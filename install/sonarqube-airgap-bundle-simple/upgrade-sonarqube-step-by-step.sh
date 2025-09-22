#!/bin/bash
set -euo pipefail

# SonarQube 단계별 업그레이드 스크립트
# 8.9.3 → 8.9.6 → 9.9.4 LTS로 안전한 단계별 업그레이드

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
NAMESPACE="${NAMESPACE:-devops}"
RELEASE_NAME="sonarqube"
CHART_PATH="./charts/devops"
VALUES_FILE="./values/sonarqube.yaml"
CHART_FILE="./charts/devops/Chart.yaml"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 단계 정의
UPGRADE_STEPS=(
    "8.9.3-community:8.9.6-community"
    "8.9.6-community:9.9.4-community"
)

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo -e "${BLUE}=== SonarQube 단계별 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}업그레이드 경로: 8.9.3 → 8.9.6 → 9.9.4 (LTS)${NC}"
echo

# 함수: 현재 버전 확인
get_current_version() {
    kubectl get deployment sonarqube -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://'
}

# 함수: 데이터베이스 백업
backup_database() {
    local step_num=$1
    echo -e "\n${BLUE}[${step_num}] 데이터베이스 백업${NC}"
    
    echo "PostgreSQL 데이터베이스 백업 중..."
    PGPASSWORD="epqmdhqtm1@" pg_dump -h gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com -p 5432 -U sonar -d sonar > "$BACKUP_DIR/sonar_database_backup_$(date +%H%M%S).sql"
    
    if [ $? -eq 0 ]; then
        echo "✅ 데이터베이스 백업 완료"
        echo "백업 파일 크기: $(du -h "$BACKUP_DIR"/sonar_database_backup_*.sql | tail -1 | cut -f1)"
    else
        echo -e "${RED}❌ 데이터베이스 백업 실패${NC}"
        read -r -p "백업 없이 계속하시겠습니까? (y/N): " backup_confirm
        if [[ ! "$backup_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
            exit 1
        fi
    fi
}

# 함수: 설정 백업
backup_config() {
    local step_num=$1
    echo -e "\n${BLUE}[${step_num}] 현재 설정 백업${NC}"
    
    mkdir -p "$BACKUP_DIR"
    cp -r values/ "$BACKUP_DIR/" 2>/dev/null || true
    cp -r charts/ "$BACKUP_DIR/" 2>/dev/null || true
    helm get values sonarqube -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
    kubectl get configmap sonarqube-config -n $NAMESPACE -o yaml > "$BACKUP_DIR/sonarqube-configmap-backup.yaml" 2>/dev/null || echo "ConfigMap 백업 생략"
    
    echo "✅ 현재 설정 백업 완료: $BACKUP_DIR"
}

# 함수: SonarQube 상태 확인
check_sonarqube_status() {
    local step_num=$1
    echo -e "\n${BLUE}[${step_num}] SonarQube 상태 확인${NC}"
    
    if ! kubectl get deployment sonarqube -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${RED}❌ SonarQube가 설치되어 있지 않습니다.${NC}"
        exit 1
    fi
    
    local current_version=$(get_current_version)
    echo "✅ 현재 버전: $current_version"
    
    kubectl get pods -n $NAMESPACE -l app=sonarqube --no-headers | while read pod_info; do
        pod_name=$(echo $pod_info | awk '{print $1}')
        status=$(echo $pod_info | awk '{print $3}')
        echo "  - Pod: $pod_name (상태: $status)"
    done
}

# 함수: 버전 업그레이드 실행
upgrade_version() {
    local from_version=$1
    local to_version=$2
    local step_num=$3
    local total_steps=$4
    
    echo -e "\n${GREEN}=== 단계 ${step_num}/${total_steps}: ${from_version} → ${to_version} ===${NC}"
    
    # 현재 버전 확인
    local current_version=$(get_current_version)
    if [[ "$current_version" != "$from_version" ]]; then
        echo -e "${YELLOW}⚠️  현재 버전($current_version)이 예상 버전($from_version)과 다릅니다.${NC}"
        read -r -p "계속하시겠습니까? (y/N): " version_confirm
        if [[ ! "$version_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
            exit 1
        fi
    fi
    
    echo -e "\n${BLUE}SonarQube 중지${NC}"
    kubectl scale deployment sonarqube --replicas=0 -n $NAMESPACE
    kubectl wait --for=delete pod -l app=sonarqube -n $NAMESPACE --timeout=300s || true
    echo "✅ SonarQube 중지 완료"
    
    echo -e "\n${BLUE}설정 파일 업데이트${NC}"
    # values/sonarqube.yaml 업데이트
    sed -i.bak "s/tag: $from_version/tag: $to_version/g" "$VALUES_FILE"
    
    # charts/devops/Chart.yaml 업데이트
    sed -i.bak "s/appVersion: \"$from_version\"/appVersion: \"$to_version\"/g" "$CHART_FILE"
    
    echo "✅ 설정 파일 업데이트 완료: $from_version → $to_version"
    
    echo -e "\n${BLUE}Helm 업그레이드 실행${NC}"
    helm upgrade $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $VALUES_FILE \
        --timeout 1800s
    
    if [ $? -eq 0 ]; then
        echo "✅ Helm 업그레이드 성공"
    else
        echo -e "${RED}❌ Helm 업그레이드 실패${NC}"
        echo "백업에서 복구하려면: helm rollback $RELEASE_NAME -n $NAMESPACE"
        exit 1
    fi
    
    echo -e "\n${BLUE}업그레이드 상태 확인${NC}"
    kubectl rollout status deployment/sonarqube -n $NAMESPACE --timeout=1800s
    
    echo -e "\n${BLUE}SonarQube 서비스 확인${NC}"
    local timeout=600
    local check_interval=30
    
    while [ $timeout -gt 0 ]; do
        if kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "1/1.*Running"; then
            echo "✅ SonarQube Pod이 정상 실행 중입니다."
            break
        else
            echo "⏳ SonarQube 시작 대기 중... (남은 시간: ${timeout}초)"
            sleep $check_interval
            timeout=$((timeout - check_interval))
        fi
    done
    
    if [ $timeout -le 0 ]; then
        echo -e "${RED}❌ SonarQube 시작 타임아웃${NC}"
        kubectl logs -n $NAMESPACE deployment/sonarqube --tail=50
        exit 1
    fi
    
    # 데이터베이스 마이그레이션 완료 대기 (9.x 업그레이드 시에만)
    if [[ "$to_version" == "9.9.4-community" ]]; then
        echo -e "\n${YELLOW}⚠️  메이저 버전 업그레이드 - 데이터베이스 마이그레이션 필요${NC}"
        echo "웹 브라우저에서 https://sonarqube-dev.secl.samsung.co.kr/setup 접속"
        echo "데이터베이스 마이그레이션을 완료하세요."
        echo
        read -r -p "데이터베이스 마이그레이션이 완료되었나요? (y/N): " migration_confirm
        if [[ ! "$migration_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️  마이그레이션을 완료한 후 계속하세요.${NC}"
            exit 1
        fi
    fi
    
    echo -e "\n${GREEN}✅ 단계 ${step_num} 완료: ${from_version} → ${to_version}${NC}"
    
    # 업그레이드 후 데이터 검증
    echo -e "\n${BLUE}데이터 검증${NC}"
    echo "웹 인터페이스에서 다음을 확인하세요:"
    echo "1. 로그인 가능 여부"
    echo "2. 기존 프로젝트 표시 여부"
    echo "3. 사용자 계정 정상 여부"
    echo
    read -r -p "데이터가 정상적으로 보이나요? (y/N): " data_confirm
    if [[ ! "$data_confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ 데이터 검증 실패 - 다음 단계 진행 중단${NC}"
        exit 1
    fi
    
    echo "✅ 데이터 검증 완료"
}

# 메인 실행
main() {
    # 초기 상태 확인
    check_sonarqube_status "1"
    
    # 설정 백업
    backup_config "2"
    
    # 데이터베이스 백업
    backup_database "3"
    
    echo -e "\n${YELLOW}⚠️  단계별 업그레이드를 시작합니다${NC}"
    echo "각 단계마다 데이터 검증을 수행합니다."
    echo "문제가 발생하면 이전 단계로 롤백할 수 있습니다."
    echo
    read -r -p "단계별 업그레이드를 시작하시겠습니까? (y/N): " start_confirm
    if [[ ! "$start_confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
        exit 1
    fi
    
    # 단계별 업그레이드 실행
    local step_num=1
    local total_steps=${#UPGRADE_STEPS[@]}
    
    for step in "${UPGRADE_STEPS[@]}"; do
        IFS=':' read -r from_version to_version <<< "$step"
        upgrade_version "$from_version" "$to_version" "$step_num" "$total_steps"
        step_num=$((step_num + 1))
        
        if [ $step_num -le $total_steps ]; then
            echo -e "\n${BLUE}다음 단계 준비 중...${NC}"
            sleep 10
        fi
    done
    
    # 최종 상태 확인
    echo -e "\n${GREEN}=== 단계별 업그레이드 완료 ===${NC}"
    
    local final_version=$(get_current_version)
    echo -e "\n📋 최종 상태:"
    echo "  버전: $final_version"
    kubectl get pods,svc,ingress -n $NAMESPACE -l app=sonarqube
    
    echo -e "\n🌐 접속 정보:"
    echo "  URL: https://sonarqube-dev.secl.samsung.co.kr"
    echo "  로그인: admin/admin (첫 로그인 시 비밀번호 변경 필요)"
    
    echo -e "\n📁 백업 위치: $BACKUP_DIR"
    echo "  - 데이터베이스 백업: $BACKUP_DIR/sonar_database_backup_*.sql"
    echo "  - 설정 백업: $BACKUP_DIR/values/, $BACKUP_DIR/charts/"
    
    echo -e "\n✅ ${GREEN}SonarQube 단계별 업그레이드가 성공적으로 완료되었습니다!${NC}"
    echo -e "최종 버전: ${final_version}"
    
    # 정리
    echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
    rm -f "$VALUES_FILE.bak" "$CHART_FILE.bak" 2>/dev/null || true
    echo "✅ 정리 완료"
}

# 스크립트 실행
main "$@"
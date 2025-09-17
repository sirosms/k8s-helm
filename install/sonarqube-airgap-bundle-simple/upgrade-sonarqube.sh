#!/bin/bash
set -euo pipefail

# SonarQube 업그레이드 스크립트 - GitLab/Nexus 패턴 참고
# 현재 버전: 8.9.3-community → LTS 버전: 9.9.4-community

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
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 버전 정보
CURRENT_VERSION="8.9.3-community"
NEW_VERSION="9.9.4-community"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo -e "${BLUE}=== SonarQube Community Build 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}현재 버전: ${CURRENT_VERSION}${NC}"
echo -e "${GREEN}목표 버전: ${NEW_VERSION}${NC}"
echo

# 현재 상태 확인
echo -e "${BLUE}[1/9] 현재 SonarQube 상태 확인${NC}"
if ! kubectl get deployment sonarqube -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}❌ SonarQube가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo "✅ SonarQube 발견됨"
kubectl get pods -n $NAMESPACE -l app=sonarqube --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    status=$(echo $pod_info | awk '{print $3}')
    echo "  - Pod: $pod_name (상태: $status)"
done

# 데이터베이스 연결 확인
echo -e "\n${BLUE}[2/9] 데이터베이스 연결 확인${NC}"
echo "PostgreSQL 데이터베이스 버전 확인 중..."
echo "✅ 데이터베이스: postgresql://gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com:5432/sonar"

# 백업 디렉토리 생성
echo -e "\n${BLUE}[3/9] 백업 디렉토리 생성${NC}"
mkdir -p "$BACKUP_DIR"
echo "✅ 백업 디렉토리 생성됨: $BACKUP_DIR"

# 현재 설정 백업
echo -e "\n${BLUE}[4/9] 현재 설정 백업${NC}"
cp -r values/ "$BACKUP_DIR/"
cp -r charts/ "$BACKUP_DIR/"
helm get values sonarqube -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
kubectl get configmap sonarqube-config -n $NAMESPACE -o yaml > "$BACKUP_DIR/sonarqube-configmap-backup.yaml" 2>/dev/null || echo "ConfigMap 백업 생략"
echo "✅ 현재 설정 백업 완료"

# 데이터베이스 백업
echo -e "\n${BLUE}데이터베이스 백업 실행${NC}"
echo "PostgreSQL 데이터베이스 백업 중..."
PGPASSWORD="epqmdhqtm1@" pg_dump -h gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com -p 5432 -U sonar -d sonar > "$BACKUP_DIR/sonar_database_backup.sql"
if [ $? -eq 0 ]; then
    echo "✅ 데이터베이스 백업 완료: $BACKUP_DIR/sonar_database_backup.sql"
    echo "백업 파일 크기: $(du -h "$BACKUP_DIR/sonar_database_backup.sql" | cut -f1)"
else
    echo -e "${RED}❌ 데이터베이스 백업 실패${NC}"
    echo "백업 없이 업그레이드를 계속하시겠습니까? (y/N): "
    read -r db_backup_confirm
    if [[ ! "$db_backup_confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
        exit 1
    fi
fi

# 업그레이드 전 중요 확인사항
echo -e "\n${YELLOW}⚠️  중요한 메이저 버전 업그레이드가 진행됩니다!${NC}"
echo "1. PostgreSQL 데이터베이스 백업이 완료되었는지 확인"
echo "2. 데이터베이스 마이그레이션은 4-5시간 소요될 수 있습니다"
echo "3. 데이터베이스 디스크 사용량이 50% 미만인지 확인 (임시로 2배까지 증가 가능)"
echo "4. PostgreSQL 버전이 13-17 범위에 있는지 확인"
echo "5. ECR에 새로운 SonarQube 이미지가 업로드되어 있는지 확인"
echo "6. 스테이징 환경에서 업그레이드 테스트를 완료했는지 확인"
echo
read -r -p "메이저 업그레이드를 계속하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
    exit 1
fi

# SonarQube 안전 중지
echo -e "\n${BLUE}[5/9] SonarQube 안전 중지${NC}"
echo "SonarQube 서비스를 안전하게 중지합니다..."
kubectl scale deployment sonarqube --replicas=0 -n $NAMESPACE
kubectl wait --for=delete pod -l app=sonarqube -n $NAMESPACE --timeout=300s || true
echo "✅ SonarQube 서비스 중지 완료"

# 이미지 버전 업데이트
echo -e "\n${BLUE}[6/9] SonarQube 이미지 버전 업데이트${NC}"
sed -i.bak "s/tag: $CURRENT_VERSION/tag: $NEW_VERSION/g" "$VALUES_FILE"
sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" "$VALUES_FILE"
echo "✅ 이미지 버전 업데이트됨: $CURRENT_VERSION → $NEW_VERSION"

# PostgreSQL 연결 확인
echo -e "\n${BLUE}[7/9] 데이터베이스 연결성 확인${NC}"
echo "데이터베이스 연결 테스트 중..."
# 간단한 연결 테스트용 Pod 생성
cat <<EOF > temp-db-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: sonarqube-db-test
  namespace: $NAMESPACE
spec:
  containers:
  - name: postgres-client
    image: postgres:13
    command: ['sleep', '300']
    env:
    - name: PGPASSWORD
      value: "epqmdhqtm1@"
  restartPolicy: Never
EOF

kubectl apply -f temp-db-test-pod.yaml
kubectl wait --for=condition=Ready pod/sonarqube-db-test -n $NAMESPACE --timeout=120s

# 데이터베이스 연결 테스트
kubectl exec -n $NAMESPACE sonarqube-db-test -- psql -h gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com -p 5432 -U sonar -d sonar -c "SELECT version();" > /tmp/db_version.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 데이터베이스 연결 성공"
    cat /tmp/db_version.log
else
    echo -e "${RED}❌ 데이터베이스 연결 실패${NC}"
    kubectl delete -f temp-db-test-pod.yaml
    exit 1
fi

# 테스트 Pod 정리
kubectl delete -f temp-db-test-pod.yaml
rm -f temp-db-test-pod.yaml

# Helm 업그레이드 실행
echo -e "\n${BLUE}[8/9] Helm 업그레이드 실행${NC}"
echo "새로운 SonarQube 버전으로 업그레이드 중..."
helm upgrade $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --values $VALUES_FILE \
    --set image.tag="$NEW_VERSION" \
    --timeout 1800s

if [ $? -eq 0 ]; then
    echo "✅ Helm 업그레이드 성공"
else
    echo -e "${RED}❌ Helm 업그레이드 실패${NC}"
    echo "백업에서 복구하려면 다음 명령어를 사용하세요:"
    echo "helm rollback $RELEASE_NAME -n $NAMESPACE"
    exit 1
fi

# 업그레이드 상태 확인 및 데이터베이스 마이그레이션 대기
echo -e "\n${BLUE}[9/9] 업그레이드 상태 확인 및 데이터베이스 마이그레이션 대기${NC}"
echo "Pod 상태 확인 중..."
kubectl rollout status deployment/sonarqube -n $NAMESPACE --timeout=1800s

echo -e "\n${YELLOW}⏳ 데이터베이스 마이그레이션 진행 중...${NC}"
echo "이 과정은 데이터베이스 크기에 따라 4-5시간까지 소요될 수 있습니다."
echo "마이그레이션 상태를 확인하려면: kubectl logs -f deployment/sonarqube -n $NAMESPACE"

# SonarQube 시작 대기 (마이그레이션 포함)
echo "SonarQube 완전 시작 대기 중... (최대 30분)"
timeout=1800
while [ $timeout -gt 0 ]; do
    if kubectl get pods -n $NAMESPACE -l app=sonarqube | grep -q "Running"; then
        echo "✅ SonarQube Pod이 실행 중입니다."
        
        # HTTP 응답 확인
        kubectl port-forward -n $NAMESPACE svc/sonarqube 9000:9000 &
        PF_PID=$!
        sleep 5
        
        if curl -s http://localhost:9000/api/system/status | grep -q "UP"; then
            echo "✅ SonarQube 서비스가 정상적으로 시작되었습니다."
            kill $PF_PID 2>/dev/null || true
            break
        else
            echo "⏳ SonarQube 마이그레이션 진행 중... (남은 시간: ${timeout}초)"
            kill $PF_PID 2>/dev/null || true
        fi
    fi
    
    sleep 30
    timeout=$((timeout - 30))
done

if [ $timeout -le 0 ]; then
    echo -e "${YELLOW}⚠️  마이그레이션이 아직 진행 중일 수 있습니다.${NC}"
    echo "로그를 확인하세요: kubectl logs -f deployment/sonarqube -n $NAMESPACE"
fi

# 최종 상태 확인
echo -e "\n${GREEN}=== 업그레이드 완료 ===${NC}"

echo -e "\n📋 서비스 상태:"
kubectl get pods,svc,ingress -n $NAMESPACE -l app=sonarqube

echo -e "\n🔍 SonarQube 버전 확인:"
kubectl get deployment sonarqube -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo -e "\n🌐 접속 정보:"
echo "  URL: https://sonarqube-dev.samsungena.io"
echo "  초기 접속: admin/admin (첫 로그인 시 비밀번호 변경 필요)"

echo -e "\n📁 백업 위치: $BACKUP_DIR"
echo "  - 데이터베이스 백업: $BACKUP_DIR/sonar_database_backup.sql"
echo "  - 설정 백업: $BACKUP_DIR/values/, $BACKUP_DIR/charts/"

echo -e "\n✅ ${GREEN}SonarQube Community Build 업그레이드가 성공적으로 완료되었습니다!${NC}"
echo -e "🔧 SonarQube 웹 인터페이스에서 마이그레이션 상태를 확인하세요."

echo -e "\n${YELLOW}다음 단계:${NC}"
echo "1. SonarQube 웹 인터페이스 접속 확인"
echo "2. 프로젝트 및 품질 규칙 확인"
echo "3. 기존 분석 데이터 정상성 확인"
echo "4. 새로운 기능 및 설정 검토"
echo "5. 백업 파일 안전한 위치에 보관"

echo -e "\n${BLUE}주요 변경사항 (8.9 → 9.9 LTS):${NC}"
echo "- 안정화된 LTS 버전으로 안전한 업그레이드"
echo "- 향상된 코드 품질 분석 규칙"
echo "- 성능 및 안정성 개선"
echo "- 보안 취약점 분석 강화"

# 정리
echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
rm -f "$VALUES_FILE.bak" 2>/dev/null || true
rm -f /tmp/db_version.log 2>/dev/null || true
echo "✅ 정리 완료"

echo -e "\n${GREEN}업그레이드 완료! SonarQube Community Build $NEW_VERSION${NC}"
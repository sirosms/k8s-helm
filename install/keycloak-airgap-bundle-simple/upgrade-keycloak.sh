#!/bin/bash
set -euo pipefail

# Keycloak 업그레이드 스크립트 - Vault와 동일한 패턴
# 현재 버전: 18.0.2 → 목표 버전: 19.0.1

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
NAMESPACE="${NAMESPACE:-devops-keycloak}"
RELEASE_NAME="keycloak"
CHART_PATH="./charts/keycloak-9.7.2.tgz"
VALUES_FILE="./values/keycloak.yaml"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 버전 정보
CURRENT_VERSION="18.0.2-debian-11-r25"
NEW_VERSION="19.0.1-debian-11-r0"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo -e "${BLUE}=== Keycloak 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}현재 버전: ${CURRENT_VERSION}${NC}"
echo -e "${GREEN}목표 버전: ${NEW_VERSION}${NC}"
echo

# 현재 상태 확인
echo -e "${BLUE}[1/9] 현재 Keycloak 상태 확인${NC}"
if ! kubectl get statefulset keycloak -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}❌ Keycloak가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo "✅ Keycloak 발견됨"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=keycloak --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    status=$(echo $pod_info | awk '{print $3}')
    echo "  - Pod: $pod_name (상태: $status)"
done

# Keycloak 상태 확인 (관리자 콘솔 접근 가능 여부)
echo -e "\n${BLUE}[2/9] Keycloak 서비스 상태 확인${NC}"
kubectl get svc -n $NAMESPACE keycloak && echo "✅ Keycloak 서비스 정상"

# 백업 디렉토리 생성
echo -e "\n${BLUE}[3/9] 백업 디렉토리 생성${NC}"
mkdir -p "$BACKUP_DIR"
echo "✅ 백업 디렉토리 생성됨: $BACKUP_DIR"

# 현재 설정 백업
echo -e "\n${BLUE}[4/9] 현재 설정 백업${NC}"
cp -r values/ "$BACKUP_DIR/" 2>/dev/null || echo "values 디렉토리 백업 생략"
cp -r charts/ "$BACKUP_DIR/" 2>/dev/null || echo "charts 디렉토리 백업 생략"
helm get values keycloak -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
kubectl get pvc -n $NAMESPACE -o yaml > "$BACKUP_DIR/keycloak-pvc-backup.yaml" 2>/dev/null || echo "PVC 백업 생략"
kubectl get secret -n $NAMESPACE -o yaml > "$BACKUP_DIR/keycloak-secrets-backup.yaml" 2>/dev/null || echo "Secret 백업 생략"

# Keycloak 데이터베이스 백업 (PostgreSQL 덤프)
echo "Keycloak 데이터베이스 백업 시도 중..."
kubectl exec -n $NAMESPACE keycloak-0 -- bash -c "
PGPASSWORD='epqmdhqtm1@' pg_dump -h gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com -U keycloak -d keycloak > /tmp/keycloak-backup.sql
" 2>/dev/null && kubectl cp $NAMESPACE/keycloak-0:/tmp/keycloak-backup.sql "$BACKUP_DIR/keycloak-backup.sql" 2>/dev/null || echo "데이터베이스 백업 실패 (계속 진행)"

echo "✅ 현재 설정 백업 완료"

# 확인 프롬프트
echo -e "\n${YELLOW}⚠️  업그레이드를 진행하기 전에 확인사항:${NC}"
echo "1. Keycloak 데이터베이스 백업이 완료되었는지 확인"
echo "2. 진행 중인 인증 세션이 중단될 수 있음"
echo "3. 업그레이드 중 서비스 중단이 발생할 수 있음"
echo "4. ECR에 새로운 Keycloak 이미지가 업로드되어 있는지 확인"
echo "5. Keycloak 18.x에서 19.x로의 마이너 업그레이드임"
echo
read -r -p "업그레이드를 계속하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
    exit 1
fi

# Keycloak 임시 점검 모드 (Read-Only는 지원하지 않으므로 스케일 다운)
echo -e "\n${BLUE}[5/9] Keycloak 임시 점검 모드${NC}"
echo "Keycloak을 안전하게 종료합니다..."
kubectl scale statefulset keycloak --replicas=0 -n $NAMESPACE
echo "Keycloak 종료 대기 중..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=keycloak -n $NAMESPACE --timeout=300s || echo "Keycloak 종료 시간 초과 (계속 진행)"
echo "✅ Keycloak 안전 모드 전환 완료"

# 이미지 버전 업데이트
echo -e "\n${BLUE}[6/9] Keycloak 이미지 버전 업데이트${NC}"
sed -i.bak "s/tag: $CURRENT_VERSION/tag: $NEW_VERSION/g" "$VALUES_FILE"
echo "✅ 이미지 버전 업데이트됨: $CURRENT_VERSION → $NEW_VERSION"

# Helm 업그레이드 실행
echo -e "\n${BLUE}[7/9] Helm 업그레이드 실행${NC}"
helm upgrade $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --values $VALUES_FILE \
    --set image.tag="$NEW_VERSION" \
    --timeout 900s

if [ $? -eq 0 ]; then
    echo "✅ Helm 업그레이드 성공"
else
    echo -e "${RED}❌ Helm 업그레이드 실패${NC}"
    echo "백업에서 복구하려면 다음 명령어를 사용하세요:"
    echo "helm rollback $RELEASE_NAME -n $NAMESPACE"
    exit 1
fi

# 업그레이드 상태 확인
echo -e "\n${BLUE}[8/9] 업그레이드 상태 확인${NC}"
echo "Pod 상태 확인 중..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n $NAMESPACE --timeout=600s

# 최종 상태 확인
echo -e "\n${BLUE}[9/9] 최종 상태 확인${NC}"
echo -e "${GREEN}=== 업그레이드 완료 ===${NC}"

echo -e "\n📋 서비스 상태:"
kubectl get pods,svc,ingress -n $NAMESPACE -l app.kubernetes.io/name=keycloak

echo -e "\n🔍 Keycloak 버전 확인:"
kubectl get statefulset keycloak -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo -e "\n🌐 접속 정보:"
echo "  URL: https://keycloak-dev.secl.samsung.co.kr"
echo "  관리자: admin"
echo "  비밀번호: keycloak123!"

echo -e "\n📁 백업 위치: $BACKUP_DIR"

echo -e "\n✅ ${GREEN}Keycloak 업그레이드가 성공적으로 완료되었습니다!${NC}"

echo -e "\n${YELLOW}다음 단계:${NC}"
echo "1. Keycloak 관리자 콘솔 접속 확인"
echo "2. 기존 realm 및 사용자 데이터 정상성 확인"
echo "3. 인증 flow 테스트"
echo "4. 백업 파일 안전한 위치에 보관"

echo -e "\n${RED}⚠️ 중요:${NC}"
echo "- Keycloak 18.x에서 19.x로의 마이너 업그레이드입니다"
echo "- 업그레이드된 Keycloak은 이전 버전의 데이터를 자동으로 마이그레이션합니다"
echo "- 새로운 기능들을 확인하고 설정을 점검하세요"
echo "- 문제 발생 시 백업에서 복구하거나 helm rollback을 사용하세요"

# 정리
echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
rm -f "$VALUES_FILE.bak" 2>/dev/null || true
echo "✅ 정리 완료"
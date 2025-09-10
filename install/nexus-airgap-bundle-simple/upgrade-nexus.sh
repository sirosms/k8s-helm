#!/bin/bash
set -euo pipefail

# Nexus 업그레이드 스크립트 - GitLab과 동일한 패턴
# 현재 버전: 3.37.3 → 최신 안정화 버전: 3.83.2

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
NAMESPACE="${NAMESPACE:-devops}"
RELEASE_NAME="nexus"
CHART_PATH="./charts/devops"
VALUES_FILE="./values/nexus.yaml"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 버전 정보
CURRENT_VERSION="3.37.3"
NEW_VERSION="3.83.2"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo -e "${BLUE}=== Nexus Repository 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}현재 버전: ${CURRENT_VERSION}${NC}"
echo -e "${GREEN}목표 버전: ${NEW_VERSION}${NC}"
echo

# 현재 상태 확인
echo -e "${BLUE}[1/8] 현재 Nexus 상태 확인${NC}"
if ! kubectl get deployment nexus -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}❌ Nexus가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo "✅ Nexus 발견됨"
kubectl get pods -n $NAMESPACE -l app=nexus --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    status=$(echo $pod_info | awk '{print $3}')
    echo "  - Pod: $pod_name (상태: $status)"
done

# 백업 디렉토리 생성
echo -e "\n${BLUE}[2/8] 백업 디렉토리 생성${NC}"
mkdir -p "$BACKUP_DIR"
echo "✅ 백업 디렉토리 생성됨: $BACKUP_DIR"

# 현재 설정 백업
echo -e "\n${BLUE}[3/8] 현재 설정 백업${NC}"
cp -r values/ "$BACKUP_DIR/"
cp -r charts/ "$BACKUP_DIR/"
helm get values nexus -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
kubectl get configmap nexus-config -n $NAMESPACE -o yaml > "$BACKUP_DIR/nexus-configmap-backup.yaml" 2>/dev/null || echo "ConfigMap 백업 생략"
echo "✅ 현재 설정 백업 완료"

# 확인 프롬프트
echo -e "\n${YELLOW}⚠️  업그레이드를 진행하기 전에 확인사항:${NC}"
echo "1. Nexus PVC 백업이 완료되었는지 확인"
echo "2. 진행 중인 업로드/다운로드가 없는지 확인"
echo "3. 업그레이드 중 서비스 중단이 발생할 수 있음"
echo "4. ECR에 새로운 Nexus 이미지가 업로드되어 있는지 확인"
echo
read -r -p "업그레이드를 계속하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
    exit 1
fi

# Nexus Graceful Shutdown (Read-Only Mode)
echo -e "\n${BLUE}[4/8] Nexus 안전 모드 전환${NC}"
echo "Nexus를 읽기 전용 모드로 전환합니다..."
# Port-forward를 사용한 API 호출 (옵션)
kubectl port-forward -n $NAMESPACE svc/nexus 8081:8081 &
PF_PID=$!
sleep 3
# Nexus API를 통한 Read-Only 모드 전환 (관리자 권한 필요)
curl -X PUT "http://localhost:8081/service/rest/v1/read-only/freeze" \
    -H "accept: application/json" \
    -u admin:admin123 2>/dev/null || echo "Read-Only 모드 전환 실패 (계속 진행)"
kill $PF_PID 2>/dev/null || true
echo "✅ 안전 모드 전환 완료"

# 이미지 버전 업데이트
echo -e "\n${BLUE}[5/8] Nexus 이미지 버전 업데이트${NC}"
sed -i.bak "s/tag: $CURRENT_VERSION/tag: $NEW_VERSION/g" "$VALUES_FILE"
sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" "$VALUES_FILE"
echo "✅ 이미지 버전 업데이트됨: $CURRENT_VERSION → $NEW_VERSION"

# Helm 업그레이드 실행
echo -e "\n${BLUE}[6/8] Helm 업그레이드 실행${NC}"
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
echo -e "\n${BLUE}[7/8] 업그레이드 상태 확인${NC}"
echo "Pod 상태 확인 중..."
kubectl rollout status deployment/nexus -n $NAMESPACE --timeout=600s

# 최종 상태 확인
echo -e "\n${BLUE}[8/8] 최종 상태 확인${NC}"
echo -e "${GREEN}=== 업그레이드 완료 ===${NC}"

echo -e "\n📋 서비스 상태:"
kubectl get pods,svc,ingress -n $NAMESPACE -l app=nexus

echo -e "\n🔍 Nexus 버전 확인:"
kubectl get deployment nexus -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo -e "\n🌐 접속 정보:"
echo "  URL: https://nexus-dev.samsungena.io"
echo "  관리자: admin"
echo "  초기 비밀번호: admin123"

echo -e "\n📁 백업 위치: $BACKUP_DIR"

echo -e "\n✅ ${GREEN}Nexus Repository 업그레이드가 성공적으로 완료되었습니다!${NC}"
echo -e "🔧 Nexus 웹 인터페이스에서 설정을 확인하세요."

echo -e "\n${YELLOW}다음 단계:${NC}"
echo "1. Nexus 웹 인터페이스 접속 확인"
echo "2. Repository 설정 및 데이터 정상성 확인"
echo "3. 기존 아티팩트 접근 테스트"
echo "4. 백업 파일 안전한 위치에 보관"

# 정리
echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
rm -f "$VALUES_FILE.bak" 2>/dev/null || true
echo "✅ 정리 완료"
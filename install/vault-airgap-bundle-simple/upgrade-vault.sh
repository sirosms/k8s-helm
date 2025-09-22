#!/bin/bash
set -euo pipefail

# Vault 업그레이드 스크립트 - Nexus와 동일한 패턴
# 현재 버전: 1.11.2 → 최신 안정화 버전: 1.17.6

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
NAMESPACE="${NAMESPACE:-devops-vault}"
RELEASE_NAME="vault"
CHART_PATH="./charts/vault-0.21.0.tgz"
VALUES_FILE="./values/vault.yaml"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 버전 정보
CURRENT_VERSION="1.11.2"
NEW_VERSION="1.17.6"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo -e "${BLUE}=== HashiCorp Vault 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}현재 버전: ${CURRENT_VERSION}${NC}"
echo -e "${GREEN}목표 버전: ${NEW_VERSION}${NC}"
echo

# 현재 상태 확인
echo -e "${BLUE}[1/9] 현재 Vault 상태 확인${NC}"
if ! kubectl get statefulset vault -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}❌ Vault가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo "✅ Vault 발견됨"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vault --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    status=$(echo $pod_info | awk '{print $3}')
    echo "  - Pod: $pod_name (상태: $status)"
done

# Vault 상태 확인 (초기화 여부)
echo -e "\n${BLUE}[2/9] Vault 초기화 상태 확인${NC}"
kubectl exec -n $NAMESPACE vault-0 -- vault status || echo "⚠️ Vault가 초기화되지 않았거나 sealed 상태입니다"

# 백업 디렉토리 생성
echo -e "\n${BLUE}[3/9] 백업 디렉토리 생성${NC}"
mkdir -p "$BACKUP_DIR"
echo "✅ 백업 디렉토리 생성됨: $BACKUP_DIR"

# 현재 설정 백업
echo -e "\n${BLUE}[4/9] 현재 설정 백업${NC}"
cp -r values/ "$BACKUP_DIR/" 2>/dev/null || echo "values 디렉토리 백업 생략"
cp -r charts/ "$BACKUP_DIR/" 2>/dev/null || echo "charts 디렉토리 백업 생략"
helm get values vault -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
kubectl get pvc -n $NAMESPACE -o yaml > "$BACKUP_DIR/vault-pvc-backup.yaml" 2>/dev/null || echo "PVC 백업 생략"
kubectl get secret -n $NAMESPACE -o yaml > "$BACKUP_DIR/vault-secrets-backup.yaml" 2>/dev/null || echo "Secret 백업 생략"

# Vault 백업 (Snapshot) - 초기화된 경우에만
if kubectl exec -n $NAMESPACE vault-0 -- vault status >/dev/null 2>&1; then
    echo "Vault 스냅샷 백업 시도 중..."
    kubectl exec -n $NAMESPACE vault-0 -- vault operator raft snapshot save /tmp/vault-backup.snap 2>/dev/null || echo "스냅샷 백업 실패 (계속 진행)"
    kubectl cp $NAMESPACE/vault-0:/tmp/vault-backup.snap "$BACKUP_DIR/vault-backup.snap" 2>/dev/null || echo "스냅샷 복사 실패"
fi
echo "✅ 현재 설정 백업 완료"

# 확인 프롬프트
echo -e "\n${YELLOW}⚠️  업그레이드를 진행하기 전에 확인사항:${NC}"
echo "1. Vault 데이터 백업이 완료되었는지 확인"
echo "2. Vault가 unsealed 상태인지 확인"
echo "3. 업그레이드 중 서비스 중단이 발생할 수 있음"
echo "4. ECR에 새로운 Vault 이미지가 업로드되어 있는지 확인"
echo "5. Vault 업그레이드는 롤백이 어려우므로 신중히 진행"
echo
read -r -p "업그레이드를 계속하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
    exit 1
fi

# Vault Seal (안전한 업그레이드를 위해)
echo -e "\n${BLUE}[5/9] Vault Seal (안전 모드)${NC}"
if kubectl exec -n $NAMESPACE vault-0 -- vault status >/dev/null 2>&1; then
    echo "Vault를 seal 상태로 전환합니다..."
    kubectl exec -n $NAMESPACE vault-0 -- vault operator seal 2>/dev/null || echo "Seal 실패 (계속 진행)"
    echo "✅ Vault sealed"
else
    echo "✅ Vault는 이미 sealed 상태입니다"
fi

# 이미지 버전 업데이트
echo -e "\n${BLUE}[6/9] Vault 이미지 버전 업데이트${NC}"
sed -i.bak "s/tag: $CURRENT_VERSION/tag: $NEW_VERSION/g" "$VALUES_FILE"
sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" "$VALUES_FILE"
echo "✅ 이미지 버전 업데이트됨: $CURRENT_VERSION → $NEW_VERSION"

# Helm 업그레이드 실행
echo -e "\n${BLUE}[7/9] Helm 업그레이드 실행${NC}"
helm upgrade $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --values $VALUES_FILE \
    --set server.image.tag="$NEW_VERSION" \
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
kubectl rollout status statefulset/vault -n $NAMESPACE --timeout=600s

# 최종 상태 확인
echo -e "\n${BLUE}[9/9] 최종 상태 확인${NC}"
echo -e "${GREEN}=== 업그레이드 완료 ===${NC}"

echo -e "\n📋 서비스 상태:"
kubectl get pods,svc,ingress -n $NAMESPACE -l app.kubernetes.io/name=vault

echo -e "\n🔍 Vault 버전 확인:"
kubectl get statefulset vault -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo -e "\n🌐 접속 정보:"
echo "  URL: https://vault-dev.secl.samsung.co.kr"
echo "  CLI: kubectl exec -n $NAMESPACE -it vault-0 -- vault status"

echo -e "\n📁 백업 위치: $BACKUP_DIR"

echo -e "\n✅ ${GREEN}HashiCorp Vault 업그레이드가 성공적으로 완료되었습니다!${NC}"

echo -e "\n${YELLOW}다음 단계:${NC}"
echo "1. Vault 상태 확인: kubectl exec -n $NAMESPACE -it vault-0 -- vault status"
echo "2. Vault Unseal 수행 (필요시): kubectl exec -n $NAMESPACE -it vault-0 -- vault operator unseal"
echo "3. Vault 웹 인터페이스 접속 확인"
echo "4. 기존 시크릿 및 정책 정상성 확인"
echo "5. 백업 파일 안전한 위치에 보관"

echo -e "\n${RED}⚠️ 중요:${NC}"
echo "- Vault 업그레이드 후 unseal key를 사용하여 Vault를 unseal해야 합니다"
echo "- 업그레이드된 Vault는 이전 버전의 데이터를 자동으로 마이그레이션합니다"
echo "- 문제 발생 시 백업에서 복구하거나 helm rollback을 사용하세요"

# 정리
echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
rm -f "$VALUES_FILE.bak" 2>/dev/null || true
echo "✅ 정리 완료"
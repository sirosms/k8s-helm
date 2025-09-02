#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="devops-mattermost"
RELEASE_NAME="mattermost"
CHART_PATH="./charts/mattermost-team-edition-6.6.11.tgz"
VALUES_FILE="./values/mattermost.yaml"

echo "=== Mattermost 설치 스크립트 ==="

# Mattermost 설정 입력
echo "Mattermost 설정을 입력하세요:"
read -r -p "Mattermost 외부 URL [https://mattermost-dev.samsungena.io]: " MATTERMOST_URL
MATTERMOST_URL=${MATTERMOST_URL:-https://mattermost-dev.samsungena.io}

read -r -p "관리자 이메일 [admin@samsungena.io]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@samsungena.io}

echo
echo "입력된 설정:"
echo "  Mattermost URL: $MATTERMOST_URL"
echo "  관리자 이메일: $ADMIN_EMAIL"
echo

# PVC 생성 확인
echo "💡 Mattermost용 PVC가 미리 생성되어 있는지 확인하세요:"
echo "   - mattermost-data (10Gi)"
echo "   - mattermost-plugins (1Gi)"
echo
read -r -p "PVC가 준비되어 있습니까? (y/N): " pvc_ready
if [[ ! "$pvc_ready" =~ ^[Yy]$ ]]; then
    echo "❌ PVC를 먼저 생성한 후 다시 실행해주세요."
    echo "   kubectl apply -f pvc/mattermost-pvc.yaml"
    exit 1
fi

# 네임스페이스 생성
echo "[1/3] 네임스페이스 생성"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Helm 차트 패키징 (필요한 경우)
echo "[2/3] Helm 차트 패키징"
if [ ! -f "mattermost-0.1.0.tgz" ]; then
    helm package ${CHART_PATH} .
fi

# Helm 설치
echo "[3/3] Mattermost 설치"
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --set ingress.host="$(echo $MATTERMOST_URL | sed 's|https\?://||')" \
  --set image.repository="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/mattermost-team-edition" \
  --set image.tag="7.2.0" \
  --set ingress.tls.secretName="samsungena.io-tls" \
  --timeout 900s

echo
echo "설치 상태 확인:"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}

echo
echo "✅ Mattermost 설치 완료!"
echo "📝 웹 브라우저에서 초기 설정을 진행하세요"
echo "🌐 접속 URL: $MATTERMOST_URL"
echo
echo "포트 포워딩으로 접속 테스트:"
echo "kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 8065:8065"
echo "브라우저에서 http://localhost:8065 접속"
echo
echo "데이터베이스 연결 확인:"
echo "kubectl logs -n ${NAMESPACE} \$(kubectl get pod -n ${NAMESPACE} -l app=mattermost -o jsonpath='{.items[0].metadata.name}')"
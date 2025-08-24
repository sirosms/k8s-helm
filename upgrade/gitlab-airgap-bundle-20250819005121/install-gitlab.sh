#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="gitlab"
RELEASE_NAME="gitlab"
CHART_PATH="./charts/gitlab-9.2.1.tgz"
VALUES_FILE="./values/values-offline-example.yaml"

echo "=== GitLab 설치 스크립트 ==="

# PostgreSQL 설정 입력
echo "PostgreSQL 데이터베이스 설정을 입력하세요:"
read -r -p "PostgreSQL 호스트 (예: postgres.example.com): " POSTGRES_HOST
read -r -p "PostgreSQL 포트 [5432]: " POSTGRES_PORT
POSTGRES_PORT=${POSTGRES_PORT:-5432}
read -r -p "데이터베이스 이름 [gitlab]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-gitlab}
read -r -p "PostgreSQL 사용자명 [gitlab]: " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-gitlab}
read -r -s -p "PostgreSQL 패스워드: " POSTGRES_PASSWORD
echo

# GitLab 도메인 설정
echo
read -r -p "GitLab 외부 URL (예: https://gitlab.example.com): " GITLAB_EXTERNAL_URL
GITLAB_EXTERNAL_URL=${GITLAB_EXTERNAL_URL:-https://gitlab.local}

# 입력값 검증
if [ -z "$POSTGRES_HOST" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    echo "❌ 오류: PostgreSQL 호스트와 패스워드는 필수입니다."
    exit 1
fi

echo "입력된 설정:"
echo "  PostgreSQL 호스트: $POSTGRES_HOST"
echo "  PostgreSQL 포트: $POSTGRES_PORT"
echo "  데이터베이스: $POSTGRES_DB"
echo "  사용자: $POSTGRES_USER"
echo "  GitLab URL: $GITLAB_EXTERNAL_URL"
echo

# PVC 생성 확인
echo "💡 GitLab용 PVC가 미리 생성되어 있는지 확인하세요:"
echo "   - gitlab-opt-dev"
echo "   - gitlab-etc-dev"
echo "   - gitlab-log-dev"
echo
read -r -p "PVC들이 준비되어 있습니까? (y/N): " pvc_ready
if [[ ! "$pvc_ready" =~ ^[Yy]$ ]]; then
    echo "❌ PVC를 먼저 생성한 후 다시 실행해주세요."
    echo "예시:"
    echo "kubectl create -f pvc/gitlab-pvc.yaml"
    exit 1
fi

# 네임스페이스 생성
echo "[1/4] 네임스페이스 생성"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# GitLab Secret 생성
echo "[2/4] GitLab Secret 생성"
kubectl create secret generic gitlab-postgres-secret \
  --from-literal=db-password="$POSTGRES_PASSWORD" \
  --namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# 내부 레지스트리 Secret 생성 (필요시)
echo "[3/4] 내부 레지스트리 인증 Secret 확인"
if ! kubectl get secret registry-local-credential -n ${NAMESPACE} >/dev/null 2>&1; then
    echo "⚠️  내부 레지스트리 인증 Secret이 없습니다."
    echo "   필요시 다음 명령으로 생성하세요:"
    echo "   kubectl create secret docker-registry registry-local-credential \\"
    echo "     --docker-server=registry.local:5000 \\"
    echo "     --docker-username=<username> \\"
    echo "     --docker-password=<password> \\"
    echo "     --namespace ${NAMESPACE}"
fi

# Helm 설치
echo "[4/4] GitLab 설치"
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --set env.open.EXTERNAL_URL="$GITLAB_EXTERNAL_URL" \
  --set env.open.DB_HOST="$POSTGRES_HOST" \
  --set env.open.DB_PORT="$POSTGRES_PORT" \
  --set env.open.DB_DATABASE="$POSTGRES_DB" \
  --set env.open.DB_USERNAME="$POSTGRES_USER" \
  --set env.secret.DB_PASSWORD="$POSTGRES_PASSWORD" \
  --set certmanager-issuer.email=myeongs.seo@partner.samsung.com \
  --set certmanager.install=false \
  --timeout 900s

echo
echo "설치 상태 확인:"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}

echo
echo "✅ GitLab 설치 완료!"
echo "📝 초기 root 패스워드: Passw0rd!"
echo "🌐 접속 URL: $GITLAB_EXTERNAL_URL"
echo
echo "포트 포워딩으로 접속 테스트:"
echo "kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 8443:443"
echo "브라우저에서 https://localhost:8443 접속"
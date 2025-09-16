#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="devops"
RELEASE_NAME="gitlab"
CHART_PATH="./charts/gitlab-0.1.0.tgz"
VALUES_FILE="./values/gitlab.yaml"

echo "=== GitLab Simple 설치 스크립트 ==="

# PostgreSQL 설정 입력
echo "PostgreSQL 데이터베이스 설정을 입력하세요:"
read -r -p "PostgreSQL 호스트 [postgresql.postgres.svc.cluster.local]: " POSTGRES_HOST
POSTGRES_HOST=${POSTGRES_HOST:-postgresql.postgres.svc.cluster.local}
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
read -r -p "GitLab 외부 URL [https://gitlab.local]: " GITLAB_EXTERNAL_URL
GITLAB_EXTERNAL_URL=${GITLAB_EXTERNAL_URL:-https://gitlab.local}

# 입력값 검증
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "❌ 오류: PostgreSQL 패스워드는 필수입니다."
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
echo "   - gitlab-opt"
echo "   - gitlab-etc"
echo "   - gitlab-log"
echo
read -r -p "PVC들이 준비되어 있습니까? (y/N): " pvc_ready
if [[ ! "$pvc_ready" =~ ^[Yy]$ ]]; then
    echo "❌ PVC를 먼저 생성한 후 다시 실행해주세요."
    exit 1
fi

# 네임스페이스 생성
echo "[1/2] 네임스페이스 생성"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Helm 설치
echo "[2/2] GitLab 설치"
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --set env.open.EXTERNAL_URL="$GITLAB_EXTERNAL_URL" \
  --set env.open.DB_HOST="$POSTGRES_HOST" \
  --set env.open.DB_PORT="$POSTGRES_PORT" \
  --set env.open.DB_DATABASE="$POSTGRES_DB" \
  --set env.open.DB_USERNAME="$POSTGRES_USER" \
  --set env.secret.DB_PASSWORD="$POSTGRES_PASSWORD" \
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
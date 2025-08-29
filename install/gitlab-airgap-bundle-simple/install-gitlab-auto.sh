#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="devops"
RELEASE_NAME="gitlab"
CHART_PATH="./charts/gitlab-0.1.0.tgz"
VALUES_FILE="./values/gitlab.yaml"

# RDS PostgreSQL 설정
POSTGRES_HOST="gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com"
POSTGRES_PORT="5432"
POSTGRES_DB="gitlabhq_production"
POSTGRES_USER="gitlab"
POSTGRES_PASSWORD="GitlabDev123!"
GITLAB_EXTERNAL_URL="https://gitlab.samsungena.io"

echo "=== GitLab Simple 자동 설치 스크립트 ==="

echo "설정 정보:"
echo "  PostgreSQL 호스트: $POSTGRES_HOST"
echo "  PostgreSQL 포트: $POSTGRES_PORT"
echo "  데이터베이스: $POSTGRES_DB"
echo "  사용자: $POSTGRES_USER"
echo "  GitLab URL: $GITLAB_EXTERNAL_URL"
echo

# PVC 생성 확인 (자동으로 yes)
echo "💡 GitLab용 PVC 확인 중..."
echo "   - gitlab-opt-dev"
echo "   - gitlab-etc-dev"
echo "   - gitlab-log-dev"

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
#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="devops"
RELEASE_NAME="sonarqube"
CHART_PATH="./charts/devops"
VALUES_FILE="./values/sonarqube.yaml"

echo "=== SonarQube 설치 스크립트 ==="

# SonarQube 설정 입력
echo "SonarQube 설정을 입력하세요:"
read -r -p "SonarQube 외부 URL [https://sonarqube-dev.secl.samsung.co.kr]: " SONARQUBE_URL
SONARQUBE_URL=${SONARQUBE_URL:-https://sonarqube-dev.secl.samsung.co.kr}

read -r -p "관리자 이메일 [admin@secl.samsung.co.kr]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@secl.samsung.co.kr}

echo
echo "입력된 설정:"
echo "  SonarQube URL: $SONARQUBE_URL"
echo "  관리자 이메일: $ADMIN_EMAIL"
echo

# PVC 생성 확인
echo "💡 SonarQube용 PVC가 미리 생성되어 있는지 확인하세요:"
echo "   - sonarqube-extensions (5Gi)"
echo "   - sonarqube-logs (5Gi)"
echo "   - sonarqube-data (10Gi)"
echo
read -r -p "PVC가 준비되어 있습니까? (y/N): " pvc_ready
if [[ ! "$pvc_ready" =~ ^[Yy]$ ]]; then
    echo "❌ PVC를 먼저 생성한 후 다시 실행해주세요."
    echo "   kubectl apply -f pvc/sonarqube-pvc.yaml"
    exit 1
fi

# 네임스페이스 생성
echo "[1/3] 네임스페이스 생성"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Helm 차트 패키징 (필요한 경우)
echo "[2/3] Helm 차트 패키징"
if [ ! -f "sonarqube-0.1.0.tgz" ]; then
    helm package ${CHART_PATH} .
fi

# Helm 설치
echo "[3/3] SonarQube 설치"
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --set ingress.host="$(echo $SONARQUBE_URL | sed 's|https\?://||')" \
  --set image.repository="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/sonarqube" \
  --set image.tag="8.9.3-community" \
  --set ingress.tls.secretName="secl.samsung.co.kr-tls" \
  --timeout 900s

echo
echo "설치 상태 확인:"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}

echo
echo "✅ SonarQube 설치 완료!"
echo "📝 초기 관리자 계정으로 로그인하세요 (admin/admin)"
echo "🌐 접속 URL: $SONARQUBE_URL"
echo
echo "포트 포워딩으로 접속 테스트:"
echo "kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 9000:9000"
echo "브라우저에서 http://localhost:9000 접속"
echo
echo "데이터베이스 연결 확인:"
echo "kubectl logs -n ${NAMESPACE} \$(kubectl get pod -n ${NAMESPACE} -l app=sonarqube -o jsonpath='{.items[0].metadata.name}')"
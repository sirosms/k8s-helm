#!/bin/bash

# Keycloak 설치 스크립트

set -e

NAMESPACE="devops-keycloak"
APP_NAME="keycloak"

echo "=== Keycloak 설치 시작 ==="

# 네임스페이스 확인 및 생성
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 $NAMESPACE 이미 존재"
fi

# Helm 차트 설치
echo "Keycloak Helm 차트 설치 중..."
helm upgrade --install $APP_NAME ./charts/keycloak-9.7.2.tgz \
    -f values/keycloak.yaml \
    -n $NAMESPACE \
    --create-namespace

echo "=== Keycloak 설치 완료 ==="

# 설치 상태 확인
echo "Pod 상태 확인:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=keycloak

echo "Service 상태 확인:"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=keycloak

echo "Ingress 상태 확인:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "=== 설치 완료 ==="
echo "Keycloak 접속 방법:"
echo "1. Ingress 설정 시: https://keycloak-dev.samsungena.io"
echo "2. Port-forward 사용: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:8080"
echo "   접속: http://localhost:8080"
echo ""
echo "기본 관리자 계정:"
echo "사용자명: admin"
echo "비밀번호: keycloak123!"
#!/bin/bash

# Vault 설치 스크립트

set -e

NAMESPACE="devops-vault"
APP_NAME="vault"

echo "=== Vault 설치 시작 ==="

# 네임스페이스 확인 및 생성
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 $NAMESPACE 이미 존재"
fi

# PVC 생성
echo "PVC 생성 중..."
kubectl apply -f pvc/vault-pvc.yaml

# PVC 상태 확인
echo "PVC 상태 확인 중..."
kubectl get pvc -n $NAMESPACE | grep vault

# Helm 차트 설치
echo "Vault Helm 차트 설치 중..."
helm upgrade --install $APP_NAME ./charts/vault-0.21.0.tgz \
    -f values/vault.yaml \
    -n $NAMESPACE \
    --create-namespace

echo "=== Vault 설치 완료 ==="

# 설치 상태 확인
echo "Pod 상태 확인:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vault

echo "Service 상태 확인:"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=vault

echo "Ingress 상태 확인:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "=== 설치 완료 ==="
echo "Vault 접속 방법:"
echo "1. Ingress 설정 시: https://vault-dev.samsungena.io"
echo "2. Port-forward 사용: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8200:8200"
echo "   접속: http://localhost:8200"
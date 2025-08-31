#!/bin/bash

# Nexus 설치 스크립트

set -e

NAMESPACE="devops"
APP_NAME="nexus"

echo "=== Nexus 설치 시작 ==="

# 네임스페이스 확인 및 생성
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 $NAMESPACE 이미 존재"
fi

# PVC 생성
echo "PVC 생성 중..."
kubectl apply -f pvc/nexus-pvc.yaml

# PVC 상태 확인
echo "PVC 상태 확인 중..."
kubectl get pvc -n $NAMESPACE | grep nexus

# Helm 차트 설치
echo "Nexus Helm 차트 설치 중..."
helm upgrade --install $APP_NAME ./charts/nexus \
    -f values/nexus.yaml \
    -n $NAMESPACE \
    --create-namespace

echo "=== Nexus 설치 완료 ==="

# 설치 상태 확인
echo "Pod 상태 확인:"
kubectl get pods -n $NAMESPACE -l app=$APP_NAME

echo "Service 상태 확인:"
kubectl get svc -n $NAMESPACE -l app=$APP_NAME

echo "Ingress 상태 확인:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "=== 설치 완료 ==="
echo "Nexus 접속 방법:"
echo "1. Ingress 설정 시: https://nexus.example.com"
echo "2. Port-forward 사용: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8081:8081"
echo "   접속: http://localhost:8081"
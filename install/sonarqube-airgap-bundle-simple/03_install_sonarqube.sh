#!/bin/bash

# SonarQube 설치 스크립트

set -e

NAMESPACE="devops"
APP_NAME="sonarqube"

echo "=== SonarQube 설치 시작 ==="

# 네임스페이스 확인 및 생성
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 $NAMESPACE 이미 존재"
fi

# PVC 생성
echo "PVC 생성 중..."
kubectl apply -f pvc/sonarqube-pvc.yaml

# PVC 상태 확인
echo "PVC 상태 확인 중..."
kubectl get pvc -n $NAMESPACE | grep sonarqube

# Helm 차트 설치
echo "SonarQube Helm 차트 설치 중..."
helm upgrade --install $APP_NAME ./charts/devops \
    -f values/sonarqube.yaml \
    -n $NAMESPACE \
    --create-namespace

echo "=== SonarQube 설치 완료 ==="

# 설치 상태 확인
echo "Pod 상태 확인:"
kubectl get pods -n $NAMESPACE -l app=$APP_NAME

echo "Service 상태 확인:"
kubectl get svc -n $NAMESPACE -l app=$APP_NAME

echo "Ingress 상태 확인:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "=== 설치 완료 ==="
echo "SonarQube 접속 방법:"
echo "1. Ingress 설정 시: https://sonarqube-dev.samsungena.io"
echo "2. Port-forward 사용: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 9000:9000"
echo "   접속: http://localhost:9000"
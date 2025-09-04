#!/bin/bash

# Prometheus 설치 스크립트

set -e

NAMESPACE="devops-prometheus"
APP_NAME="prometheus"
CHART_VERSION="77.3.0"

echo "=== Prometheus 설치 시작 ==="

# 네임스페이스 확인 및 생성
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 $NAMESPACE 이미 존재"
fi

# ECR registry credential secret 생성
echo "ECR registry credential secret 생성 중..."
if ! kubectl get secret registry-local-credential -n $NAMESPACE > /dev/null 2>&1; then
    kubectl create secret docker-registry registry-local-credential \
        --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \
        --docker-username=AWS \
        --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
        --namespace=$NAMESPACE
    echo "ECR registry credential secret 생성 완료"
else
    echo "ECR registry credential secret 이미 존재"
fi

# Helm 차트 다운로드 및 수정 (오프라인 및 ECR 사용을 위해)
echo "Prometheus Helm 차트 준비 중..."
mkdir -p charts

# 압축된 차트가 없으면 다운로드
if [ ! -f "charts/kube-prometheus-stack-${CHART_VERSION}.tgz" ]; then
    echo "Helm 리포지토리 설정 중..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add kube-state-metrics https://kubernetes.github.io/kube-state-metrics
    helm repo update
    
    echo "Prometheus Helm 차트 다운로드 중..."
    helm pull prometheus-community/kube-prometheus-stack --version ${CHART_VERSION} --destination charts/
fi

# 차트가 압축 해제되어 있지 않으면 압축 해제 및 수정
if [ ! -d "charts/kube-prometheus-stack" ]; then
    echo "차트 압축 해제 및 ECR 이미지 설정 수정 중..."
    tar -xzf charts/kube-prometheus-stack-${CHART_VERSION}.tgz -C charts/
    
    # ECR 사용을 위한 default registry 제거
    find charts/kube-prometheus-stack -name "values.yaml" -exec sed -i '' 's/registry: docker.io/registry: ""/g' {} \;
    find charts/kube-prometheus-stack -name "values.yaml" -exec sed -i '' 's/registry: quay.io/registry: ""/g' {} \;
    find charts/kube-prometheus-stack -name "values.yaml" -exec sed -i '' 's/registry: registry.k8s.io/registry: ""/g' {} \;
    
    echo "차트 수정 완료"
fi

# Helm 차트 설치
echo "Prometheus Helm 차트 설치 중..."
helm upgrade --install $APP_NAME charts/kube-prometheus-stack \
    -f values/prometheus.yaml \
    -n $NAMESPACE \
    --create-namespace

echo "=== Prometheus 설치 완료 ==="

# 설치 상태 확인
echo "Pod 상태 확인:"
kubectl get pods -n $NAMESPACE

echo "Service 상태 확인:"
kubectl get svc -n $NAMESPACE

echo "PVC 상태 확인:"
kubectl get pvc -n $NAMESPACE

echo "Ingress 상태 확인:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "=== 설치 완료 ==="
echo "Grafana 접속 방법:"
echo "1. Ingress 설정 시: https://grafana-dev.samsungena.io"
echo "2. Port-forward 사용: kubectl port-forward -n $NAMESPACE svc/prometheus-grafana 3000:80"
echo "   접속: http://localhost:3000"
echo ""
echo "기본 Grafana 계정:"
echo "사용자명: admin"
echo "비밀번호: admin123!"
echo ""
echo "Prometheus 접속:"
echo "Port-forward: kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "접속: http://localhost:9090"
echo ""
echo "AlertManager 접속:"
echo "Port-forward: kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-alertmanager 9093:9093"
echo "접속: http://localhost:9093"
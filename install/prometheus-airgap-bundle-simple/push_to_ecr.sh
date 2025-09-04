#!/bin/bash

# ECR에 Prometheus 이미지들을 푸시하는 스크립트

set -e

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 매핑 (source -> target)
declare -A IMAGE_MAP=(
    ["quay.io/prometheus/prometheus:v3.5.0"]="prometheus:v3.5.0"
    ["quay.io/prometheus/alertmanager:v0.28.1"]="alertmanager:v0.28.1"
    ["grafana/grafana:11.1.0"]="grafana:11.1.0"
    ["quay.io/prometheus/node-exporter:v1.8.2"]="node-exporter:v1.8.2"
    ["registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0"]="kube-state-metrics:v2.13.0"
    ["quay.io/prometheus-operator/prometheus-operator:v0.85.0"]="prometheus-operator:v0.85.0"
    ["quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0"]="prometheus-config-reloader:v0.85.0"
    ["quay.io/thanos/thanos:v0.39.2"]="thanos:v0.39.2"
    ["jimmidyson/configmap-reload:v0.8.0"]="configmap-reload:v0.8.0"
    ["busybox:1.31.1"]="busybox:1.31.1"
    ["registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2"]="kube-webhook-certgen:v1.6.2"
    ["quay.io/kiwigrid/k8s-sidecar:1.30.10"]="k8s-sidecar:1.30.10"
)

success_count=0
total_count=${#IMAGE_MAP[@]}
current=1

echo "=== ECR 푸시 시작 (총 $total_count 개) ==="

for source_image in "${!IMAGE_MAP[@]}"; do
    target_image="${IMAGE_MAP[$source_image]}"
    ecr_image="$ECR_REGISTRY/$target_image"
    
    echo "[$current/$total_count] 처리 중: $source_image -> $target_image"
    
    # 소스 이미지가 존재하는지 확인
    if docker image inspect "$source_image" > /dev/null 2>&1; then
        # 태깅
        if docker tag "$source_image" "$ecr_image"; then
            echo "✅ 태깅 성공: $ecr_image"
            
            # 푸시
            if docker push "$ecr_image"; then
                echo "✅ 푸시 성공: $ecr_image"
                success_count=$((success_count + 1))
            else
                echo "❌ 푸시 실패: $ecr_image"
            fi
        else
            echo "❌ 태깅 실패: $source_image -> $ecr_image"
        fi
    else
        echo "❌ 소스 이미지 없음: $source_image"
        echo "   이미지를 먼저 pull하세요: docker pull $source_image"
    fi
    
    current=$((current + 1))
    echo "---"
done

echo ""
echo "=== ECR 푸시 완료 ==="
echo "성공: $success_count/$total_count 개"
echo ""
echo "ECR에 푸시된 이미지 확인:"
echo "aws ecr list-images --region $REGION --repository-name prometheus"
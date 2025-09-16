#!/bin/bash

# AMD64 전용 Prometheus 이미지들을 ECR에 푸시하는 수정된 스크립트
# nginx-ingress와 동일한 문제 해결: 멀티 아키텍처 매니페스트에서 AMD64만 선택

set -e

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "========================================"
echo "  AMD64 전용 Prometheus ECR 푸시"
echo "========================================"
echo "ECR Registry: $ECR_REGISTRY"
echo "Region: $REGION"
echo "========================================"

# ECR 로그인
echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# AMD64 전용 이미지 매핑 (source@digest -> target)
declare -A IMAGE_MAP=(
    # Prometheus core images (멀티 아키텍처 - AMD64 digest 사용)
    ["quay.io/prometheus/prometheus@sha256:8672a850efe2f9874702406c8318704edb363587f8c2ca88586b4c8fdb5cea24"]="prometheus:v3.5.0"
    ["quay.io/prometheus/alertmanager@sha256:220da6995a919b9ee6e0d3da7ca5f09802f3088007af56be22160314d2485b54"]="alertmanager:v0.28.1"
    ["grafana/grafana@sha256:83c197f05ad57b51f5186ca902f0c95fcce45810e7fe738a84cc38f481a2227a"]="grafana:11.1.0"
    ["quay.io/prometheus/node-exporter@sha256:065914c03336590ebed517e7df38520f0efb44465fde4123c3f6b7328f5a9396"]="node-exporter:v1.8.2"
    ["registry.k8s.io/kube-state-metrics/kube-state-metrics@sha256:cfef7d6665aab9bfeecd9f738a23565cb57f038a4dfb2fa6b36e2d80a8333a0a"]="kube-state-metrics:v2.13.0"
    
    # 기타 이미지들 (단일 아키텍처로 추정 - 태그 사용)
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

echo "=== AMD64 전용 ECR 푸시 시작 (총 $total_count 개) ==="
echo ""

for source_image in "${!IMAGE_MAP[@]}"; do
    target_image="${IMAGE_MAP[$source_image]}"
    ecr_image="$ECR_REGISTRY/$target_image"
    
    echo "[$current/$total_count] 처리 중: $source_image"
    echo "                    -> $target_image"
    
    # AMD64 전용 이미지 pull
    echo "  🔽 AMD64 이미지 pull 중..."
    if docker pull "$source_image"; then
        echo "  ✅ Pull 성공"
        
        # 아키텍처 확인
        arch=$(docker inspect "$source_image" | grep -o '"Architecture": "[^"]*"' | cut -d'"' -f4)
        echo "  🔍 이미지 아키텍처: $arch"
        
        if [ "$arch" = "amd64" ]; then
            echo "  ✅ AMD64 아키텍처 확인됨"
            
            # ECR에 태깅
            if docker tag "$source_image" "$ecr_image"; then
                echo "  🏷️  태깅 성공: $ecr_image"
                
                # ECR에 푸시
                if docker push "$ecr_image"; then
                    echo "  ✅ 푸시 성공: $ecr_image"
                    success_count=$((success_count + 1))
                else
                    echo "  ❌ 푸시 실패: $ecr_image"
                fi
            else
                echo "  ❌ 태깅 실패: $source_image -> $ecr_image"
            fi
        else
            echo "  ❌ 잘못된 아키텍처: $arch (AMD64 필요)"
        fi
        
        # 로컬 이미지 정리
        docker rmi "$source_image" 2>/dev/null || true
    else
        echo "  ❌ Pull 실패: $source_image"
    fi
    
    current=$((current + 1))
    echo ""
done

echo "========================================"
echo "  ECR 푸시 완료"
echo "========================================"
echo "성공: $success_count/$total_count 개"
echo ""

if [ $success_count -eq $total_count ]; then
    echo "🎉 모든 이미지가 성공적으로 푸시되었습니다!"
else
    echo "⚠️  일부 이미지 푸시에 실패했습니다."
fi

echo ""
echo "ECR 레포지토리 확인 명령어:"
echo "aws ecr describe-repositories --region $REGION"
echo ""
echo "특정 이미지 확인 예시:"
echo "aws ecr describe-images --region $REGION --repository-name prometheus"
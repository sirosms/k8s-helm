#!/bin/bash
set -e

echo "🎯 검증된 방식으로 모든 Prometheus 이미지 다운로드..."

# 모든 이미지 리스트
images=(
    "quay.io/prometheus/alertmanager:v0.28.1"
    "quay.io/prometheus/node-exporter:v1.8.2"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0"
    "quay.io/prometheus-operator/prometheus-operator:v0.85.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0"
    "quay.io/thanos/thanos:v0.39.2"
    "docker.io/jimmidyson/configmap-reload:v0.8.0"
    "docker.io/library/busybox:1.31.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2"
    "quay.io/kiwigrid/k8s-sidecar:1.30.10"
)

for image in "${images[@]}"; do
    echo ""
    echo "📦 처리: $image"
    
    # 파일명 생성
    filename=$(echo "$image" | tr '/' '_' | tr ':' '-')
    tar_file="images/${filename}.tar"
    
    echo "💾 저장: $tar_file"
    
    # Docker pull
    echo "⬇️  Pull..."
    docker pull "$image"
    
    # 즉시 save (리다이렉션 방식)
    echo "💿 Save..."
    docker save "$image" > "$tar_file"
    
    # 파일 확인
    if [ -f "$tar_file" ]; then
        file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "0")
        echo "📊 크기: $file_size bytes"
        
        if [ "$file_size" -gt 1000000 ]; then  # 1MB 이상
            echo "✅ 성공: $tar_file"
            # 메모리 절약을 위해 이미지 삭제
            docker rmi "$image"
        else
            echo "❌ 실패: 파일 크기 너무 작음"
            rm -f "$tar_file"
        fi
    else
        echo "❌ 파일 생성 실패"
    fi
done

echo ""
echo "🎉 모든 이미지 다운로드 완료!"
echo ""
echo "📊 최종 결과:"
ls -lh images/*.tar
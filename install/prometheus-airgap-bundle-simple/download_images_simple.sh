#!/bin/bash

# 간단한 이미지 다운로드 스크립트 (Docker save 문제 해결)

set -e

# 이미지 목록
IMAGES=(
    "quay.io/prometheus/prometheus:v3.5.0"
    "quay.io/prometheus/alertmanager:v0.28.1"
    "grafana/grafana:11.1.0"
    "quay.io/prometheus/node-exporter:v1.8.2"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0"
    "quay.io/prometheus-operator/prometheus-operator:v0.85.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0"
    "quay.io/thanos/thanos:v0.39.2"
    "jimmidyson/configmap-reload:v0.8.0"
    "busybox:1.31.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2"
    "quay.io/kiwigrid/k8s-sidecar:1.30.10"
)

mkdir -p images

echo "=== Prometheus 이미지 다운로드 시작 ==="
echo "총 ${#IMAGES[@]} 개의 이미지를 다운로드합니다."
echo ""

# 이미지 목록 파일 생성
cat > images/image-list.txt << EOF
# Prometheus Stack Images for Airgap Installation
# Generated on: $(date)
# Chart Version: kube-prometheus-stack-77.3.0

EOF

success_count=0
failed_count=0

for i in "${!IMAGES[@]}"; do
    image="${IMAGES[$i]}"
    echo "[$((i+1))/${#IMAGES[@]}] 다운로드 중: $image"
    
    # 이미지 pull
    if docker pull "$image"; then
        echo "✅ 이미지 pull 성공: $image"
        
        # 파일명 생성
        filename=$(echo "$image" | sed 's|[/:]|_|g' | sed 's|\.|-|g')
        
        # Docker save 시도 (여러 방법)
        saved=false
        
        # 방법 1: 표준 save
        if docker save "$image" -o "images/${filename}.tar" 2>/dev/null; then
            if [ -s "images/${filename}.tar" ]; then
                echo "✅ 이미지 저장 성공: ${filename}.tar"
                echo "$image -> ${filename}.tar" >> images/image-list.txt
                success_count=$((success_count + 1))
                saved=true
            fi
        fi
        
        # 방법 2: gzip 압축으로 저장
        if [ "$saved" = false ]; then
            if docker save "$image" | gzip > "images/${filename}.tar.gz" 2>/dev/null; then
                if [ -s "images/${filename}.tar.gz" ]; then
                    echo "✅ 이미지 저장 성공 (압축): ${filename}.tar.gz"
                    echo "$image -> ${filename}.tar.gz" >> images/image-list.txt
                    success_count=$((success_count + 1))
                    saved=true
                fi
            fi
        fi
        
        if [ "$saved" = false ]; then
            echo "❌ 이미지 저장 실패: $image"
            echo "# SAVE FAILED: $image" >> images/image-list.txt
            failed_count=$((failed_count + 1))
            # 실패한 파일들 정리
            rm -f "images/${filename}.tar" "images/${filename}.tar.gz"
        fi
    else
        echo "❌ 이미지 pull 실패: $image"
        echo "# PULL FAILED: $image" >> images/image-list.txt
        failed_count=$((failed_count + 1))
    fi
    echo "---"
done

echo ""
echo "=== 이미지 다운로드 완료 ==="
echo "성공: $success_count 개"
echo "실패: $failed_count 개"
echo ""

if [ $success_count -gt 0 ]; then
    echo "저장된 파일 목록:"
    ls -lh images/*.tar* 2>/dev/null || echo "저장된 파일이 없습니다."
    echo ""
    echo "총 크기:"
    du -sh images/ 2>/dev/null
else
    echo "⚠️ 모든 이미지 저장이 실패했습니다."
    echo "Docker 데몬 상태를 확인하거나 ECR 사용을 고려하세요."
fi
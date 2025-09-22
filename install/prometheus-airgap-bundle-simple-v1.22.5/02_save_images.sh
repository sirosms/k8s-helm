#!/bin/bash

# 이미 pull된 이미지들을 저장하는 스크립트

set -e

# images 디렉토리 생성
mkdir -p images

# 실제 존재하는 이미지들 확인 후 저장
echo "=== 이미지 저장 시작 ==="

# 이미지 목록 배열
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

success_count=0
total_count=${#IMAGES[@]}
current=1

# 이미지 목록 파일 생성
echo "# Prometheus Stack Images for Airgap Installation" > images/image-list.txt
echo "# Generated on: $(date)" >> images/image-list.txt
echo "# Chart Version: kube-prometheus-stack-77.3.0" >> images/image-list.txt
echo "" >> images/image-list.txt

for image in "${IMAGES[@]}"; do
    # 파일명 생성 (슬래시와 콜론을 언더스코어로 변경)
    filename=$(echo $image | sed 's/[\\/:]/_/g' | sed 's/\\./_/g').tar
    echo "[$current/$total_count] 저장 중: $image -> $filename"
    
    # 이미지가 존재하는지 확인
    if docker image inspect "$image" > /dev/null 2>&1; then
        # 기존 파일 삭제 후 저장 시도
        rm -f "images/$filename"
        
        # docker save 시도 (여러 방법 시도)
        saved=false
        
        # 방법 1: 표준 docker save
        if ! $saved; then
            if timeout 30 docker save "$image" > "images/$filename" 2>/dev/null && [ -s "images/$filename" ]; then
                echo "✅ 저장 성공: $filename ($(du -h images/$filename | cut -f1))"
                echo "$image -> $filename" >> images/image-list.txt
                success_count=$((success_count + 1))
                saved=true
            fi
        fi
        
        # 방법 2: -o 옵션 사용
        if ! $saved; then
            rm -f "images/$filename"
            if timeout 30 docker save -o "images/$filename" "$image" 2>/dev/null && [ -s "images/$filename" ]; then
                echo "✅ 저장 성공: $filename ($(du -h images/$filename | cut -f1))"
                echo "$image -> $filename" >> images/image-list.txt
                success_count=$((success_count + 1))
                saved=true
            fi
        fi
        
        if ! $saved; then
            echo "❌ 저장 실패: $image"
            echo "# SAVE FAILED: $image" >> images/image-list.txt
            rm -f "images/$filename"
        fi
    else
        echo "❌ 이미지 없음: $image"
        echo "# IMAGE NOT FOUND: $image" >> images/image-list.txt
    fi
    
    current=$((current + 1))
    echo "---"
done

echo ""
echo "=== 이미지 저장 완료 ==="
echo "성공: $success_count/$total_count 개"
echo ""
echo "저장된 파일 목록:"
ls -lh images/*.tar 2>/dev/null || echo "저장된 tar 파일이 없습니다."
echo ""
echo "총 크기:"
du -sh images/ 2>/dev/null || echo "images 디렉토리가 비어있습니다."
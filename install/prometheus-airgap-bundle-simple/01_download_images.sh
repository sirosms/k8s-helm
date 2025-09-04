#!/bin/bash

# Prometheus 이미지 다운로드 스크립트 (폐쇄망 설치용)

set -e

# kube-prometheus-stack 77.3.0 버전의 필수 이미지 목록
IMAGES=(
    # 메인 컴포넌트들
    "quay.io/prometheus/prometheus:v3.5.0"
    "quay.io/prometheus/alertmanager:v0.28.1"
    "docker.io/grafana/grafana:11.1.0" 
    "quay.io/prometheus/node-exporter:v1.8.2"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0"
    "quay.io/prometheus-operator/prometheus-operator:v0.85.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0"
    
    # 추가 컴포넌트들 (선택적)
    "quay.io/thanos/thanos:v0.39.2"
    "docker.io/jimmidyson/configmap-reload:v0.8.0"
    
    # 폐쇄망에서 필요할 수 있는 추가 이미지들
    "docker.io/library/busybox:1.31.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2"
    "quay.io/kiwigrid/k8s-sidecar:1.30.10"
)

# 이미지 디렉토리 생성
mkdir -p images

echo "=== Prometheus 이미지 다운로드 시작 (폐쇄망 설치용) ==="
echo "총 $(echo ${#IMAGES[@]}) 개의 이미지를 다운로드합니다."
echo ""

# 다운로드된 이미지 목록 파일 생성
echo "# Prometheus Stack Images for Airgap Installation" > images/image-list.txt
echo "# Generated on: $(date)" >> images/image-list.txt
echo "# Chart Version: kube-prometheus-stack-77.3.0" >> images/image-list.txt
echo "" >> images/image-list.txt

success_count=0
failed_count=0

for i in "${!IMAGES[@]}"; do
    image="${IMAGES[$i]}"
    echo "[$((i+1))/${#IMAGES[@]}] 다운로드 중: $image"
    
    # 이미지 pull 시도
    if docker pull --platform linux/amd64 "$image" 2>/dev/null; then
        echo "✅ 이미지 pull 성공: $image"
        
        # tar 파일명 생성 (슬래시와 콜론을 언더스코어로 변경)
        filename=$(echo $image | sed 's/[\/:]/_/g' | sed 's/\./_/g')
        
        # 이미지를 tar 파일로 저장 (manifest 문제 방지를 위해 --platform 옵션 제거)
        if docker save "$image" > "images/${filename}.tar" 2>/dev/null; then
            echo "✅ 이미지 저장 성공: images/${filename}.tar"
            echo "$image -> ${filename}.tar" >> images/image-list.txt
            success_count=$((success_count + 1))
        else
            echo "❌ 이미지 저장 실패: $image"
            echo "# SAVE FAILED: $image" >> images/image-list.txt
            failed_count=$((failed_count + 1))
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
echo "저장된 위치: $(pwd)/images/"
echo ""
echo "이미지 파일 목록:"
ls -lh images/*.tar 2>/dev/null || echo "저장된 tar 파일이 없습니다."
echo ""
echo "총 크기:"
du -sh images/ 2>/dev/null || echo "images 디렉토리가 비어있습니다."
echo ""
echo "상세 목록은 images/image-list.txt 파일을 확인하세요."
#!/bin/bash

# Prometheus 이미지 다운로드 스크립트

set -e

# kube-prometheus-stack 39.11.0 버전의 이미지 목록
IMAGES=(
    "quay.io/prometheus/prometheus:v2.37.0"
    "quay.io/prometheus/alertmanager:v0.24.0" 
    "grafana/grafana:9.1.0"
    "quay.io/prometheus/node-exporter:v1.3.1"
    "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.5.0"
    "quay.io/prometheus-operator/prometheus-operator:v0.58.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.58.0"
    "quay.io/thanos/thanos:v0.27.0"
    "jimmidyson/configmap-reload:v0.5.0"
)

# 이미지 디렉토리 생성
mkdir -p images

echo "=== Prometheus 이미지 다운로드 시작 ==="

for image in "${IMAGES[@]}"; do
    echo "다운로드 중: $image"
    
    # 이미지 pull (amd64 아키텍처로)
    docker pull --platform linux/amd64 $image
    
    # tar 파일명 생성 (슬래시와 콜론을 언더스코어로 변경)
    filename=$(echo $image | sed 's/[\/:]/_/g')
    
    # 이미지를 tar 파일로 저장
    docker save $image -o "images/${filename}.tar"
    
    echo "저장 완료: images/${filename}.tar"
done

echo "=== 모든 이미지 다운로드 완료 ==="
echo "이미지 목록:"
ls -la images/
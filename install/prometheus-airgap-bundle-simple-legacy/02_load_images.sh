#!/bin/bash

# Prometheus 이미지 로드 스크립트

set -e

# 이미지 디렉토리 확인
if [ ! -d "images" ]; then
    echo "ERROR: images 디렉토리가 존재하지 않습니다."
    exit 1
fi

echo "=== Prometheus 이미지 로드 시작 ==="

# images 디렉토리의 모든 tar 파일 로드
for tar_file in images/*.tar; do
    if [ -f "$tar_file" ]; then
        echo "로드 중: $tar_file"
        docker load -i "$tar_file"
    fi
done

echo "=== 모든 이미지 로드 완료 ==="
echo "로드된 이미지 확인:"
docker images | grep -E "(prometheus|grafana|alertmanager|node-exporter|kube-state-metrics)" | head -10
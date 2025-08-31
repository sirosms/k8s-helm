#!/bin/bash

# Nexus 이미지 다운로드 스크립트

set -e

IMAGES=(
    "sonatype/nexus3:3.37.3"
    "busybox:latest"
    "ocadotechnology/nexus-exporter:latest"
)

# 이미지 디렉토리 생성
mkdir -p images

echo "=== Nexus 이미지 다운로드 시작 ==="

for image in "${IMAGES[@]}"; do
    echo "다운로드 중: $image"
    
    # 이미지 pull
    docker pull $image
    
    # tar 파일명 생성 (슬래시와 콜론을 언더스코어로 변경)
    filename=$(echo $image | sed 's/[\/:]/_/g')
    
    # 이미지를 tar 파일로 저장
    docker save $image -o "images/${filename}.tar"
    
    echo "저장 완료: images/${filename}.tar"
done

echo "=== 모든 이미지 다운로드 완료 ==="
echo "이미지 목록:"
ls -la images/
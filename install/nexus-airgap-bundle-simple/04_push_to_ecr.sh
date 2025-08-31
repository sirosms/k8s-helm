#!/bin/bash

# ECR 푸시 스크립트

set -e

# ECR 설정
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
ECR_REPOSITORY_PREFIX="nexus"

# 이미지 목록
IMAGES=(
    "sonatype/nexus3:3.37.3"
    "busybox:latest"
    "ocadotechnology/nexus-exporter:latest"
)

ECR_IMAGES=(
    "${ECR_REGISTRY}/nexus3:3.37.3"
    "${ECR_REGISTRY}/busybox:latest"
    "${ECR_REGISTRY}/nexus-exporter:latest"
)

echo "=== ECR 로그인 ==="
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin ${ECR_REGISTRY}

echo "=== 이미지 태깅 및 푸시 시작 ==="

for i in "${!IMAGES[@]}"; do
    original_image="${IMAGES[$i]}"
    ecr_image="${ECR_IMAGES[$i]}"
    
    echo "처리 중: $original_image -> $ecr_image"
    
    # 이미지 태깅
    docker tag "$original_image" "$ecr_image"
    
    # ECR 리포지토리 생성 (존재하지 않는 경우)
    repo_name=$(echo "$ecr_image" | cut -d'/' -f2 | cut -d':' -f1)
    aws ecr describe-repositories --repository-names "$repo_name" --region ap-northeast-2 >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$repo_name" --region ap-northeast-2
    
    # 이미지 푸시
    docker push "$ecr_image"
    
    echo "푸시 완료: $ecr_image"
done

echo "=== 모든 이미지 ECR 푸시 완료 ==="
echo "푸시된 이미지:"
for ecr_image in "${ECR_IMAGES[@]}"; do
    echo "  $ecr_image"
done
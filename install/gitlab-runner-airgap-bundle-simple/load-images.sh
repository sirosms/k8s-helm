#!/bin/bash
set -e

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "🚀 GitLab Runner 이미지 로드 및 ECR 업로드 시작..."
echo ""

# GitLab Runner 17.6.0 이미지 매핑
declare -A image_mappings=(
    ["gitlab_gitlab-runner_alpine-v17.6.0.tar"]="gitlab/gitlab-runner:alpine-v17.6.0"
    ["gitlab_gitlab-runner-helper_x86_64-v17.6.0.tar"]="gitlab/gitlab-runner-helper:x86_64-v17.6.0"
    ["ubuntu_20.04.tar"]="ubuntu:20.04"
)

# ECR 로그인
echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 로드 및 태그
for tar_file in "${!image_mappings[@]}"; do
    original_image="${image_mappings[$tar_file]}"
    
    echo ""
    echo "📦 처리 중: $tar_file -> $original_image"
    
    if [ ! -f "images/$tar_file" ]; then
        echo "❌ 파일을 찾을 수 없습니다: images/$tar_file"
        continue
    fi
    
    # 이미지 로드
    echo "⬆️  이미지 로드 중..."
    docker load -i "images/$tar_file"
    
    # 아키텍처 확인
    arch=$(docker inspect "$original_image" --format '{{.Architecture}}' 2>/dev/null || echo "unknown")
    echo "🔍 아키텍처: $arch"
    
    # ECR 태그 생성
    if [[ "$original_image" == gitlab/* ]]; then
        ecr_image="$ECR_REGISTRY/$original_image"
    else
        ecr_image="$ECR_REGISTRY/$original_image"
    fi
    
    echo "🏷️  태그 생성: $original_image -> $ecr_image"
    docker tag "$original_image" "$ecr_image"
    
    # ECR에 푸시
    echo "⬆️  ECR 업로드 중..."
    docker push "$ecr_image"
    
    echo "✅ 완료: $ecr_image"
done

echo ""
echo "🎉 GitLab Runner 이미지 로드 및 업로드 완료!"
echo ""

# ECR 저장소 내용 확인
echo "📋 ECR 저장소 확인:"
aws ecr list-images --repository-name gitlab/gitlab-runner --region $REGION --query 'imageIds[?imageTag!=`null`].imageTag' --output table 2>/dev/null || echo "  gitlab/gitlab-runner 저장소 없음"
aws ecr list-images --repository-name gitlab/gitlab-runner-helper --region $REGION --query 'imageIds[?imageTag!=`null`].imageTag' --output table 2>/dev/null || echo "  gitlab/gitlab-runner-helper 저장소 없음"
aws ecr list-images --repository-name ubuntu --region $REGION --query 'imageIds[?imageTag!=`null`].imageTag' --output table 2>/dev/null || echo "  ubuntu 저장소 없음"
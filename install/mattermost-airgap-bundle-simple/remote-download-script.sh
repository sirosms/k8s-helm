#!/bin/bash

set -e

# 변수 설정
MATTERMOST_VERSION="10.12.0"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
ECR_REPO="mattermost-team-edition"
AWS_REGION="ap-northeast-2"

echo "=== Bastion에서 Mattermost $MATTERMOST_VERSION 이미지 다운로드 및 ECR 업로드 ==="

# Docker Hub에서 이미지 다운로드
echo "Docker Hub에서 Mattermost $MATTERMOST_VERSION 이미지 다운로드 중..."
docker pull mattermost/mattermost-team-edition:$MATTERMOST_VERSION

# ECR 로그인
echo "ECR 로그인 중..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 태깅
echo "이미지 태깅 중..."
docker tag mattermost/mattermost-team-edition:$MATTERMOST_VERSION $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION

# ECR에 이미지 푸시
echo "ECR에 이미지 푸시 중..."
docker push $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION

echo "✅ Mattermost $MATTERMOST_VERSION 이미지가 ECR에 성공적으로 업로드되었습니다!"
echo "ECR 이미지: $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION"

# 다운로드된 이미지 확인
echo "다운로드된 이미지 확인:"
docker images | grep mattermost

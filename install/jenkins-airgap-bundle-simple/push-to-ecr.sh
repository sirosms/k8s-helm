#!/bin/bash
set -euo pipefail

# ECR 설정
AWS_REGION="ap-northeast-2"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo "=== Jenkins Docker 이미지 ECR 푸시 스크립트 ==="

# AWS CLI 로그인 확인
echo "[1/4] AWS ECR 로그인"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 이미지 로드
echo "[2/4] Docker 이미지 로드"
if [ -f "images/jenkins-2.375.2-lts.tar" ]; then
    docker load -i images/jenkins-2.375.2-lts.tar
else
    echo "❌ 이미지 파일을 찾을 수 없습니다: images/jenkins-2.375.2-lts.tar"
    exit 1
fi

# ECR 리포지토리 생성 (존재하지 않는 경우)
echo "[3/4] ECR 리포지토리 확인/생성"
aws ecr describe-repositories --region ${AWS_REGION} --repository-names devops-service/jenkins-master || \
aws ecr create-repository --region ${AWS_REGION} --repository-name devops-service/jenkins-master

# 이미지 푸시
echo "[4/4] 이미지 푸시"
docker push ${ECR_REGISTRY}/devops-service/jenkins-master:2.375.2-lts

echo
echo "✅ Jenkins 이미지 ECR 푸시 완료!"
echo "📦 이미지: ${ECR_REGISTRY}/devops-service/jenkins-master:2.375.2-lts"
#!/bin/bash

# GitLab 업그레이드용 이미지를 ECR에 푸시하는 스크립트

set -e

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

# 업그레이드할 GitLab 버전들
GITLAB_VERSIONS=(
    "15.11.13-ce.0"
    "16.3.7-ce.0"
    "16.7.8-ce.0"
    "17.3.7-ce.0"
    "17.6.2-ce.0"
)

echo "=== GitLab 업그레이드용 이미지 ECR 푸시 시작 ==="
echo "총 ${#GITLAB_VERSIONS[@]}개 버전 처리"
echo ""

# ECR 로그인
echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# ECR 저장소 확인/생성
echo "=== ECR 저장소 확인/생성 ==="
if ! aws ecr describe-repositories --region $REGION --repository-names gitlab/gitlab-ce 2>/dev/null; then
    echo "gitlab/gitlab-ce 저장소 생성 중..."
    aws ecr create-repository --region $REGION --repository-name gitlab/gitlab-ce
fi

success_count=0
failed_count=0

for version in "${GITLAB_VERSIONS[@]}"; do
    echo ""
    echo "=== 처리 중: GitLab CE $version ==="
    
    source_image="gitlab/gitlab-ce:$version"
    target_image="$ECR_REGISTRY/gitlab/gitlab-ce:$version"
    
    # 이미지 다운로드
    echo "1. 이미지 다운로드: $source_image"
    if docker pull $source_image; then
        echo "✅ 다운로드 성공"
        
        # 이미지 태깅
        echo "2. 이미지 태깅: $target_image"
        if docker tag $source_image $target_image; then
            echo "✅ 태깅 성공"
            
            # ECR에 푸시
            echo "3. ECR 푸시: $target_image"
            if docker push $target_image; then
                echo "✅ 푸시 성공: $version"
                success_count=$((success_count + 1))
                
                # 로컬 이미지 정리 (공간 절약)
                docker rmi $source_image $target_image 2>/dev/null || true
            else
                echo "❌ 푸시 실패: $version"
                failed_count=$((failed_count + 1))
            fi
        else
            echo "❌ 태깅 실패: $version"
            failed_count=$((failed_count + 1))
        fi
    else
        echo "❌ 다운로드 실패: $version"
        failed_count=$((failed_count + 1))
    fi
    echo "---"
done

echo ""
echo "=== ECR 푸시 완료 ==="
echo "성공: $success_count/${#GITLAB_VERSIONS[@]} 개"
echo "실패: $failed_count/${#GITLAB_VERSIONS[@]} 개"

if [ $success_count -gt 0 ]; then
    echo ""
    echo "✅ ECR에 업로드된 이미지들:"
    aws ecr list-images --region $REGION --repository-name gitlab/gitlab-ce --query 'imageIds[*].imageTag' --output table
fi

if [ $failed_count -gt 0 ]; then
    echo ""
    echo "⚠️ 실패한 이미지가 있습니다. 다시 시도하거나 수동으로 처리하세요."
    exit 1
fi

echo ""
echo "🎉 모든 GitLab 업그레이드 이미지가 ECR에 업로드되었습니다!"
echo "이제 upgrade-gitlab.sh 스크립트를 실행할 수 있습니다."
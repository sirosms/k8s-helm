#!/bin/bash
set -euo pipefail

# Jenkins 이미지 ECR 푸쉬 스크립트

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ECR 설정
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
AWS_REGION="ap-northeast-2"
NEW_VERSION="2.462.3-lts"

# 이미지 매핑
declare -A IMAGE_MAPPINGS=(
    ["jenkins/jenkins:$NEW_VERSION"]="devops-service/jenkins-master:$NEW_VERSION"
    ["jenkins/jenkins:$NEW_VERSION-jdk11"]="devops-service/jenkins-master:$NEW_VERSION-jdk11"
    ["jenkins/jenkins:$NEW_VERSION-jdk21"]="devops-service/jenkins-master:$NEW_VERSION-jdk21"
)

echo -e "${BLUE}=== Jenkins 이미지 ECR 푸쉬 ===${NC}"

# ECR 로그인
echo -e "${BLUE}🔐 ECR 로그인...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 각 이미지 처리
for source_image in "${!IMAGE_MAPPINGS[@]}"; do
    target_image="${IMAGE_MAPPINGS[$source_image]}"
    ecr_full_path="${ECR_REGISTRY}/${target_image}"
    
    echo -e "\n${BLUE}📤 처리 중: $source_image → $ecr_full_path${NC}"
    
    # ECR 리포지토리 생성 (필요시)
    repo_name=$(echo "$target_image" | cut -d: -f1)
    aws ecr describe-repositories --repository-names "$repo_name" --region $AWS_REGION >/dev/null 2>&1 || {
        echo "ECR 리포지토리 생성: $repo_name"
        aws ecr create-repository --repository-name "$repo_name" --region $AWS_REGION >/dev/null
    }
    
    # 이미지 태깅 및 푸쉬
    if docker tag "$source_image" "$ecr_full_path"; then
        if docker push "$ecr_full_path"; then
            echo -e "${GREEN}✅ 푸쉬 성공: $ecr_full_path${NC}"
        else
            echo -e "${RED}❌ 푸쉬 실패: $ecr_full_path${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ 태깅 실패: $source_image${NC}"
        exit 1
    fi
done

echo -e "\n${GREEN}✅ 모든 Jenkins 이미지 ECR 푸쉬 완료!${NC}"
echo -e "ECR 레지스트리: ${BLUE}$ECR_REGISTRY${NC}"

echo -e "\n💡 다음 단계:"
echo "1. Jenkins 업그레이드 스크립트 실행: ./upgrade-jenkins.sh"
echo "2. 업그레이드 후 Jenkins 웹 인터페이스에서 동작 확인"
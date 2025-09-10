#!/bin/bash
set -euo pipefail

# Nexus 이미지 ECR 푸쉬 스크립트

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# ECR 설정
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
AWS_REGION="ap-northeast-2"
NEW_VERSION="3.83.2"

# 이미지 매핑
declare -A IMAGE_MAPPINGS=(
    ["sonatype/nexus3:$NEW_VERSION"]="nexus3:$NEW_VERSION"
    ["busybox:latest"]="busybox:latest"
    ["866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/nexus-exporter:latest"]="nexus-exporter:latest"
)

echo -e "${BLUE}=== Nexus 이미지 ECR 푸쉬 ===${NC}"

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

echo -e "\n${GREEN}✅ 모든 Nexus 이미지 ECR 푸쉬 완료!${NC}"
echo -e "ECR 레지스트리: ${BLUE}$ECR_REGISTRY${NC}"

echo -e "\n💡 다음 단계:"
echo "1. Nexus 업그레이드 스크립트 실행: ./upgrade-nexus.sh"
echo "2. 업그레이드 후 Nexus 웹 인터페이스에서 동작 확인"
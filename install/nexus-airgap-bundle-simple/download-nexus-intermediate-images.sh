#!/bin/bash
set -euo pipefail

# Nexus 중간 버전 이미지 다운로드 스크립트 (단계적 업그레이드용)
# Bastion 서버에서 실행

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 이미지 설정
INTERMEDIATE_VERSION="3.70.3"  # OrientDB 지원 마지막 버전
FINAL_VERSION="3.83.2"
IMAGES_DIR="./images"

# Nexus 이미지 목록 (단계적 업그레이드용)
NEXUS_IMAGES=(
    "sonatype/nexus3:$INTERMEDIATE_VERSION"
    "sonatype/nexus3:$FINAL_VERSION"
    "busybox:latest"
)

mkdir -p "$IMAGES_DIR"

echo -e "${BLUE}=== Nexus 단계적 업그레이드 이미지 다운로드 ===${NC}"
echo -e "중간 버전: ${GREEN}$INTERMEDIATE_VERSION${NC} (OrientDB 지원 마지막)"
echo -e "최종 버전: ${GREEN}$FINAL_VERSION${NC} (H2 전용)"
echo

for image in "${NEXUS_IMAGES[@]}"; do
    echo -e "${BLUE}📥 다운로드: $image${NC}"
    
    # 이미지명을 파일명으로 변환
    filename=$(echo "$image" | sed 's|[/:@]|-|g' | sed 's|\.|-|g')
    output_file="${IMAGES_DIR}/${filename}.tar"
    
    # 이미 존재하는 파일 확인
    if [ -f "$output_file" ]; then
        echo -e "${YELLOW}⚠️  파일이 이미 존재함: $output_file${NC}"
        continue
    fi
    
    if docker pull "$image" --platform linux/amd64; then
        echo -e "${GREEN}✅ Pull 성공: $image${NC}"
        
        if docker save "$image" -o "$output_file"; then
            echo -e "${GREEN}✅ 저장 성공: $output_file${NC}"
            echo "파일 크기: $(du -sh "$output_file" | cut -f1)"
        else
            echo -e "${RED}❌ 저장 실패: $image${NC}"
        fi
        
        # 로컬 이미지 정리
        docker rmi "$image" >/dev/null 2>&1 || true
    else
        echo -e "${RED}❌ Pull 실패: $image${NC}"
    fi
    echo "---"
done

echo -e "\n${GREEN}=== 다운로드 완료 ===${NC}"
echo -e "저장 위치: $(pwd)/$IMAGES_DIR"
echo -e "\n다운로드된 파일 목록:"
ls -lh "$IMAGES_DIR"/*.tar 2>/dev/null || echo "다운로드된 파일이 없습니다."

echo -e "\n💡 다음 단계:"
echo "1. ECR에 이미지 푸쉬: ./push-nexus-stepwise-to-ecr.sh"
echo "2. 로컬로 이미지 다운로드"
echo "3. 단계적 업그레이드 실행: ./upgrade-nexus-stepwise.sh"
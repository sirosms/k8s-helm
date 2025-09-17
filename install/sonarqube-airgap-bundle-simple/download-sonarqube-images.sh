#!/bin/bash
set -euo pipefail

# SonarQube 최신 Community Build 이미지 다운로드 스크립트
# Bastion 서버에서 실행

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 이미지 설정
NEW_VERSION="9.9.4-community"
IMAGES_DIR="./images"

# SonarQube 이미지 목록
SONARQUBE_IMAGES=(
    "sonarqube:$NEW_VERSION"
    "postgres:13"
    "prom/jmx-exporter:0.17.2"
)

mkdir -p "$IMAGES_DIR"

echo -e "${BLUE}=== SonarQube Community Build 이미지 다운로드 ===${NC}"
echo -e "목표 버전: ${GREEN}$NEW_VERSION${NC}"
echo

for image in "${SONARQUBE_IMAGES[@]}"; do
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
echo "1. ECR에 이미지 푸쉬: ./push-sonarqube-to-ecr.sh"
echo "2. 로컬로 이미지 다운로드"
echo "3. SonarQube 업그레이드 실행: ./upgrade-sonarqube.sh"
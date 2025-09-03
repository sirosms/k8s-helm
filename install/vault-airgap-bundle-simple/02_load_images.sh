#!/bin/bash

# Vault 이미지 로드 스크립트

set -e

# 이미지 디렉토리 확인
if [ ! -d "images" ]; then
    echo "ERROR: images 디렉토리가 존재하지 않습니다."
    exit 1
fi

echo "=== Vault 이미지 로드 시작 ==="

# 이미지 태깅 함수
tag_image() {
    local filename="$1"
    local image_id="$2"
    
    case "$filename" in
        "hashicorp_vault_1.11.2.tar")
            echo "태깅 중: $image_id -> hashicorp/vault:1.11.2"
            docker tag "$image_id" "hashicorp/vault:1.11.2"
            ;;
        *)
            echo "알 수 없는 이미지 파일: $filename"
            ;;
    esac
}

# images 디렉토리의 모든 tar 파일 로드
for tar_file in images/*.tar; do
    if [ -f "$tar_file" ]; then
        filename=$(basename "$tar_file")
        echo "로드 중: $tar_file"
        
        # 이미지 로드하고 Image ID 추출
        load_output=$(docker load -i "$tar_file")
        echo "$load_output"
        
        # Image ID 추출 (SHA256 해시만 있는 경우)
        if echo "$load_output" | grep -q "Loaded image ID:"; then
            image_id=$(echo "$load_output" | grep "Loaded image ID:" | cut -d' ' -f4)
            tag_image "$filename" "$image_id"
        fi
    fi
done

echo "=== 모든 이미지 로드 완료 ==="
echo "로드된 이미지 확인:"
docker images | grep -E "(hashicorp|vault)" || echo "Vault 관련 이미지를 찾을 수 없습니다."
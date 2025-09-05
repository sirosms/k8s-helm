#!/bin/bash

# 백업용 이미지 다운로드 스크립트 (폐쇄망 설치용)

set -e

# 백업에 필요한 이미지 목록
BACKUP_IMAGES=(
    "ubuntu:20.04"
    "postgres:13"
    "busybox:1.31.1"
)

# 이미지 디렉토리 생성
mkdir -p backup-images

echo "=== 백업용 이미지 다운로드 시작 (폐쇄망 설치용) ==="
echo "총 ${#BACKUP_IMAGES[@]} 개의 이미지를 다운로드합니다."
echo ""

# 이미지 목록 파일 생성
cat > backup-images/backup-image-list.txt << EOF
# Backup Images for GitLab Airgap Installation
# Generated on: $(date)
# Purpose: PVC backup and database operations

EOF

success_count=0
failed_count=0

for i in "${!BACKUP_IMAGES[@]}"; do
    image="${BACKUP_IMAGES[$i]}"
    echo "[$((i+1))/${#BACKUP_IMAGES[@]}] 다운로드 중: $image"
    
    # 이미지 pull
    if docker pull --platform linux/amd64 "$image"; then
        echo "✅ 이미지 pull 성공: $image"
        
        # 파일명 생성
        filename=$(echo "$image" | sed 's|[/:]|_|g' | sed 's|\.|-|g')
        
        # Docker save
        if docker save "$image" > "backup-images/${filename}.tar" 2>/dev/null && [ -s "backup-images/${filename}.tar" ]; then
            echo "✅ 이미지 저장 성공: ${filename}.tar"
            echo "$image -> ${filename}.tar" >> backup-images/backup-image-list.txt
            success_count=$((success_count + 1))
        else
            echo "❌ 이미지 저장 실패: $image"
            echo "# SAVE FAILED: $image" >> backup-images/backup-image-list.txt
            failed_count=$((failed_count + 1))
            rm -f "backup-images/${filename}.tar"
        fi
    else
        echo "❌ 이미지 pull 실패: $image"
        echo "# PULL FAILED: $image" >> backup-images/backup-image-list.txt
        failed_count=$((failed_count + 1))
    fi
    echo "---"
done

echo ""
echo "=== 백업용 이미지 다운로드 완료 ==="
echo "성공: $success_count 개"
echo "실패: $failed_count 개"
echo ""

if [ $success_count -gt 0 ]; then
    echo "저장된 파일 목록:"
    ls -lh backup-images/*.tar 2>/dev/null || echo "저장된 tar 파일이 없습니다."
    echo ""
    echo "총 크기:"
    du -sh backup-images/ 2>/dev/null
else
    echo "⚠️ 모든 이미지 저장이 실패했습니다."
fi

echo ""
echo "상세 목록은 backup-images/backup-image-list.txt 파일을 확인하세요."
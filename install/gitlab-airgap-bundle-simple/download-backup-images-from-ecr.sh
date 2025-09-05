#!/bin/bash

# ECR에서 백업용 이미지 다운로드 스크립트 (폐쇄망 설치용)

set -e

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

# ECR에 있는 백업용 이미지 목록
ECR_BACKUP_IMAGES=(
    "$ECR_REGISTRY/ubuntu:20.04"
    "$ECR_REGISTRY/busybox:1.31.1"
)

# 이미지 디렉토리 생성
mkdir -p backup-images

echo "=== ECR에서 백업용 이미지 다운로드 시작 ==="
echo "총 ${#ECR_BACKUP_IMAGES[@]} 개의 이미지를 다운로드합니다."
echo ""

# ECR 로그인
echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 목록 파일 생성
cat > backup-images/ecr-backup-image-list.txt << EOF
# Backup Images from ECR for GitLab Airgap Installation
# Generated on: $(date)
# ECR Registry: $ECR_REGISTRY

EOF

success_count=0
failed_count=0

for i in "${!ECR_BACKUP_IMAGES[@]}"; do
    image="${ECR_BACKUP_IMAGES[$i]}"
    echo "[$((i+1))/${#ECR_BACKUP_IMAGES[@]}] ECR에서 다운로드 중: $image"
    
    # 이미지 pull
    if docker pull "$image"; then
        echo "✅ ECR 이미지 pull 성공: $image"
        
        # 파일명 생성 (ECR 경로 제거)
        image_name=$(echo "$image" | sed "s|$ECR_REGISTRY/||")
        filename=$(echo "$image_name" | sed 's|[/:]|_|g' | sed 's|\.|-|g')
        
        # Docker save
        if docker save "$image" -o "backup-images/ecr_${filename}.tar"; then
            if [ -s "backup-images/ecr_${filename}.tar" ]; then
                echo "✅ 이미지 저장 성공: ecr_${filename}.tar"
                echo "$image -> ecr_${filename}.tar" >> backup-images/ecr-backup-image-list.txt
                success_count=$((success_count + 1))
            else
                echo "❌ 빈 파일 생성됨: $image"
                echo "# EMPTY FILE: $image" >> backup-images/ecr-backup-image-list.txt
                failed_count=$((failed_count + 1))
                rm -f "backup-images/ecr_${filename}.tar"
            fi
        else
            echo "❌ 이미지 저장 실패: $image"
            echo "# SAVE FAILED: $image" >> backup-images/ecr-backup-image-list.txt
            failed_count=$((failed_count + 1))
        fi
    else
        echo "❌ ECR 이미지 pull 실패: $image"
        echo "# PULL FAILED: $image" >> backup-images/ecr-backup-image-list.txt
        failed_count=$((failed_count + 1))
    fi
    echo "---"
done

echo ""
echo "=== ECR 백업용 이미지 다운로드 완료 ==="
echo "성공: $success_count 개"
echo "실패: $failed_count 개"
echo ""

if [ $success_count -gt 0 ]; then
    echo "저장된 파일 목록:"
    ls -lh backup-images/ecr_*.tar 2>/dev/null || echo "저장된 ECR tar 파일이 없습니다."
    echo ""
    echo "총 크기:"
    du -sh backup-images/ 2>/dev/null
else
    echo "⚠️ 모든 ECR 이미지 저장이 실패했습니다."
fi

echo ""
echo "상세 목록은 backup-images/ecr-backup-image-list.txt 파일을 확인하세요."
echo ""
echo "=== 폐쇄망 환경에서 이미지 로드 방법 ==="
echo "다음 명령어로 이미지들을 로드하세요:"
echo ""
for tar_file in backup-images/ecr_*.tar; do
    if [ -f "$tar_file" ]; then
        echo "docker load < $tar_file"
    fi
done 2>/dev/null
echo ""
echo "로드 후 ECR 로그인하고 사용하세요:"
echo "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY"
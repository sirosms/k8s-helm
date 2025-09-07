#!/bin/bash
set -e

export DOCKER_DEFAULT_PLATFORM=linux/amd64

echo "🚀 GitLab Runner 17.6.0 이미지 다운로드 시작..."
echo ""

# GitLab Runner 17.6.0에 필요한 이미지 리스트
images=(
    "gitlab/gitlab-runner:alpine-v17.6.0"
    "gitlab/gitlab-runner-helper:x86_64-v17.6.0"
    "ubuntu:20.04"
)

# images 디렉터리 생성
mkdir -p images

for image in "${images[@]}"; do
    echo ""
    echo "📦 처리 중: $image"
    
    # 파일명 생성
    filename=$(echo "$image" | tr '/' '_' | tr ':' '-')
    tar_file="images/${filename}.tar"
    
    echo "💾 저장 위치: $tar_file"
    
    # Docker pull
    echo "⬇️  이미지 다운로드 중..."
    docker pull --platform linux/amd64 "$image"
    
    # 아키텍처 확인
    echo "🔍 아키텍처 확인 중..."
    arch=$(docker inspect "$image" --format '{{.Architecture}}')
    echo "📋 아키텍처: $arch"
    
    if [ "$arch" != "amd64" ]; then
        echo "❌ 경고: $arch 아키텍처입니다. amd64가 필요합니다."
    fi
    
    # 이미지 저장
    echo "💿 이미지 저장 중..."
    docker save "$image" > "$tar_file"
    
    # 파일 확인
    if [ -f "$tar_file" ]; then
        file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "0")
        echo "📊 파일 크기: $file_size bytes"
        
        if [ "$file_size" -gt 1000000 ]; then  # 1MB 이상
            echo "✅ 성공: $tar_file"
        else
            echo "❌ 실패: 파일 크기가 너무 작음"
            rm -f "$tar_file"
        fi
    else
        echo "❌ 파일 생성 실패"
    fi
done

echo ""
echo "🎉 GitLab Runner 이미지 다운로드 완료!"
echo ""
echo "📊 최종 결과:"
ls -lh images/*.tar

echo ""
echo "🔍 아키텍처 검증:"
for image in "${images[@]}"; do
    arch=$(docker inspect "$image" --format '{{.Architecture}}')
    echo "  $image: $arch"
done
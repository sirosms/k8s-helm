#!/bin/bash
set -e

echo "🔄 Docker Desktop 재시작 후 순수 Docker 방식 시도..."

# Docker 완전 정리
echo "🧹 Docker 완전 정리..."
docker system prune -a -f --volumes

# Docker daemon 재시작 대기
echo "⏳ Docker daemon 안정화 대기..."
sleep 10

# 하나씩 단순하게 처리
images=(
    "quay.io/prometheus/prometheus:v3.5.0"
    "docker.io/grafana/grafana:11.1.0"
)

for image in "${images[@]}"; do
    echo ""
    echo "📦 테스트 처리: $image"
    
    # 파일명 생성
    filename=$(echo "$image" | tr '/' '_' | tr ':' '-')
    tar_file="images/${filename}.tar"
    
    echo "💾 저장: $tar_file"
    
    # Docker pull 단순화 (buildx 사용 안함)
    echo "⬇️  Simple pull..."
    docker pull "$image"
    
    # 즉시 save
    echo "💿 즉시 save..."
    docker save "$image" > "$tar_file" 2>&1
    
    # 파일 확인
    if [ -f "$tar_file" ]; then
        file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "0")
        echo "📊 파일 크기: $file_size bytes"
        
        if [ "$file_size" -gt 10000000 ]; then  # 10MB 이상
            echo "✅ 성공: $tar_file"
            # 이미지 삭제하여 메모리 절약
            docker rmi "$image"
        else
            echo "❌ 실패: 파일 크기가 너무 작음"
            rm -f "$tar_file"
        fi
    else
        echo "❌ 파일 생성 실패"
    fi
done

echo ""
echo "📊 결과 확인:"
ls -lh images/ || echo "파일 없음"
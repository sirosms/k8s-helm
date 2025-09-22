#!/bin/bash
set -e

# GitLab의 성공한 방식을 적용한 Prometheus 이미지 다운로드
# 차이점: .tar.gz 대신 .tar 사용, 압축 없음

export DOCKER_DEFAULT_PLATFORM=linux/amd64

echo "🚀 GitLab 방식으로 Prometheus 이미지 다운로드 시작..."

# 기존 이미지와 캐시 정리
echo "🧹 Docker 캐시 정리..."
docker system prune -f
docker image prune -a -f

# images 디렉토리 생성
mkdir -p images

# 이미지 리스트 정의 (GitLab처럼 하나씩 처리)
images=(
    "quay.io/prometheus/prometheus:v3.5.0"
    "quay.io/prometheus/alertmanager:v0.28.1"
    "docker.io/grafana/grafana:11.1.0"
    "quay.io/prometheus/node-exporter:v1.8.2"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0"
    "quay.io/prometheus-operator/prometheus-operator:v0.85.0"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0"
    "quay.io/thanos/thanos:v0.39.2"
    "docker.io/jimmidyson/configmap-reload:v0.8.0"
    "docker.io/library/busybox:1.31.1"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2"
    "quay.io/kiwigrid/k8s-sidecar:1.30.10"
)

for image in "${images[@]}"; do
    echo ""
    echo "📦 처리 중: $image"
    
    # 파일명 생성 (GitLab 방식과 동일하게 단순화)
    filename=$(echo "$image" | tr '/' '_' | tr ':' '-')
    tar_file="images/${filename}.tar"
    
    echo "💾 저장 위치: $tar_file"
    
    # 이미지 pull (AMD64 강제)
    echo "⬇️  이미지 pull..."
    docker pull --platform linux/amd64 "$image"
    
    # 아키텍처 확인
    arch=$(docker inspect "$image" --format '{{.Architecture}}')
    echo "🏗️  아키텍처: $arch"
    
    if [ "$arch" != "amd64" ]; then
        echo "⚠️  경고: $image 아키텍처가 $arch 입니다. AMD64가 아닙니다."
    fi
    
    # GitLab 방식으로 docker save (압축 없음)
    echo "💿 Docker save 실행..."
    if docker save "$image" -o "$tar_file"; then
        # 파일 크기 확인
        file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 1000000 ]; then  # 1MB 이상이면 성공
            echo "✅ 성공: $tar_file (크기: $file_size bytes)"
        else
            echo "❌ 실패: $tar_file 크기가 너무 작습니다 ($file_size bytes)"
            rm -f "$tar_file"
        fi
    else
        echo "❌ Docker save 실패: $image"
    fi
    
    # 메모리 정리
    docker rmi "$image" || true
done

echo ""
echo "📊 다운로드 결과 확인..."
ls -lh images/*.tar || echo "❌ tar 파일이 없습니다."

echo ""
echo "🎉 GitLab 방식 다운로드 완료!"
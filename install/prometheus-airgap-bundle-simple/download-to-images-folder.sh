#!/bin/bash

# images 폴더에 AMD64 이미지 다운로드 (폐쇄망 설치용)

set -e

# 필수 이미지 목록
IMAGES=(
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

echo "=== AMD64 이미지 다운로드 (images 폴더) ==="
echo "총 ${#IMAGES[@]}개의 이미지를 다운로드합니다."
echo ""

# images 디렉토리 정리 및 생성
rm -rf images/*.tar 2>/dev/null || true
mkdir -p images

# 이미지 목록 파일 생성
cat > images/image-list.txt << EOF
# Prometheus Stack Images for Airgap Installation (AMD64)
# Generated on: $(date)
# Chart Version: kube-prometheus-stack-77.3.0

EOF

success_count=0
failed_count=0

for i in "${!IMAGES[@]}"; do
    image="${IMAGES[$i]}"
    echo "[$((i+1))/${#IMAGES[@]}] 처리 중: $image"
    
    # 기존 이미지 완전 삭제
    echo "  기존 이미지 정리..."
    docker rmi "$image" >/dev/null 2>&1 || true
    docker system prune -f >/dev/null 2>&1 || true
    
    # AMD64 이미지 강제 pull
    echo "  AMD64 이미지 다운로드..."
    if DOCKER_DEFAULT_PLATFORM=linux/amd64 docker pull --platform linux/amd64 "$image"; then
        # 아키텍처 확인
        ARCH=$(docker image inspect "$image" --format '{{.Architecture}}' 2>/dev/null || echo "unknown")
        echo "  아키텍처: $ARCH"
        
        if [ "$ARCH" = "amd64" ]; then
            # 파일명 생성
            filename=$(echo "$image" | sed 's|[/:]|_|g' | sed 's|\.|_|g')
            
            # 다양한 방법으로 저장 시도
            echo "  이미지 저장 시도..."
            saved=false
            
            # 방법 1: 직접 저장
            if ! $saved; then
                echo "    방법 1: 직접 저장 시도..."
                if timeout 60 docker save "$image" -o "images/${filename}.tar" 2>/dev/null; then
                    if [ -s "images/${filename}.tar" ]; then
                        SIZE=$(du -sh "images/${filename}.tar" | cut -f1)
                        echo "    ✅ 직접 저장 성공: $SIZE"
                        saved=true
                    else
                        rm -f "images/${filename}.tar"
                    fi
                fi
            fi
            
            # 방법 2: 파이프를 통한 저장
            if ! $saved; then
                echo "    방법 2: 파이프 저장 시도..."
                if timeout 60 bash -c "docker save '$image' > 'images/${filename}.tar'" 2>/dev/null; then
                    if [ -s "images/${filename}.tar" ]; then
                        SIZE=$(du -sh "images/${filename}.tar" | cut -f1)
                        echo "    ✅ 파이프 저장 성공: $SIZE"
                        saved=true
                    else
                        rm -f "images/${filename}.tar"
                    fi
                fi
            fi
            
            # 방법 3: 압축 저장
            if ! $saved; then
                echo "    방법 3: 압축 저장 시도..."
                if timeout 60 bash -c "docker save '$image' | gzip > 'images/${filename}.tar.gz'" 2>/dev/null; then
                    if [ -s "images/${filename}.tar.gz" ]; then
                        SIZE=$(du -sh "images/${filename}.tar.gz" | cut -f1)
                        echo "    ✅ 압축 저장 성공: $SIZE"
                        echo "$image -> ${filename}.tar.gz (${ARCH})" >> images/image-list.txt
                        success_count=$((success_count + 1))
                        saved=true
                    else
                        rm -f "images/${filename}.tar.gz"
                    fi
                fi
            fi
            
            if $saved; then
                if [ -f "images/${filename}.tar" ]; then
                    echo "$image -> ${filename}.tar (${ARCH})" >> images/image-list.txt
                    success_count=$((success_count + 1))
                fi
            else
                echo "    ❌ 모든 저장 방법 실패"
                echo "# SAVE FAILED: $image ($ARCH)" >> images/image-list.txt
                failed_count=$((failed_count + 1))
            fi
        else
            echo "  ❌ AMD64가 아닌 이미지: $ARCH"
            echo "# WRONG ARCH: $image ($ARCH)" >> images/image-list.txt
            failed_count=$((failed_count + 1))
        fi
        
        # 메모리 절약을 위해 이미지 삭제
        docker rmi "$image" >/dev/null 2>&1 || true
    else
        echo "  ❌ 이미지 다운로드 실패"
        echo "# PULL FAILED: $image" >> images/image-list.txt
        failed_count=$((failed_count + 1))
    fi
    
    echo "  ---"
done

echo ""
echo "=== 다운로드 완료 ==="
echo "성공: $success_count 개"
echo "실패: $failed_count 개"
echo ""

if [ $success_count -gt 0 ]; then
    echo "저장된 파일들:"
    ls -lh images/*.tar images/*.tar.gz 2>/dev/null | head -20
    echo ""
    echo "총 크기:"
    du -sh images/
    echo ""
    echo "✅ 폐쇄망 설치용 이미지 파일들이 images/ 폴더에 준비되었습니다!"
    echo ""
    echo "폐쇄망에서 이미지 로드 방법:"
    echo "for file in images/*.tar; do docker load < \$file; done"
    echo "for file in images/*.tar.gz; do gunzip -c \$file | docker load; done"
else
    echo "❌ 모든 이미지 저장에 실패했습니다."
    echo "Docker의 manifest 문제가 지속되는 경우 ECR 사용을 권장합니다."
fi

echo ""
echo "상세 목록은 images/image-list.txt를 확인하세요."
#!/bin/bash

# 최종 이미지 다운로드 스크립트 (polyfill 방식)

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

echo "=== 최종 이미지 다운로드 (Docker desktop 문제 회피) ==="
echo ""

# images 디렉토리 준비
rm -rf images/*.tar* 2>/dev/null || true
mkdir -p images

# 이미지 목록 파일 생성
cat > images/image-list.txt << EOF
# Prometheus Stack Images for Airgap Installation (AMD64)
# Generated on: $(date)
# Method: Single container export
# Chart Version: kube-prometheus-stack-77.3.0

EOF

success_count=0
failed_count=0

for i in "${!IMAGES[@]}"; do
    image="${IMAGES[$i]}"
    echo "[$((i+1))/${#IMAGES[@]}] 처리 중: $image"
    
    # 완전 정리
    docker system prune -f >/dev/null 2>&1 || true
    docker rmi "$image" >/dev/null 2>&1 || true
    
    # AMD64 이미지 다운로드
    echo "  AMD64 이미지 pull..."
    if DOCKER_DEFAULT_PLATFORM=linux/amd64 docker pull --platform linux/amd64 "$image"; then
        ARCH=$(docker image inspect "$image" --format '{{.Architecture}}' 2>/dev/null)
        echo "  아키텍처: $ARCH"
        
        if [ "$ARCH" = "amd64" ]; then
            # 컨테이너 생성 방식으로 export 시도
            echo "  컨테이너 export 방식으로 저장..."
            
            filename=$(echo "$image" | sed 's|[/:]|_|g' | sed 's|\.|_|g')
            container_name="temp_$(date +%s)"
            
            # 임시 컨테이너 생성 후 export
            if docker create --name "$container_name" "$image" >/dev/null 2>&1; then
                echo "    임시 컨테이너 생성 성공"
                
                if timeout 120 docker export "$container_name" | gzip > "images/${filename}.tar.gz"; then
                    if [ -s "images/${filename}.tar.gz" ]; then
                        SIZE=$(du -sh "images/${filename}.tar.gz" | cut -f1)
                        echo "    ✅ export 성공: $SIZE"
                        echo "$image -> ${filename}.tar.gz (exported)" >> images/image-list.txt
                        success_count=$((success_count + 1))
                    else
                        echo "    ❌ 빈 파일 생성"
                        rm -f "images/${filename}.tar.gz"
                        echo "# EXPORT FAILED: $image (empty file)" >> images/image-list.txt
                        failed_count=$((failed_count + 1))
                    fi
                else
                    echo "    ❌ export 실패"
                    echo "# EXPORT FAILED: $image (timeout)" >> images/image-list.txt
                    failed_count=$((failed_count + 1))
                fi
                
                # 임시 컨테이너 정리
                docker rm "$container_name" >/dev/null 2>&1 || true
            else
                echo "    ❌ 컨테이너 생성 실패"
                echo "# CONTAINER FAILED: $image" >> images/image-list.txt
                failed_count=$((failed_count + 1))
            fi
        else
            echo "  ❌ AMD64가 아닌 아키텍처: $ARCH"
            echo "# WRONG ARCH: $image ($ARCH)" >> images/image-list.txt
            failed_count=$((failed_count + 1))
        fi
        
        # 이미지 정리
        docker rmi "$image" >/dev/null 2>&1 || true
    else
        echo "  ❌ 이미지 pull 실패"
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
    ls -lh images/*.tar.gz 2>/dev/null | head -20
    echo ""
    echo "총 크기:"
    du -sh images/
    echo ""
    echo "✅ Export된 이미지 파일들이 images/ 폴더에 준비되었습니다!"
    echo ""
    echo "⚠️  주의: 이 방법은 컨테이너 export이므로 docker load가 아닌 docker import 사용:"
    echo ""
    echo "폐쇄망에서 로드 방법:"
    echo "for file in images/*.tar.gz; do"
    echo "  name=\$(basename \$file .tar.gz)"
    echo "  gunzip -c \$file | docker import - \${name}:latest"
    echo "done"
    echo ""
    echo "또는 ECR 사용을 권장합니다."
else
    echo "❌ 모든 이미지 저장에 실패했습니다."
    echo ""
    echo "🚀 권장 해결책: ECR 사용"
    echo "./push_to_ecr.sh 실행 후 values.yaml의 imageRegistry 설정 사용"
fi
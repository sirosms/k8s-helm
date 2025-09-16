#!/bin/bash

# 폐쇄망 환경을 위한 AMD64 이미지 다운로드 스크립트

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

ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "=== 폐쇄망 환경용 AMD64 이미지 준비 ==="
echo "방법 1: ECR에 직접 푸시 (권장)"
echo "방법 2: 개별 이미지 저장"
echo ""

read -r -p "ECR에 직접 푸시하시겠습니까? (y/N): " push_to_ecr

if [[ $push_to_ecr =~ ^[Yy]$ ]]; then
    echo "=== ECR 로그인 ==="
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    
    echo ""
    echo "=== ECR에 AMD64 이미지 푸시 ==="
    
    for image in "${IMAGES[@]}"; do
        echo "처리 중: $image"
        
        # AMD64 이미지 pull
        echo "  AMD64 이미지 pull..."
        DOCKER_DEFAULT_PLATFORM=linux/amd64 docker pull --platform linux/amd64 "$image"
        
        # 아키텍처 확인
        ARCH=$(docker image inspect "$image" --format '{{.Architecture}}')
        echo "  아키텍처: $ARCH"
        
        if [ "$ARCH" = "amd64" ]; then
            # ECR 태그 생성
            image_name=$(echo "$image" | sed 's|.*/||' | sed 's/:/-/')
            ecr_tag="$ECR_REGISTRY/$image_name"
            
            echo "  ECR 태그: $ecr_tag"
            docker tag "$image" "$ecr_tag"
            
            # ECR 저장소 생성 (존재하지 않으면)
            repo_name=$(echo "$image_name" | sed 's/-[^-]*$//')
            aws ecr describe-repositories --region $REGION --repository-names "$repo_name" >/dev/null 2>&1 || \
            aws ecr create-repository --region $REGION --repository-name "$repo_name" >/dev/null 2>&1
            
            # ECR에 푸시
            if docker push "$ecr_tag"; then
                echo "  ✅ ECR 푸시 성공: $ecr_tag"
            else
                echo "  ❌ ECR 푸시 실패: $ecr_tag"
            fi
            
            # 로컬 이미지 정리
            docker rmi "$image" "$ecr_tag" >/dev/null 2>&1 || true
        else
            echo "  ❌ AMD64가 아닌 이미지: $ARCH"
        fi
        echo "  ---"
    done
    
    echo "✅ ECR 푸시 완료"
    echo ""
    echo "values/prometheus.yaml에서 다음 설정을 사용하세요:"
    echo "global:"
    echo "  imageRegistry: \"$ECR_REGISTRY\""
    
else
    echo "=== 개별 이미지 파일 저장 (실험적) ==="
    mkdir -p images-fixed
    
    for image in "${IMAGES[@]}"; do
        echo "처리 중: $image"
        
        # 완전히 새로운 환경에서 이미지 다운로드
        echo "  이미지 삭제 및 재다운로드..."
        docker rmi "$image" >/dev/null 2>&1 || true
        docker system prune -f >/dev/null 2>&1
        
        # AMD64 이미지만 pull
        if DOCKER_DEFAULT_PLATFORM=linux/amd64 docker pull --platform linux/amd64 --pull always "$image"; then
            ARCH=$(docker image inspect "$image" --format '{{.Architecture}}')
            echo "  아키텍처: $ARCH"
            
            if [ "$ARCH" = "amd64" ]; then
                # tar 파일명 생성
                filename=$(echo "$image" | sed 's|[/:]|_|g' | sed 's|\\.|_|g')
                
                # 새로운 방법으로 저장 시도
                echo "  이미지 저장 중..."
                if timeout 300 docker save "$image" | gzip > "images-fixed/${filename}.tar.gz"; then
                    if [ -s "images-fixed/${filename}.tar.gz" ]; then
                        SIZE=$(du -sh "images-fixed/${filename}.tar.gz" | cut -f1)
                        echo "  ✅ 저장 성공: ${filename}.tar.gz ($SIZE)"
                    else
                        echo "  ❌ 빈 파일 생성됨"
                        rm -f "images-fixed/${filename}.tar.gz"
                    fi
                else
                    echo "  ❌ 저장 실패"
                fi
            else
                echo "  ❌ AMD64가 아닌 이미지: $ARCH"
            fi
        else
            echo "  ❌ 이미지 다운로드 실패"
        fi
        
        # 정리
        docker rmi "$image" >/dev/null 2>&1 || true
        echo "  ---"
    done
    
    echo ""
    echo "저장된 파일들:"
    ls -lh images-fixed/*.tar.gz 2>/dev/null || echo "저장된 파일이 없습니다."
fi

echo ""
echo "=== 완료 ==="
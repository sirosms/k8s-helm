#!/bin/bash

# Prometheus AMD64 이미지 다운로드 스크립트 (Bastion 서버용)
# 멀티 아키텍처 매니페스트에서 AMD64 이미지만 추출하여 저장

set -e

# 디렉토리 설정
IMAGES_DIR="./images_amd64"
TEMP_DIR="/tmp/prometheus_images"

echo "========================================"
echo "  Prometheus AMD64 이미지 다운로드"
echo "========================================"
echo "저장 경로: $IMAGES_DIR"
echo "임시 경로: $TEMP_DIR"
echo "========================================"

# 디렉토리 생성
mkdir -p "$IMAGES_DIR"
mkdir -p "$TEMP_DIR"

# AMD64 전용 이미지 리스트 (모든 digest는 AMD64 아키텍처)
IMAGES=(
    "quay.io/prometheus/prometheus@sha256:8672a850efe2f9874702406c8318704edb363587f8c2ca88586b4c8fdb5cea24|quay_io_prometheus_prometheus_v3_5_0_amd64.tar"
    "quay.io/prometheus/alertmanager@sha256:220da6995a919b9ee6e0d3da7ca5f09802f3088007af56be22160314d2485b54|quay_io_prometheus_alertmanager_v0_28_1_amd64.tar"
    "grafana/grafana@sha256:83c197f05ad57b51f5186ca902f0c95fcce45810e7fe738a84cc38f481a2227a|docker_io_grafana_grafana_11_1_0_amd64.tar"
    "quay.io/prometheus/node-exporter@sha256:065914c03336590ebed517e7df38520f0efb44465fde4123c3f6b7328f5a9396|quay_io_prometheus_node-exporter_v1_8_2_amd64.tar"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics@sha256:cfef7d6665aab9bfeecd9f738a23565cb57f038a4dfb2fa6b36e2d80a8333a0a|registry_k8s_io_kube-state-metrics_kube-state-metrics_v2_13_0_amd64.tar"
    "quay.io/prometheus-operator/prometheus-operator@sha256:a84aefea0ec5652a0d7dd67c83fd3ae755e7937dabc98f021b80db2e4b59f873|quay_io_prometheus-operator_prometheus-operator_v0_85_0_amd64.tar"
    "quay.io/prometheus-operator/prometheus-config-reloader@sha256:e8834beedbd76723ab90964ffcc96ea158710da54bd169cea334d3f11c08eae9|quay_io_prometheus-operator_prometheus-config-reloader_v0_85_0_amd64.tar"
    "quay.io/thanos/thanos@sha256:aca3887cc68c58441627d7026b219167b048808affa3bd72b26144d9c25018e1|quay_io_thanos_thanos_v0_39_2_amd64.tar"
    "jimmidyson/configmap-reload@sha256:084de2d3533f9215eceef9a1feccfc11cad43cf382ea82ddfa4272f68df0614f|docker_io_jimmidyson_configmap-reload_v0_8_0_amd64.tar"
    "busybox@sha256:fd4a8673d0344c3a7f427fe4440d4b8dfd4fa59cfabbd9098f9eb0cb4ba905d0|docker_io_library_busybox_1_31_1_amd64.tar"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen@sha256:316cd3217236293ba00ab9b5eac4056b15d9ab870b3eeeeb99e0d9139a608aa3|registry_k8s_io_ingress-nginx_kube-webhook-certgen_v1_6_2_amd64.tar"
    "quay.io/kiwigrid/k8s-sidecar@sha256:2248efa2bf19ab7b0ae6c10017c484ddbdbfe2de3c1b255ee12c2c606b9d91e1|quay_io_kiwigrid_k8s-sidecar_1_30_10_amd64.tar"
)

success_count=0
total_count=${#IMAGES[@]}
current=1

echo "=== AMD64 이미지 다운로드 시작 (총 $total_count 개) ==="
echo ""

for image_entry in "${IMAGES[@]}"; do
    source_image="${image_entry%|*}"
    filename="${image_entry#*|}"
    output_path="$IMAGES_DIR/$filename"
    temp_path="$TEMP_DIR/$filename"
    
    echo "[$current/$total_count] 처리 중: $source_image"
    echo "                    -> $filename"
    
    # AMD64 이미지 pull
    echo "  🔽 AMD64 이미지 pull 중..."
    if docker pull "$source_image"; then
        echo "  ✅ Pull 성공"
        
        # 아키텍처 확인
        arch=$(docker inspect "$source_image" | grep -o '"Architecture": "[^"]*"' | cut -d'"' -f4)
        echo "  🔍 이미지 아키텍처: $arch"
        
        if [ "$arch" = "amd64" ]; then
            echo "  ✅ AMD64 아키텍처 확인됨"
            
            # 이미지를 tar 파일로 저장
            echo "  💾 이미지 저장 중: $filename"
            if docker save "$source_image" -o "$temp_path"; then
                echo "  ✅ 임시 저장 성공"
                
                # 최종 위치로 이동
                if mv "$temp_path" "$output_path"; then
                    echo "  ✅ 저장 완료: $output_path"
                    
                    # 파일 크기 확인
                    size=$(du -h "$output_path" | cut -f1)
                    echo "  📦 파일 크기: $size"
                    
                    success_count=$((success_count + 1))
                else
                    echo "  ❌ 파일 이동 실패: $temp_path -> $output_path"
                fi
            else
                echo "  ❌ 이미지 저장 실패: $source_image"
            fi
        else
            echo "  ❌ 잘못된 아키텍처: $arch (AMD64 필요)"
        fi
        
        # 로컬 이미지 정리
        docker rmi "$source_image" 2>/dev/null || true
    else
        echo "  ❌ Pull 실패: $source_image"
    fi
    
    current=$((current + 1))
    echo ""
done

# 임시 디렉토리 정리
rm -rf "$TEMP_DIR"

echo "========================================"
echo "  AMD64 이미지 다운로드 완료"
echo "========================================"
echo "성공: $success_count/$total_count 개"
echo "저장 위치: $IMAGES_DIR"
echo ""

if [ $success_count -eq $total_count ]; then
    echo "🎉 모든 AMD64 이미지가 성공적으로 저장되었습니다!"
else
    echo "⚠️  일부 이미지 다운로드에 실패했습니다."
fi

echo ""
echo "저장된 파일 목록:"
ls -lh "$IMAGES_DIR"

echo ""
echo "이미지 검증 명령어:"
echo "docker load -i $IMAGES_DIR/quay_io_prometheus_prometheus_v3_5_0_amd64.tar"
echo "docker inspect <loaded_image_id> | grep Architecture"
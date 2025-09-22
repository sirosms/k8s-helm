#!/bin/bash

# 폐쇄망 환경에서 Prometheus PVC 사전 생성 스크립트

NAMESPACE="devops-prometheus"

echo "=== Prometheus PVC 사전 생성 시작 ==="

# 네임스페이스 생성 (없으면)
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo "네임스페이스 $NAMESPACE 생성 중..."
    kubectl create namespace $NAMESPACE
    echo "✅ 네임스페이스 생성 완료"
else
    echo "✅ 네임스페이스 $NAMESPACE 이미 존재"
fi

echo ""
echo "=== PVC 생성 중 ==="

# PVC 파일 목록
PVC_FILES=(
    "prometheus-grafana-pvc.yaml"
    "prometheus-server-pvc.yaml"
    "alertmanager-pvc.yaml"
)

success_count=0
failed_count=0

for pvc_file in "${PVC_FILES[@]}"; do
    echo ""
    echo "PVC 생성: $pvc_file"
    
    if kubectl apply -f "pvc/$pvc_file"; then
        echo "✅ $pvc_file 생성 성공"
        success_count=$((success_count + 1))
    else
        echo "❌ $pvc_file 생성 실패"
        failed_count=$((failed_count + 1))
    fi
done

echo ""
echo "=== PVC 생성 완료 ==="
echo "성공: $success_count 개"
echo "실패: $failed_count 개"
echo ""

# PVC 상태 확인
echo "=== PVC 상태 확인 ==="
kubectl get pvc -n $NAMESPACE
echo ""

# 생성된 PVC 요약
echo "=== 생성된 PVC 요약 ==="
echo "1. prometheus-grafana (5Gi) - Grafana 데이터 저장"
echo "2. prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-prometheus-kube-prometheus-prometheus-0 (20Gi) - Prometheus 메트릭 데이터"
echo "3. alertmanager-prometheus-kube-prometheus-alertmanager-db-alertmanager-prometheus-kube-prometheus-alertmanager-0 (5Gi) - AlertManager 설정/데이터"
echo ""

if [ $failed_count -eq 0 ]; then
    echo "✅ 모든 PVC 생성이 완료되었습니다!"
    echo "이제 Prometheus를 설치하면 기존 PVC를 사용합니다."
else
    echo "⚠️ 일부 PVC 생성에 실패했습니다. 로그를 확인하세요."
fi

echo ""
echo "다음 단계: ./03_install_prometheus.sh 실행"
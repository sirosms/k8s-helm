#!/bin/bash

# 폐쇄망 환경에서 StatefulSet 생성 문제 해결 스크립트

NAMESPACE="devops-prometheus"

echo "=== 폐쇄망 환경 StatefulSet 문제 진단 및 해결 ==="
echo ""

echo "1. 현재 StatefulSet 상태 확인"
kubectl get statefulsets -n $NAMESPACE
echo ""

echo "2. StatefulSet이 없는 경우 원인 진단"
echo ""

echo "A. Prometheus Operator 상태 확인"
OPERATOR_POD=$(kubectl get pods -n $NAMESPACE -l "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OPERATOR_POD" ]; then
    echo "✅ Prometheus Operator Pod: $OPERATOR_POD"
    kubectl get pod -n $NAMESPACE $OPERATOR_POD -o jsonpath='{.status.phase}' 2>/dev/null
    echo ""
else
    echo "❌ Prometheus Operator Pod를 찾을 수 없습니다"
    echo "원인: Operator가 실행되지 않으면 StatefulSet이 생성되지 않습니다"
fi
echo ""

echo "B. CRD (Custom Resource Definitions) 확인"
REQUIRED_CRDS=(
    "prometheuses.monitoring.coreos.com"
    "alertmanagers.monitoring.coreos.com"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd $crd >/dev/null 2>&1; then
        echo "✅ CRD 존재: $crd"
    else
        echo "❌ CRD 없음: $crd"
        echo "   해결: helm uninstall 후 재설치 필요"
    fi
done
echo ""

echo "C. Prometheus/AlertManager Custom Resources 확인"
echo "Prometheus 리소스:"
kubectl get prometheus -n $NAMESPACE 2>/dev/null || echo "❌ Prometheus 리소스 없음"
echo ""
echo "AlertManager 리소스:"
kubectl get alertmanager -n $NAMESPACE 2>/dev/null || echo "❌ AlertManager 리소스 없음"
echo ""

echo "D. imagePullSecrets 확인 (폐쇄망 핵심)"
if kubectl get secret registry-local-credential -n $NAMESPACE >/dev/null 2>&1; then
    echo "✅ ECR registry secret 존재"
    
    # Secret 내용 확인
    SECRET_SERVER=$(kubectl get secret registry-local-credential -n $NAMESPACE -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | keys[0]' 2>/dev/null)
    echo "   Registry: $SECRET_SERVER"
else
    echo "❌ ECR registry secret이 없습니다"
    echo ""
    echo "해결 방법:"
    echo "kubectl create secret docker-registry registry-local-credential \\"
    echo "  --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \\"
    echo "  --docker-username=AWS \\"
    echo "  --docker-password=\$(aws ecr get-login-password --region ap-northeast-2) \\"
    echo "  --namespace=$NAMESPACE"
fi
echo ""

echo "E. 필수 이미지 존재 확인"
REQUIRED_IMAGES=(
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus:v3.5.0"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/alertmanager:v0.28.1"
)

for image in "${REQUIRED_IMAGES[@]}"; do
    echo "이미지 확인: $image"
    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "✅ 로컬에 존재"
    else
        echo "❌ 로컬에 없음"
        echo "   해결: ECR에서 pull 또는 push_to_ecr.sh 실행"
    fi
done
echo ""

echo "=== 문제 해결 방법 ==="
echo ""
echo "1. StatefulSet이 Pending 상태인 경우:"
echo "   kubectl describe statefulset -n $NAMESPACE"
echo "   kubectl describe pod -n $NAMESPACE <pod-name>"
echo ""
echo "2. 이미지 Pull 실패인 경우:"
echo "   ./push_to_ecr.sh  # 인터넷 연결 환경에서"
echo "   또는"
echo "   docker load < images/*.tar  # 이미지 파일이 있는 경우"
echo ""
echo "3. Operator 문제인 경우:"
echo "   kubectl delete pod -n $NAMESPACE \$OPERATOR_POD"
echo ""
echo "4. 완전 재설치:"
echo "   helm uninstall prometheus -n $NAMESPACE"
echo "   kubectl delete namespace $NAMESPACE"
echo "   ./03_install_prometheus.sh"
echo ""
echo "5. 네트워크 정책/Security Group 문제:"
echo "   - 클러스터 내 Pod 간 통신 허용"
echo "   - API Server와 Webhook 통신 허용"
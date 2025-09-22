#!/bin/bash

# Prometheus Operator 문제 진단 스크립트

NAMESPACE="devops-prometheus"

echo "=== Prometheus Operator 문제 진단 ==="
echo ""

echo "1. Pod 상태 확인"
kubectl get pods -n $NAMESPACE -l "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator"
echo ""

echo "2. 이미지 Pull 상태 확인"
OPERATOR_POD=$(kubectl get pods -n $NAMESPACE -l "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OPERATOR_POD" ]; then
    echo "Operator Pod: $OPERATOR_POD"
    kubectl describe pod -n $NAMESPACE $OPERATOR_POD | grep -A 10 "Events:"
else
    echo "❌ Operator Pod를 찾을 수 없습니다"
fi
echo ""

echo "3. ECR 로그인 상태 확인"
if kubectl get secret registry-local-credential -n $NAMESPACE >/dev/null 2>&1; then
    echo "✅ ECR registry secret 존재"
else
    echo "❌ ECR registry secret이 없습니다"
    echo "다음 명령어로 생성하세요:"
    echo "kubectl create secret docker-registry registry-local-credential \\"
    echo "  --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \\"
    echo "  --docker-username=AWS \\"
    echo "  --docker-password=\$(aws ecr get-login-password --region ap-northeast-2) \\"
    echo "  --namespace=$NAMESPACE"
fi
echo ""

echo "4. 필요한 이미지 확인"
REQUIRED_IMAGES=(
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-operator:v0.85.0"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-config-reloader:v0.85.0"
)

for image in "${REQUIRED_IMAGES[@]}"; do
    echo "이미지 확인: $image"
    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "✅ 로컬에 존재"
    else
        echo "❌ 로컬에 없음 - ECR에서 pull 필요"
        echo "docker pull $image"
    fi
done
echo ""

echo "5. CRD 설치 상태 확인"
CRD_LIST=(
    "alertmanagers.monitoring.coreos.com"
    "prometheuses.monitoring.coreos.com"
    "prometheusrules.monitoring.coreos.com"
    "servicemonitors.monitoring.coreos.com"
)

for crd in "${CRD_LIST[@]}"; do
    if kubectl get crd $crd >/dev/null 2>&1; then
        echo "✅ CRD 존재: $crd"
    else
        echo "❌ CRD 없음: $crd"
    fi
done
echo ""

echo "6. Readiness Probe 상태 (폐쇄망에서 흔한 문제)"
if [ -n "$OPERATOR_POD" ]; then
    echo "Readiness probe 테스트:"
    kubectl exec -n $NAMESPACE $OPERATOR_POD -- wget -q --spider --no-check-certificate https://localhost:10250/healthz
    if [ $? -eq 0 ]; then
        echo "✅ Health check 성공"
    else
        echo "❌ Health check 실패 - 네트워크 또는 인증서 문제"
    fi
fi
echo ""

echo "7. 권장 해결방법 (폐쇄망 환경)"
echo ""
echo "A. ECR 이미지가 없는 경우:"
echo "   - 인터넷 연결된 환경에서 ./push_to_ecr.sh 실행"
echo ""
echo "B. Pod가 0/1 Ready 상태로 멈춘 경우:"
echo "   - kubectl delete pod -n $NAMESPACE \$OPERATOR_POD  # Pod 재시작"
echo ""
echo "C. CRD 문제인 경우:"
echo "   - helm uninstall prometheus -n $NAMESPACE"
echo "   - kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack"  
echo "   - 재설치: ./03_install_prometheus.sh"
echo ""
echo "D. 네트워크 정책 문제인 경우:"
echo "   - 클러스터의 네트워크 정책 확인"
echo "   - Security Group에서 Pod 간 통신 허용"
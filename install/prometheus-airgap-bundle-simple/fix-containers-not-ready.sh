#!/bin/bash

# 폐쇄망 환경에서 ContainersNotReady 문제 해결 스크립트

NAMESPACE="devops-prometheus"

echo "=== 폐쇄망 환경 ContainersNotReady 문제 진단 및 해결 ==="
echo ""

echo "1. 모든 Pod 상태 확인"
kubectl get pods -n $NAMESPACE -o wide
echo ""

echo "2. Not Ready Pod 찾기"
NOT_READY_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -n "$NOT_READY_PODS" ]; then
    echo "❌ Not Ready Pods 발견:"
    for pod in $NOT_READY_PODS; do
        echo "   - $pod"
        kubectl describe pod -n $NAMESPACE $pod | tail -10
    done
else
    echo "✅ 모든 Pod가 Running 상태입니다"
fi
echo ""

echo "3. 0/1 Ready 상태인 Pod 찾기"
ZERO_READY_PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' | awk '$2=="false" {print $1}')
if [ -n "$ZERO_READY_PODS" ]; then
    echo "❌ 0/1 Ready 상태인 Pods:"
    for pod in $ZERO_READY_PODS; do
        echo ""
        echo "Pod: $pod"
        echo "--- 상세 진단 ---"
        
        # 컨테이너 상태 확인
        echo "컨테이너 상태:"
        kubectl get pod -n $NAMESPACE $pod -o jsonpath='{.status.containerStatuses[*].state}' | jq '.'
        echo ""
        
        # 최근 로그 확인
        echo "최근 로그 (마지막 10줄):"
        kubectl logs -n $NAMESPACE $pod --tail=10 2>/dev/null || echo "로그를 가져올 수 없습니다"
        echo ""
        
        # 이벤트 확인
        echo "최근 이벤트:"
        kubectl describe pod -n $NAMESPACE $pod | grep -A 10 "Events:"
        echo "---"
    done
else
    echo "✅ 모든 Pod가 Ready 상태입니다"
fi
echo ""

echo "4. 폐쇄망 환경 특화 문제 진단"
echo ""

echo "A. ECR 인증 상태 확인"
if kubectl get secret registry-local-credential -n $NAMESPACE >/dev/null 2>&1; then
    echo "✅ ECR registry secret 존재"
    
    # Secret 만료 확인 (ECR 토큰은 12시간)
    SECRET_AGE=$(kubectl get secret registry-local-credential -n $NAMESPACE -o jsonpath='{.metadata.creationTimestamp}')
    echo "   생성 시간: $SECRET_AGE"
    echo "   ECR 토큰은 12시간 후 만료됩니다"
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

echo "B. 필수 이미지 Pull 상태 확인"
REQUIRED_IMAGES=(
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-operator:v0.85.0"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-config-reloader:v0.85.0"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus:v3.5.0"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/alertmanager:v0.28.1"
    "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/grafana:11.1.0"
)

echo "로컬 Docker 이미지 확인:"
for image in "${REQUIRED_IMAGES[@]}"; do
    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "✅ $image"
    else
        echo "❌ $image (ECR에서 pull 필요)"
    fi
done
echo ""

echo "C. Readiness Probe 실패 확인"
echo "Readiness probe가 실패하는 Pod 찾기:"
kubectl get pods -n $NAMESPACE -o json | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false) | .metadata.name + ": " + (.status.containerStatuses[0].lastState.terminated.reason // "N/A")'
echo ""

echo "D. 리소스 부족 확인"
echo "노드 리소스 상태:"
kubectl top nodes 2>/dev/null || echo "메트릭 서버가 없어 리소스 확인 불가"
echo ""

echo "=== 문제 해결 방법 ==="
echo ""
echo "1. 이미지 Pull 실패 (가장 흔함):"
echo "   # ECR 재로그인"
echo "   aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
echo "   # 필수 이미지 pull"
echo "   ./download_images_simple.sh"
echo ""
echo "2. ECR 토큰 만료 (12시간 후):"
echo "   kubectl delete secret registry-local-credential -n $NAMESPACE"
echo "   kubectl create secret docker-registry registry-local-credential \\"
echo "     --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \\"
echo "     --docker-username=AWS \\"
echo "     --docker-password=\$(aws ecr get-login-password --region ap-northeast-2) \\"
echo "     --namespace=$NAMESPACE"
echo "   kubectl rollout restart deployment -n $NAMESPACE"
echo ""
echo "3. Readiness Probe 실패:"
echo "   kubectl describe pod -n $NAMESPACE <pod-name>"
echo "   kubectl logs -n $NAMESPACE <pod-name>"
echo "   # Pod 재시작"
echo "   kubectl delete pod -n $NAMESPACE <pod-name>"
echo ""
echo "4. 완전 재설치:"
echo "   helm uninstall prometheus -n $NAMESPACE"
echo "   kubectl delete namespace $NAMESPACE"
echo "   ./03_install_prometheus.sh"
#!/bin/bash
set -e

NAMESPACE="devops"
RELEASE_NAME="gitlab-runner"

echo "🗑️  GitLab Runner 제거 시작..."
echo ""

# 현재 설치 상태 확인
echo "=== 현재 설치 상태 확인 ==="
if ! helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    echo "GitLab Runner가 설치되어 있지 않습니다."
    exit 0
fi

echo "현재 설치된 GitLab Runner:"
helm list -n $NAMESPACE | grep $RELEASE_NAME

echo ""
echo "Pod 상태:"
kubectl get pods -n $NAMESPACE -l app=gitlab-runner

# 제거 확인
echo ""
read -p "GitLab Runner를 제거하시겠습니까? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "제거가 취소되었습니다."
    exit 0
fi

# Helm 제거
echo ""
echo "=== Helm Release 제거 ==="
helm uninstall $RELEASE_NAME -n $NAMESPACE

# Pod 제거 대기
echo ""
echo "=== Pod 제거 대기 ==="
echo "Pod가 완전히 제거될 때까지 대기 중..."
while kubectl get pods -n $NAMESPACE -l app=gitlab-runner 2>/dev/null | grep -q gitlab-runner; do
    echo "Pod 제거 중..."
    sleep 5
done

# ServiceAccount 및 RBAC 정리 (필요시)
echo ""
echo "=== 추가 리소스 정리 ==="
if kubectl get serviceaccount gitlab-runner -n $NAMESPACE &> /dev/null; then
    echo "ServiceAccount 제거 중..."
    kubectl delete serviceaccount gitlab-runner -n $NAMESPACE
fi

if kubectl get clusterrole gitlab-runner &> /dev/null; then
    echo "ClusterRole 제거 중..."
    kubectl delete clusterrole gitlab-runner
fi

if kubectl get clusterrolebinding gitlab-runner &> /dev/null; then
    echo "ClusterRoleBinding 제거 중..."
    kubectl delete clusterrolebinding gitlab-runner
fi

if kubectl get role gitlab-runner -n $NAMESPACE &> /dev/null; then
    echo "Role 제거 중..."
    kubectl delete role gitlab-runner -n $NAMESPACE
fi

if kubectl get rolebinding gitlab-runner -n $NAMESPACE &> /dev/null; then
    echo "RoleBinding 제거 중..."
    kubectl delete rolebinding gitlab-runner -n $NAMESPACE
fi

# 최종 상태 확인
echo ""
echo "=== 제거 결과 확인 ==="
echo "Helm Release 상태:"
helm list -n $NAMESPACE | grep $RELEASE_NAME || echo "GitLab Runner Release 제거됨"

echo ""
echo "Pod 상태:"
kubectl get pods -n $NAMESPACE -l app=gitlab-runner || echo "GitLab Runner Pod 제거됨"

echo ""
echo "🎉 GitLab Runner 제거 완료!"
echo ""
echo "참고사항:"
echo "- ECR 인증 정보 (registry-local-credential)는 보존됩니다"
echo "- GitLab에서 Runner 등록이 자동으로 해제되지 않을 수 있습니다"
echo "- 필요시 GitLab 웹 UI에서 수동으로 Runner를 제거하세요"
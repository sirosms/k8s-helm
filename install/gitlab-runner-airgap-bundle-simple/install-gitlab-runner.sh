#!/bin/bash
set -e

NAMESPACE="devops-runner"
RELEASE_NAME="gitlab-runner"

echo "🚀 GitLab Runner 17.6.0 설치 시작 (폐쇄망 환경)"
echo ""

# 네임스페이스 확인/생성
echo "=== 네임스페이스 설정 ==="
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "네임스페이스 '$NAMESPACE' 생성 중..."
    kubectl create namespace $NAMESPACE
else
    echo "네임스페이스 '$NAMESPACE' 이미 존재합니다."
fi

# ECR 인증 정보 확인
echo ""
echo "=== ECR 인증 정보 확인 ==="
if ! kubectl get secret registry-local-credential -n $NAMESPACE &> /dev/null; then
    echo "❌ ECR 인증 정보가 없습니다. 먼저 다음 명령어를 실행하세요:"
    echo "kubectl create secret docker-registry registry-local-credential \\"
    echo "  --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \\"
    echo "  --docker-username=AWS \\"
    echo "  --docker-password=\$(aws ecr get-login-password --region ap-northeast-2) \\"
    echo "  --namespace=$NAMESPACE"
    exit 1
else
    echo "✅ ECR 인증 정보가 설정되어 있습니다."
fi

# Runner 등록 토큰 확인
echo ""
echo "=== Runner 등록 토큰 확인 ==="
if ! grep -q "runnerRegistrationToken: \".*\"" values/gitlab-runner.yaml || grep -q "runnerRegistrationToken: \"\"" values/gitlab-runner.yaml; then
    echo "❌ Runner 등록 토큰이 설정되지 않았습니다."
    echo "GitLab에서 Runner 등록 토큰을 획득한 후 values/gitlab-runner.yaml 파일의 runnerRegistrationToken을 설정하세요."
    echo ""
    echo "토큰 획득 방법:"
    echo "1. GitLab 웹 UI에 접속 (https://gitlab-dev.samsungena.io)"
    echo "2. Admin Area > Runners 또는 프로젝트 Settings > CI/CD > Runners 섹션으로 이동"
    echo "3. 'Register a runner' 버튼을 클릭하여 등록 토큰을 획득"
    echo "4. values/gitlab-runner.yaml 파일에서 runnerRegistrationToken 값을 업데이트"
    echo ""
    read -p "토큰을 설정한 후 계속하시겠습니까? (y/N): " token_confirm
    if [[ ! $token_confirm =~ ^[Yy]$ ]]; then
        echo "설치가 중단되었습니다."
        exit 1
    fi
fi

# 기존 설치 확인
echo ""
echo "=== 기존 설치 확인 ==="
if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    echo "⚠️ GitLab Runner가 이미 설치되어 있습니다."
    read -p "기존 설치를 업그레이드하시겠습니까? (y/N): " upgrade_confirm
    if [[ $upgrade_confirm =~ ^[Yy]$ ]]; then
        ACTION="upgrade"
    else
        echo "설치가 취소되었습니다."
        exit 0
    fi
else
    ACTION="install"
fi

# Helm 설치/업그레이드 실행
echo ""
echo "=== GitLab Runner Helm $ACTION ==="
if [ "$ACTION" = "install" ]; then
    helm install $RELEASE_NAME charts/gitlab-runner \\
        -f values/gitlab-runner.yaml \\
        -n $NAMESPACE \\
        --timeout=10m
else
    helm upgrade $RELEASE_NAME charts/gitlab-runner \\
        -f values/gitlab-runner.yaml \\
        -n $NAMESPACE \\
        --timeout=10m
fi

# 설치 결과 확인
echo ""
echo "=== 설치 결과 확인 ==="
echo "Helm Release 상태:"
helm status $RELEASE_NAME -n $NAMESPACE

echo ""
echo "Pod 상태:"
kubectl get pods -n $NAMESPACE -l app=gitlab-runner

# Pod 준비 대기
echo ""
echo "=== Pod 준비 대기 ==="
kubectl wait --for=condition=ready pod -l app=gitlab-runner -n $NAMESPACE --timeout=300s

# 최종 상태 출력
echo ""
echo "=== 최종 상태 ==="
kubectl get pods -n $NAMESPACE -l app=gitlab-runner
echo ""
kubectl get svc -n $NAMESPACE -l app=gitlab-runner

# Runner 등록 확인
echo ""
echo "=== Runner 등록 확인 ==="
echo "GitLab Runner 로그를 확인하여 등록이 성공했는지 확인하세요:"
echo "kubectl logs -n $NAMESPACE -l app=gitlab-runner"
echo ""
echo "GitLab 웹 UI의 Admin Area > Runners 또는 프로젝트 Settings > CI/CD > Runners에서"
echo "새로운 Runner가 등록되었는지 확인하세요."

echo ""
echo "🎉 GitLab Runner 17.6.0 설치 완료!"
echo ""
echo "=== 사용법 ==="
echo "1. .gitlab-ci.yml 파일을 프로젝트에 생성"
echo "2. CI/CD 파이프라인이 자동으로 실행됩니다"
echo "3. Runner 상태는 다음 명령어로 확인:"
echo "   kubectl get pods -n $NAMESPACE -l app=gitlab-runner"
echo "   kubectl logs -n $NAMESPACE -l app=gitlab-runner"
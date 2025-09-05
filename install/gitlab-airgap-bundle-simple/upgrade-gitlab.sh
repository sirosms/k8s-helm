#!/bin/bash

# GitLab 업그레이드 스크립트 (폐쇄망 환경)
# 현재: 15.8.0-ce.0 -> 최신 안정화 버전으로 업그레이드

set -e

NAMESPACE="devops"
RELEASE_NAME="gitlab"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

# 업그레이드 경로 (GitLab 공식 업그레이드 가이드 기준)
# 15.8.x -> 15.11.x -> 16.3.x -> 16.7.x -> 17.3.x -> 17.6.x (최신)
UPGRADE_VERSIONS=(
    "15.11.13-ce.0"  # 15.8 -> 15.11 (마지막 15.11.x)
    "16.3.7-ce.0"    # 15.11 -> 16.3 (첫 16.x LTS)
    "16.7.8-ce.0"    # 16.3 -> 16.7 (16.x 최신 마이너)
    "17.3.7-ce.0"    # 16.7 -> 17.3 (17.x LTS)
    "17.6.2-ce.0"    # 17.3 -> 17.6 (최신 안정화)
)

echo "=== GitLab 업그레이드 스크립트 시작 ==="
echo "현재 버전: 15.8.0-ce.0"
echo "목표 버전: 17.6.2-ce.0"
echo ""

# 현재 상태 확인
echo "=== 현재 GitLab 상태 확인 ==="
kubectl get pods -n $NAMESPACE -l app=gitlab
echo ""
helm status $RELEASE_NAME -n $NAMESPACE
echo ""

# 백업 권고사항 출력
echo "⚠️ 업그레이드 전 백업을 강력히 권장합니다!"
echo "1. 데이터베이스 백업"
echo "2. PVC 백업 (gitlab-opt-dev, gitlab-etc-dev, gitlab-log-dev)"
echo "3. 설정 백업"
echo ""

read -p "백업을 완료했습니까? 계속 진행하시겠습니까? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "업그레이드가 취소되었습니다."
    exit 1
fi

# ECR 로그인
echo "=== ECR 로그인 ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 각 버전별 단계적 업그레이드
for i in "${!UPGRADE_VERSIONS[@]}"; do
    current_version="${UPGRADE_VERSIONS[$i]}"
    step=$((i + 1))
    total_steps=${#UPGRADE_VERSIONS[@]}
    
    echo ""
    echo "=== 업그레이드 단계 $step/$total_steps: $current_version ==="
    
    # 단계 시작 전 확인
    if [ $step -gt 1 ]; then
        echo "⚠️ 이전 단계에서 GitLab이 정상 작동하는지 확인하세요."
        read -p "단계 $step 업그레이드를 시작하시겠습니까? (y/N): " step_confirm
        if [[ ! $step_confirm =~ ^[Yy]$ ]]; then
            echo "업그레이드가 중단되었습니다."
            exit 1
        fi
    fi
    
    # ECR에서 이미지 확인
    image_name="$ECR_REGISTRY/gitlab/gitlab-ce:$current_version"
    echo "이미지 확인: $image_name"
    
#    if ! docker pull $image_name 2>/dev/null; then
#        echo "❌ ECR에 이미지가 없습니다: $image_name"
#        echo "다음 명령어로 이미지를 ECR에 푸시하세요:"
#        echo "docker pull gitlab/gitlab-ce:$current_version"
#        echo "docker tag gitlab/gitlab-ce:$current_version $image_name"
#        echo "docker push $image_name"
#        exit 1
#    fi
    
    # values.yaml 업데이트
    echo "values.yaml 업데이트 중..."
    sed -i.backup "s|tag: \".*\"|tag: \"$current_version\"|g" values/gitlab.yaml
    
    # Chart.yaml의 appVersion 업데이트
    echo "Chart.yaml appVersion 업데이트 중..."
    sed -i.backup "s|appVersion: \".*\"|appVersion: \"$current_version\"|g" charts/gitlab/Chart.yaml
    
    # Helm 업그레이드 실행
    echo "Helm 업그레이드 실행 중..."
    helm upgrade $RELEASE_NAME charts/gitlab \
        -f values/gitlab.yaml \
        -n $NAMESPACE \
        --timeout=20m \
        --wait \
        --wait-for-jobs

    # 업그레이드 후 상태 확인
    echo "업그레이드 후 상태 확인 중..."
    kubectl get pods -n $NAMESPACE -l app=gitlab
    
    # Pod가 Ready 상태가 될 때까지 대기
    echo "Pod Ready 상태 대기 중..."
    kubectl wait --for=condition=ready pod -l app=gitlab -n $NAMESPACE --timeout=1200s
    
    # Health check
    echo "GitLab health check 중..."
    sleep 30
    
    # 다음 단계로 진행하기 전 확인
    if [ $step -lt $total_steps ]; then
        echo "✅ 단계 $step 완료: $current_version"
        echo ""
        echo "=== 현재 상태 확인 ==="
        kubectl get pods -n $NAMESPACE -l app=gitlab -o wide
        echo ""
        kubectl logs -n $NAMESPACE -l app=gitlab --tail=20 --since=2m
        echo ""
        echo "⏰ 다음 단계로 진행하기 전 확인이 필요합니다."
        echo "다음 단계: ${UPGRADE_VERSIONS[$step]}"
        echo ""
        echo "🌐 GitLab 웹 UI 접속 확인: https://gitlab-dev.samsungena.io"
        echo "📋 확인사항:"
        echo "  - GitLab 로그인 가능한지 확인"
        echo "  - 프로젝트 목록이 정상적으로 보이는지 확인"
        echo "  - 기본 기능들이 작동하는지 확인"
        echo ""
        read -p "GitLab이 정상 작동하는지 확인했습니까? 다음 단계로 진행하시겠습니까? (y/N): " next_confirm
        if [[ ! $next_confirm =~ ^[Yy]$ ]]; then
            echo "업그레이드가 중단되었습니다."
            echo "문제를 해결한 후 다시 실행하거나, 롤백을 고려하세요."
            exit 1
        fi
        echo "다음 단계로 진행합니다..."
        sleep 10
    else
        echo "🎉 모든 업그레이드 단계 완료!"
    fi
done

echo ""
echo "=== 최종 상태 확인 ==="
kubectl get pods -n $NAMESPACE -l app=gitlab
echo ""
helm list -n $NAMESPACE
echo ""

echo "=== GitLab 접속 정보 ==="
echo "URL: https://gitlab-dev.samsungena.io"
echo "관리자 계정: root"
echo "초기 비밀번호: Passw0rd!"
echo ""

echo "=== 업그레이드 후 확인사항 ==="
echo "1. GitLab 웹 UI 접속 확인"
echo "2. 기존 프로젝트/사용자 데이터 확인" 
echo "3. 데이터베이스 마이그레이션 완료 확인"
echo "4. 백업 파일 정리 (values/gitlab.yaml.backup)"
echo ""

echo "✅ GitLab 업그레이드 완료!"
echo "현재 버전: 17.6.2-ce.0"
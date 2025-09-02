#!/bin/bash

# 예시: 오류 처리가 포함된 배포 스크립트
# 오류 발생시 자동으로 GitHub Issue 생성 및 프로젝트 백로그에 추가

# 오류 핸들러 로드
source "$(dirname "$0")/error_handler.sh"

echo "=== 배포 스크립트 시작 ==="

# 예시 명령들 (오류 발생시 자동으로 이슈 생성됨)
echo "네임스페이스 확인 중..."
kubectl get namespace devops || handle_error "kubectl get namespace devops" "namespace not found"

echo "Helm 차트 설치 중..."
helm upgrade --install myapp ./charts/myapp -n devops || handle_error "helm upgrade myapp" "helm installation failed"

echo "Pod 상태 확인 중..."
kubectl get pods -n devops || handle_error "kubectl get pods" "failed to get pods"

echo "=== 배포 스크립트 완료 ==="
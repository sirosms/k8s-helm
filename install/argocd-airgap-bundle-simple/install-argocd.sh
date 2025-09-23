#!/bin/bash

# ArgoCD Airgap Bundle Installation Script
# Version: ArgoCD v3.1.3 (Chart 8.3.4)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="devops-argocd"
RELEASE_NAME="argocd"
CHART_VERSION="8.3.4"
GITLAB_EXTERNAL_URL="argocd-dev.secl.samsung.co.kr"

# Configuration
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo "🚀 Installing ArgoCD in airgap environment..."

# Create namespace
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create image pull secret for ECR
echo "🔐 Creating ECR image pull secret..."
kubectl create secret docker-registry registry-local-credential \
    --docker-server="$ECR_REGISTRY" \
    --docker-username=AWS \
    --docker-password="$(aws ecr get-login-password --region ap-northeast-2)" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using Helm
echo "⚙️  Installing ArgoCD with Helm..."
helm upgrade --install "$RELEASE_NAME" \
    charts/argo-cd \
    --namespace "$NAMESPACE" \
    --values values/argocd.yaml \
    --wait

echo ""
echo "✅ ArgoCD installation completed!"
echo ""
echo "🌐 접속 URL: $GITLAB_EXTERNAL_URL"
echo "📋 Useful commands:"
echo "  🔍 Check status: kubectl get pods -n $NAMESPACE"
echo "  🌐 Get admin password: kubectl get secret argocd-initial-admin-secret -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo "  🔗 Port forward: kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:80"
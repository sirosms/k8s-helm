#!/bin/bash

# Reflector Installation Script for Airgap Environment
# Usage: ./install-reflector.sh

set -e

# Configuration
NAMESPACE="devops-common"
RELEASE_NAME="reflector"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo "🚀 Starting Reflector installation..."
echo "📦 Namespace: ${NAMESPACE}"
echo "🏷️  Release: ${RELEASE_NAME}"
echo "📍 ECR Registry: ${ECR_REGISTRY}"
echo ""

# Create namespace if it doesn't exist
echo "🏗️  Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Apply TLS secret that Reflector will mirror to other namespaces
echo "🔐 Applying TLS secret to be mirrored by Reflector..."
kubectl apply -f samsungena.io-secret.yaml -n ${NAMESPACE}

# Install Reflector using Helm
echo "📦 Installing Reflector with Helm..."
helm upgrade --install ${RELEASE_NAME} ./charts/reflector-6.1.47.tgz \
  --namespace ${NAMESPACE} \
  --set image.repository="${ECR_REGISTRY}/reflector/kubernetes-reflector" \
  --set image.tag="6.1.47" \
  --set image.pullPolicy="IfNotPresent" \
  --set imagePullSecrets[0].name="samsungena.io-secret" \
  --set serviceAccount.create=true \
  --set serviceAccount.name="reflector" \
  --values values/reflector.yaml \
  --wait

echo ""
echo "✅ Reflector installation completed!"
echo ""
echo "📋 Checking deployment status..."
kubectl get pods -n ${NAMESPACE}
echo ""
echo "🔍 To check Reflector logs:"
echo "   kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=reflector"
echo ""
echo "🛠️  To uninstall Reflector:"
echo "   helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "   kubectl delete namespace ${NAMESPACE}"
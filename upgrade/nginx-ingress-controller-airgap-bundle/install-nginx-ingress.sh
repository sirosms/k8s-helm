#!/bin/bash

# Nginx Ingress Controller Installation Script for Airgap Environment
# Usage: ./install-nginx-ingress.sh

set -e

# Configuration
NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

echo "🚀 Starting Nginx Ingress Controller installation..."
echo "📦 Namespace: ${NAMESPACE}"
echo "🏷️  Release: ${RELEASE_NAME}"
echo "📍 ECR Registry: ${ECR_REGISTRY}"
echo ""

# Create namespace if it doesn't exist
echo "🏗️  Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Apply image pull secret if exists
if [ -f "samsungena.io-secret.yaml" ]; then
    echo "🔐 Applying image pull secret..."
    kubectl apply -f samsungena.io-secret.yaml -n ${NAMESPACE}
fi

# Install Nginx Ingress Controller using Helm
echo "📦 Installing Nginx Ingress Controller with Helm..."
helm upgrade --install ${RELEASE_NAME} ./charts/ingress-nginx-4.1.4.tgz \
  --namespace ${NAMESPACE} \
  --set controller.image.registry="${ECR_REGISTRY}" \
  --set controller.image.image="ingress-nginx/controller" \
  --set controller.image.tag="v1.3.0" \
  --set controller.image.pullPolicy="IfNotPresent" \
  --set controller.admissionWebhooks.patch.image.registry="${ECR_REGISTRY}" \
  --set controller.admissionWebhooks.patch.image.image="ingress-nginx/kube-webhook-certgen" \
  --set controller.admissionWebhooks.patch.image.tag="v1.1.1" \
  --set controller.admissionWebhooks.patch.image.pullPolicy="IfNotPresent" \
  --set defaultBackend.image.registry="${ECR_REGISTRY}" \
  --set defaultBackend.image.image="defaultbackend-amd64" \
  --set defaultBackend.image.tag="1.5" \
  --set controller.service.type="LoadBalancer" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true" \
  --values values/nginx-ingress.yaml \
  --wait

echo ""
echo "✅ Nginx Ingress Controller installation completed!"
echo ""
echo "📋 Checking deployment status..."
kubectl get pods -n ${NAMESPACE}
echo ""
echo "🌐 Checking service status..."
kubectl get svc -n ${NAMESPACE}
echo ""
echo "🔍 To check Nginx Ingress Controller logs:"
echo "   kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx"
echo ""
echo "🛠️  To uninstall Nginx Ingress Controller:"
echo "   helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "   kubectl delete namespace ${NAMESPACE}"
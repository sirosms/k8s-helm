#!/bin/bash

# Push Nginx Ingress Controller images to ECR for Airgap Environment
# Usage: ./push-to-ecr.sh

set -e

# Configuration
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
AWS_REGION="ap-northeast-2"

echo "🚀 Starting image push to ECR..."
echo "📍 ECR Registry: ${ECR_REGISTRY}"
echo "🌏 AWS Region: ${AWS_REGION}"
echo ""

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Load images from tar files
echo "📦 Loading Docker images..."
if [ -f "images/ingress-nginx-controller-v1.3.0.tar" ]; then
    echo "Loading ingress-nginx-controller:v1.3.0..."
    docker load -i images/ingress-nginx-controller-v1.3.0.tar
fi

# Create ECR repositories if they don't exist
echo "🏗️  Creating ECR repositories..."
aws ecr describe-repositories --repository-names ingress-nginx/controller --region ${AWS_REGION} 2>/dev/null || \
    aws ecr create-repository --repository-name ingress-nginx/controller --region ${AWS_REGION}

aws ecr describe-repositories --repository-names ingress-nginx/kube-webhook-certgen --region ${AWS_REGION} 2>/dev/null || \
    aws ecr create-repository --repository-name ingress-nginx/kube-webhook-certgen --region ${AWS_REGION}

# Tag and push images
echo "🏷️  Tagging and pushing images..."

# Nginx Ingress Controller
echo "Pushing ingress-nginx/controller:v1.3.0..."
docker tag registry.k8s.io/ingress-nginx/controller:v1.3.0 ${ECR_REGISTRY}/ingress-nginx/controller:v1.3.0
docker push ${ECR_REGISTRY}/ingress-nginx/controller:v1.3.0

# Kube Webhook CertGen
echo "Pushing ingress-nginx/kube-webhook-certgen:v1.1.1..."
docker tag registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.1.1 ${ECR_REGISTRY}/ingress-nginx/kube-webhook-certgen:v1.1.1
docker push ${ECR_REGISTRY}/ingress-nginx/kube-webhook-certgen:v1.1.1

echo ""
echo "✅ All images pushed to ECR successfully!"
echo ""
echo "📋 Pushed images:"
echo "   ${ECR_REGISTRY}/ingress-nginx/controller:v1.3.0"
echo "   ${ECR_REGISTRY}/ingress-nginx/kube-webhook-certgen:v1.1.1"
#!/bin/bash

# ArgoCD Airgap Bundle ECR Push Script
# Version: ArgoCD v3.1.3 (Chart 8.3.4)

set -e

# Configuration
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
AWS_REGION="ap-northeast-2"

# Define images to push
IMAGES=(
    "quay.io/argoproj/argocd:v3.1.3,argocd:v3.1.3"
    "redis:7.2.8-alpine,redis:7.2.8-alpine"
    "ghcr.io/dexidp/dex:v2.44.0,dex:v2.44.0"
)

echo "🔄 Pushing ArgoCD images to ECR..."

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Process each image
for image_pair in "${IMAGES[@]}"; do
    original_image=$(echo "$image_pair" | cut -d, -f1)
    ecr_target=$(echo "$image_pair" | cut -d, -f2)
    ecr_full_path="${ECR_REGISTRY}/${ecr_target}"
    
    echo "📤 Processing: $original_image -> $ecr_full_path"
    
    # Create ECR repository if it doesn't exist
    repo_name=$(echo "$ecr_target" | cut -d: -f1)
    aws ecr describe-repositories --repository-names "$repo_name" --region $AWS_REGION >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$repo_name" --region $AWS_REGION >/dev/null
    
    # Tag and push image
    if docker tag "$original_image" "$ecr_full_path"; then
        if docker push "$ecr_full_path"; then
            echo "✅ Pushed: $ecr_full_path"
        else
            echo "❌ Failed to push: $ecr_full_path"
            exit 1
        fi
    else
        echo "❌ Failed to tag: $original_image"
        exit 1
    fi
done

echo ""
echo "✅ ArgoCD images successfully pushed to ECR!"
echo "🏷️  ECR Registry: $ECR_REGISTRY"
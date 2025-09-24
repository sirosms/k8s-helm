#!/bin/bash

# ArgoCD Airgap Bundle ECR Push Script
# Version: ArgoCD v2.8.15 (Chart 5.46.8) - K8s 1.22.5 Compatible

set -e

# Configuration
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
AWS_REGION="ap-northeast-2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Define images to load and push
IMAGES=(
    "argocd-v2.8.15.tar,quay.io/argoproj/argocd:v2.8.15,argocd:v2.8.15"
    "redis-7.0.15-alpine.tar,redis:7.0.15-alpine,redis:7.0.15-alpine"
    "dex-v2.37.0.tar,ghcr.io/dexidp/dex:v2.37.0,dex:v2.37.0"
)

echo "🔄 Pushing ArgoCD images to ECR..."

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Process each image
for image_info in "${IMAGES[@]}"; do
    tar_file=$(echo "$image_info" | cut -d, -f1)
    original_image=$(echo "$image_info" | cut -d, -f2)
    ecr_target=$(echo "$image_info" | cut -d, -f3)
    ecr_full_path="${ECR_REGISTRY}/${ecr_target}"
    tar_path="${IMAGES_DIR}/${tar_file}"
    
    echo "📤 Processing: $tar_file -> $ecr_full_path"
    
    # Load image from tar file
    if [ -f "$tar_path" ]; then
        echo "📥 Loading image from: $tar_path"
        docker load -i "$tar_path"
    else
        echo "❌ Tar file not found: $tar_path"
        exit 1
    fi
    
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
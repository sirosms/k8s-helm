#!/bin/bash

# GitLab Airgap Bundle - Push images to ECR script
# Usage: ./push-to-ecr.sh

set -e

# Configuration
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="866376286331"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "🚀 Starting GitLab images push to ECR..."
echo "📍 Region: ${AWS_REGION}"
echo "🏢 Account ID: ${AWS_ACCOUNT_ID}"
echo "📦 Registry: ${ECR_REGISTRY}"
echo ""

# Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Read images from meta/images.txt
if [ -f "meta/images.txt" ]; then
    echo "📋 Reading images from meta/images.txt..."
    while IFS= read -r image_line; do
        # Skip empty lines and comments
        [[ -z "$image_line" || "$image_line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse image name and tag
        image_name=$(echo "$image_line" | cut -d':' -f1)
        image_tag=$(echo "$image_line" | cut -d':' -f2)
        
        # Extract repository name (last part after /)
        repo_name=$(basename "$image_name")
        
        echo "📦 Processing: $image_name:$image_tag"
        
        # Check if ECR repository exists, create if not
        if ! aws ecr describe-repositories --repository-names "$repo_name" --region ${AWS_REGION} >/dev/null 2>&1; then
            echo "🏗️  Creating ECR repository: $repo_name"
            aws ecr create-repository --repository-name "$repo_name" --region ${AWS_REGION}
        fi
        
        # Load image from tar file if exists
        tar_file="images/${image_name//\//_}_${image_tag}.tar"
        if [ -f "$tar_file" ]; then
            echo "📥 Loading image from: $tar_file"
            docker load -i "$tar_file"
        fi
        
        # Tag image for ECR
        ecr_image_name="${ECR_REGISTRY}/${repo_name}:${image_tag}"
        echo "🏷️  Tagging: $image_name:$image_tag -> $ecr_image_name"
        docker tag "$image_name:$image_tag" "$ecr_image_name"
        
        # Push to ECR
        echo "📤 Pushing: $ecr_image_name"
        docker push "$ecr_image_name"
        
        echo "✅ Successfully pushed: $ecr_image_name"
        echo ""
        
    done < meta/images.txt
else
    echo "❌ meta/images.txt not found!"
    exit 1
fi

echo "🎉 All images pushed to ECR successfully!"
echo ""
echo "📝 ECR Repository URLs:"
echo "   - ${ECR_REGISTRY}/gitlab-webservice-ce:v15.8.0"
echo ""
echo "🔧 To use in Kubernetes, update your deployment images to:"
echo "   - ${ECR_REGISTRY}/gitlab-webservice-ce:v15.8.0"
#!/bin/bash

# Reflector Airgap Bundle - Push images to ECR script
# Usage: ./push-to-ecr.sh

set -e

# Configuration
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="866376286331"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "🚀 Starting Reflector images push to ECR..."
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
        
        # Extract image name from tar file
        tar_file="$image_line"
        
        # Remove .tar extension and extract image info
        image_info=$(basename "$tar_file" .tar)
        
        # For reflector-v6.1.47.tar -> emberstack/kubernetes-reflector:6.1.47
        if [[ "$image_info" == reflector-v* ]]; then
            original_image_name="emberstack/kubernetes-reflector"
            image_name="kubernetes-reflector"
            image_tag="${image_info#reflector-v}"
        else
            echo "❌ Unknown image format: $image_info"
            continue
        fi
        
        echo "📦 Processing: $original_image_name:$image_tag"
        
        # Check if ECR repository exists, create if not
        if ! aws ecr describe-repositories --repository-names "reflector/$image_name" --region ${AWS_REGION} >/dev/null 2>&1; then
            echo "🏗️  Creating ECR repository: reflector/$image_name"
            aws ecr create-repository --repository-name "reflector/$image_name" --region ${AWS_REGION}
        fi
        
        # Load image from tar file
        tar_file_path="images/$tar_file"
        if [ -f "$tar_file_path" ]; then
            echo "📥 Loading image from: $tar_file_path"
            docker load -i "$tar_file_path"
        else
            echo "❌ Tar file not found: $tar_file_path"
            continue
        fi
        
        # Tag image for ECR
        ecr_image_name="${ECR_REGISTRY}/reflector/${image_name}:${image_tag}"
        echo "🏷️  Tagging: $original_image_name:$image_tag -> $ecr_image_name"
        docker tag "$original_image_name:$image_tag" "$ecr_image_name"
        
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

echo "🎉 All Reflector images pushed to ECR successfully!"
echo ""
echo "📝 ECR Repository URLs:"
echo "   - ${ECR_REGISTRY}/reflector/kubernetes-reflector:6.1.47"
echo ""
echo "🔧 To use in Kubernetes, update your deployment images to:"
echo "   - ${ECR_REGISTRY}/reflector/kubernetes-reflector:6.1.47"
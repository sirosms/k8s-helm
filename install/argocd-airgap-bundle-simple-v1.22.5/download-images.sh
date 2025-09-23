#!/bin/bash

# ArgoCD Airgap Bundle Image Download Script
# Version: ArgoCD v3.1.3 (Chart 8.3.4)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Create images directory
mkdir -p "$IMAGES_DIR"

# ArgoCD Images
ARGOCD_IMAGES=(
    "quay.io/argoproj/argocd:v3.1.3"
    "redis:7.2.8-alpine"
    "ghcr.io/dexidp/dex:v2.44.0"
)

echo "🔄 Downloading ArgoCD images for airgap deployment..."

for image in "${ARGOCD_IMAGES[@]}"; do
    echo "📥 Downloading: $image"
    
    # Extract image name for filename
    image_name=$(echo "$image" | sed 's|[/:@]|-|g')
    output_file="${IMAGES_DIR}/${image_name}.tar"
    
    # Pull and save image
    echo "🔄 Pulling $image..."
    if docker pull "$image" --platform linux/amd64; then
        echo "💾 Attempting to save to $output_file..."
        # Try different save methods due to Docker Desktop manifest issues
        if docker save "$image" > "$output_file" 2>/dev/null; then
            echo "✅ Saved: $output_file"
        elif timeout 30 docker save "$image" -o "$output_file" 2>/dev/null; then
            echo "✅ Saved: $output_file"
        else
            echo "⚠️  Save failed for $image, but image is pulled locally"
            echo "💡 You can manually export later with: docker save $image -o $output_file"
        fi
    else
        echo "❌ Failed to download: $image"
        continue
    fi
done

echo ""
echo "📊 Downloaded images summary:"
ls -lh "$IMAGES_DIR"/*.tar

echo ""
echo "✅ ArgoCD airgap image download completed!"
echo "📁 Images saved in: $IMAGES_DIR"
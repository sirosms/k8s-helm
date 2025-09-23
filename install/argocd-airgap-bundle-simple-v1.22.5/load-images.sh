#!/bin/bash

# ArgoCD Airgap Bundle Image Load Script
# Version: ArgoCD v3.1.3 (Chart 8.3.4)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"

# Check if images directory exists
if [ ! -d "$IMAGES_DIR" ]; then
    echo "❌ Images directory not found: $IMAGES_DIR"
    echo "Please run download-images.sh first"
    exit 1
fi

echo "🔄 Loading ArgoCD images for airgap deployment..."

# Load all tar files in images directory
for tar_file in "$IMAGES_DIR"/*.tar; do
    if [ -f "$tar_file" ]; then
        echo "📥 Loading: $(basename "$tar_file")"
        if docker load -i "$tar_file"; then
            echo "✅ Loaded: $(basename "$tar_file")"
        else
            echo "❌ Failed to load: $(basename "$tar_file")"
            exit 1
        fi
    fi
done

echo ""
echo "📊 Loaded images:"
docker images | grep -E "(argoproj|redis|dex)" | head -10

echo ""
echo "✅ ArgoCD airgap image loading completed!"
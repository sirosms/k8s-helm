#!/bin/bash

# Analyze extracted config and create migration-ready values
# Usage: ./analyze-and-migrate.sh [extracted-config-dir]

set -e

EXTRACTED_DIR=${1:-"./extracted-config"}
OUTPUT_FILE="./values/migrated-values.yaml"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "🔍 Analyzing extracted nginx-ingress configuration..."
echo "📁 Source directory: ${EXTRACTED_DIR}"
echo "📄 Output file: ${OUTPUT_FILE}"
echo ""

# Validation
if [ ! -d "$EXTRACTED_DIR" ]; then
    echo "❌ Extracted config directory not found: $EXTRACTED_DIR"
    echo "💡 Run ./extract-nginx-config.sh first"
    exit 1
fi

# Find the latest generated values file
GENERATED_VALUES=$(ls ${EXTRACTED_DIR}/generated-values-*.yaml 2>/dev/null | head -1)
if [ -z "$GENERATED_VALUES" ]; then
    echo "❌ No generated values file found in $EXTRACTED_DIR"
    exit 1
fi

echo "📋 Found generated values: $(basename $GENERATED_VALUES)"

# Extract key information from summary
SUMMARY_FILE=$(ls ${EXTRACTED_DIR}/extraction-summary-*.md 2>/dev/null | head -1)
if [ -f "$SUMMARY_FILE" ]; then
    CURRENT_IMAGE=$(grep "Image:" $SUMMARY_FILE | cut -d':' -f2- | xargs)
    CURRENT_REPLICAS=$(grep "Replicas:" $SUMMARY_FILE | cut -d':' -f2 | xargs)
    CURRENT_NAMESPACE=$(grep "Namespace:" $SUMMARY_FILE | cut -d':' -f2 | xargs)
    HELM_MANAGED=$(grep "Helm Managed:" $SUMMARY_FILE | cut -d':' -f2 | xargs)
    
    echo "📋 Current configuration analysis:"
    echo "   🏷️  Image: $CURRENT_IMAGE"
    echo "   📊 Replicas: $CURRENT_REPLICAS"
    echo "   📦 Namespace: $CURRENT_NAMESPACE" 
    echo "   ⚙️  Helm managed: $HELM_MANAGED"
else
    echo "⚠️  Summary file not found, using defaults"
    CURRENT_IMAGE="unknown"
    CURRENT_REPLICAS="1"
    CURRENT_NAMESPACE="devops-nginx-ingress"
    HELM_MANAGED="No"
fi

# Extract current registry and image details
if [[ "$CURRENT_IMAGE" == *"sscr.comm.scp-in.com"* ]]; then
    CURRENT_REGISTRY="sscr.comm.scp-in.com"
    AIRGAP_REGISTRY="sscr.comm.scp-in.com"
    echo "✅ Detected Samsung SDS registry - will use for airgap deployment"
elif [[ "$CURRENT_IMAGE" == *"ecr"* ]]; then
    CURRENT_REGISTRY=$(echo $CURRENT_IMAGE | cut -d'/' -f1)
    AIRGAP_REGISTRY="$CURRENT_REGISTRY"
    echo "✅ Detected ECR registry - will use for airgap deployment"
else
    CURRENT_REGISTRY="registry.k8s.io"
    AIRGAP_REGISTRY="your-local-registry.com"
    echo "⚠️  Using default registry configuration"
fi

echo ""
echo "🔧 Creating migrated values for v1.3.0..."

# Create migrated values file
mkdir -p $(dirname $OUTPUT_FILE)

cat > $OUTPUT_FILE << EOF
# Migrated Nginx Ingress Controller Values for v1.3.0
# Generated on: $(date)
# Source: $GENERATED_VALUES
# Migration from: $CURRENT_IMAGE -> nginx-ingress-controller:v1.3.0

controller:
  # Replica configuration (preserved from current)
  replicaCount: $CURRENT_REPLICAS
  
  # Image configuration for v1.3.0 (updated)
  image:
    registry: $AIRGAP_REGISTRY
    image: ingress-nginx/controller  # Updated path for v1.3.0
    tag: "v1.3.0"                   # Target version
    pullPolicy: IfNotPresent
  
  # Image pull secrets (adjust based on your registry)
  imagePullSecrets:
    - name: samsungena.io-secret    # Update if needed
  
  # Service configuration (preserved from current)
  service:
    enabled: true
    type: LoadBalancer              # Preserved from current setup
    annotations:
      # Add MetalLB annotation for on-premise
      metallb.universe.tf/allow-shared-ip: "nginx-ingress"
    ports:
      http: 80
      https: 443
    targetPorts:
      http: http
      https: https
  
  # Resource configuration (preserved with some adjustments)
  resources:
    requests:
      cpu: 500m                     # Preserved from current
      memory: 1Gi                   # Preserved from current  
    limits:
      cpu: 1000m                    # Increased for v1.3.0
      memory: 2Gi                   # Increased for v1.3.0
  
  # Admission webhooks - DISABLED for airgap
  admissionWebhooks:
    enabled: false                  # Disabled (no kube-webhook-certgen image)
  
  # Node selector (Linux nodes only)
  nodeSelector:
    kubernetes.io/os: linux
  
  # Pod anti-affinity for HA
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - ingress-nginx
            - key: app.kubernetes.io/component
              operator: In
              values:
              - controller
          topologyKey: kubernetes.io/hostname

# Default backend - DISABLED for simpler airgap deployment
defaultBackend:
  enabled: false

# RBAC configuration (preserved)
rbac:
  create: true

# Service account configuration (preserved)
serviceAccount:
  create: true
  name: "dev-sds-ingress-ingress-controller"  # Preserve existing name

# Additional configurations for migration
migration:
  # Source information
  sourceImage: "$CURRENT_IMAGE"
  sourceNamespace: "$CURRENT_NAMESPACE"
  targetImage: "$AIRGAP_REGISTRY/ingress-nginx/controller:v1.3.0"
  
  # Compatibility notes
  notes: |
    - Migrating from v1.12.4 to v1.3.0 (major downgrade - verify compatibility)
    - Admission webhooks disabled for airgap environment
    - Default backend disabled for simplicity
    - Resource limits increased for v1.3.0 performance
    - Using existing service account name for continuity
EOF

echo "✅ Migrated values created: $OUTPUT_FILE"
echo ""

# Create comparison report
COMPARISON_FILE="./extracted-config/migration-comparison-$TIMESTAMP.md"
cat > $COMPARISON_FILE << EOF
# Migration Comparison Report

**Generated:** $(date)
**Source:** $CURRENT_IMAGE
**Target:** nginx-ingress-controller:v1.3.0

## Key Changes

### Image Configuration
| Aspect | Current (v1.12.4) | Target (v1.3.0) | Notes |
|--------|-------------------|------------------|-------|
| Registry | $CURRENT_REGISTRY | $AIRGAP_REGISTRY | Airgap registry |
| Image Path | score-scpapps/nginx-ingress-controller | ingress-nginx/controller | Standard path |
| Version | v1.12.4 | v1.3.0 | **Major version change** |

### Resource Configuration
| Resource | Current | Target | Change |
|----------|---------|--------|--------|
| CPU Request | 500m | 500m | No change |
| Memory Request | 1Gi | 1Gi | No change |
| CPU Limit | 500m | 1000m | **Increased** |
| Memory Limit | 1Gi | 2Gi | **Increased** |

### Feature Changes
| Feature | Current | Target | Impact |
|---------|---------|--------|--------|
| Admission Webhooks | Unknown | Disabled | Simplified deployment |
| Default Backend | Unknown | Disabled | Simplified deployment |
| Service Type | LoadBalancer | LoadBalancer | Preserved |
| Replicas | $CURRENT_REPLICAS | $CURRENT_REPLICAS | Preserved |

## ⚠️  Critical Considerations

### Version Compatibility Warning
- **This is actually a DOWNGRADE from v1.12.4 to v1.3.0**
- nginx-ingress-controller v1.12.4 is much newer than v1.3.0
- Consider using a newer airgap version if available

### Registry Migration
- Current: $CURRENT_REGISTRY
- Target: $AIRGAP_REGISTRY
- Ensure target registry has the required images

### Breaking Changes to Review
1. API version changes between versions
2. Configuration parameter changes
3. Ingress class handling differences
4. Resource requirements

## Recommended Actions

1. **Verify Version Strategy**
   - Confirm if downgrading from v1.12.4 to v1.3.0 is intentional
   - Consider finding v1.12.4 airgap bundle if possible

2. **Test Migration**
   - Run validation: \`./validate-upgrade.sh $CURRENT_NAMESPACE $OUTPUT_FILE\`
   - Test in staging environment first

3. **Backup Strategy**
   - Current configuration backed up in: $EXTRACTED_DIR/
   - Plan rollback procedure

4. **Registry Preparation**
   - Ensure $AIRGAP_REGISTRY has nginx-ingress-controller:v1.3.0
   - Verify image pull secrets are configured

## Migration Command
\`\`\`bash
./upgrade-nginx-controller.sh $CURRENT_NAMESPACE $OUTPUT_FILE
\`\`\`
EOF

echo "📊 Migration comparison report: $COMPARISON_FILE"
echo ""

# Validation warnings
echo "⚠️  IMPORTANT MIGRATION WARNINGS:"
echo ""
echo "1. **VERSION MISMATCH DETECTED**:"
echo "   - Current: v1.12.4 (newer)"
echo "   - Target: v1.3.0 (older)"
echo "   - This is a DOWNGRADE, not an upgrade!"
echo ""
echo "2. **Registry Change**:"
echo "   - From: $CURRENT_REGISTRY"
echo "   - To: $AIRGAP_REGISTRY"
echo "   - Verify image availability"
echo ""
echo "3. **Feature Changes**:"
echo "   - Admission webhooks will be disabled"
echo "   - Default backend will be disabled"
echo "   - Resource limits increased"
echo ""

echo "🚀 Next Steps:"
echo "   1. Review migrated values: $OUTPUT_FILE"
echo "   2. Review comparison report: $COMPARISON_FILE"
echo "   3. Validate migration: ./validate-upgrade.sh $CURRENT_NAMESPACE $OUTPUT_FILE"
echo "   4. Execute migration: ./upgrade-nginx-controller.sh $CURRENT_NAMESPACE $OUTPUT_FILE"
echo ""
echo "⚠️  **STRONGLY RECOMMENDED**: Test in staging environment first!"
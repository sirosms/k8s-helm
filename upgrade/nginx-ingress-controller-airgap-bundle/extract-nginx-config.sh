#!/bin/bash

# Extract Nginx Ingress Controller Configuration Script
# Usage: ./extract-nginx-config.sh [namespace]

set -e

# Configuration
NAMESPACE=${1:-"ingress-nginx"}
OUTPUT_DIR="./extracted-config"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "🔍 Extracting Nginx Ingress Controller configuration..."
echo "📦 Namespace: ${NAMESPACE}"
echo "📁 Output directory: ${OUTPUT_DIR}"
echo ""

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Check if nginx-ingress exists in the namespace
if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    echo "❌ Namespace ${NAMESPACE} does not exist"
    exit 1
fi

# Find nginx-ingress controller deployment
DEPLOYMENT=$(kubectl get deployment -n ${NAMESPACE} -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="ingress-nginx")].metadata.name}' 2>/dev/null || echo "")
if [ -z "$DEPLOYMENT" ]; then
    DEPLOYMENT=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$DEPLOYMENT" ]; then
    echo "❌ Nginx Ingress Controller deployment not found in namespace ${NAMESPACE}"
    echo "Available deployments:"
    kubectl get deployment -n ${NAMESPACE}
    exit 1
fi

echo "✅ Found deployment: ${DEPLOYMENT}"
echo ""

# 1. Extract Deployment configuration
echo "📋 Extracting Deployment configuration..."
kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o yaml > ${OUTPUT_DIR}/deployment-${TIMESTAMP}.yaml

# Get current image version
CURRENT_IMAGE=$(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "🏷️  Current image: ${CURRENT_IMAGE}"

# 2. Extract ConfigMap configuration
echo "📋 Extracting ConfigMap configuration..."
kubectl get configmap -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o yaml > ${OUTPUT_DIR}/configmap-${TIMESTAMP}.yaml 2>/dev/null || echo "⚠️  No ConfigMap found"

# 3. Extract Service configuration
echo "📋 Extracting Service configuration..."
kubectl get service -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o yaml > ${OUTPUT_DIR}/service-${TIMESTAMP}.yaml

# 4. Extract ServiceAccount and RBAC
echo "📋 Extracting RBAC configuration..."
kubectl get serviceaccount -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o yaml > ${OUTPUT_DIR}/serviceaccount-${TIMESTAMP}.yaml 2>/dev/null || echo "⚠️  No ServiceAccount found"
kubectl get clusterrole -l app.kubernetes.io/name=ingress-nginx -o yaml > ${OUTPUT_DIR}/clusterrole-${TIMESTAMP}.yaml 2>/dev/null || echo "⚠️  No ClusterRole found"
kubectl get clusterrolebinding -l app.kubernetes.io/name=ingress-nginx -o yaml > ${OUTPUT_DIR}/clusterrolebinding-${TIMESTAMP}.yaml 2>/dev/null || echo "⚠️  No ClusterRoleBinding found"

# 5. Extract current Helm values (if installed via Helm)
echo "📋 Checking if installed via Helm..."
HELM_RELEASE=$(helm list -n ${NAMESPACE} -q 2>/dev/null | grep -E "(ingress-nginx|nginx-ingress)" | head -1 || echo "")
if [ ! -z "$HELM_RELEASE" ]; then
    echo "✅ Found Helm release: ${HELM_RELEASE}"
    helm get values ${HELM_RELEASE} -n ${NAMESPACE} > ${OUTPUT_DIR}/helm-values-${TIMESTAMP}.yaml
    helm get manifest ${HELM_RELEASE} -n ${NAMESPACE} > ${OUTPUT_DIR}/helm-manifest-${TIMESTAMP}.yaml
else
    echo "ℹ️  Not installed via Helm or release not found"
fi

# 6. Generate values.yaml from extracted configuration
echo "📋 Generating values.yaml from extracted configuration..."
cat > ${OUTPUT_DIR}/generated-values-${TIMESTAMP}.yaml << EOF
# Generated Nginx Ingress Controller Values
# Extracted on: $(date)
# From namespace: ${NAMESPACE}
# Current image: ${CURRENT_IMAGE}

controller:
  # Replica count from current deployment
  replicaCount: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
  
  # Current image configuration
  image:
    registry: $(echo ${CURRENT_IMAGE} | cut -d'/' -f1)
    image: $(echo ${CURRENT_IMAGE} | cut -d'/' -f2- | cut -d':' -f1)
    tag: "$(echo ${CURRENT_IMAGE} | cut -d':' -f2)"
    pullPolicy: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}')
  
  # Service configuration
  service:
    enabled: true
    type: $(kubectl get service -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "LoadBalancer")
    
  # Resource configuration
  resources:
    requests:
      cpu: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "100m")
      memory: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "90Mi")
    limits:
      cpu: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "500m")
      memory: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "500Mi")

# RBAC configuration
rbac:
  create: true

# Service account
serviceAccount:
  create: true
  name: $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || echo "ingress-nginx")
EOF

# 7. Create summary report
echo "📋 Creating summary report..."
cat > ${OUTPUT_DIR}/extraction-summary-${TIMESTAMP}.md << EOF
# Nginx Ingress Controller Configuration Extraction Summary

**Extraction Date:** $(date)
**Namespace:** ${NAMESPACE}
**Deployment:** ${DEPLOYMENT}

## Current Configuration
- **Image:** ${CURRENT_IMAGE}
- **Replicas:** $(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
- **Service Type:** $(kubectl get service -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "Unknown")
- **Helm Managed:** $([ ! -z "$HELM_RELEASE" ] && echo "Yes (${HELM_RELEASE})" || echo "No")

## Extracted Files
- \`deployment-${TIMESTAMP}.yaml\` - Kubernetes Deployment
- \`configmap-${TIMESTAMP}.yaml\` - ConfigMaps
- \`service-${TIMESTAMP}.yaml\` - Services
- \`serviceaccount-${TIMESTAMP}.yaml\` - ServiceAccount
- \`clusterrole-${TIMESTAMP}.yaml\` - ClusterRole
- \`clusterrolebinding-${TIMESTAMP}.yaml\` - ClusterRoleBinding
- \`generated-values-${TIMESTAMP}.yaml\` - Generated Helm values
$([ ! -z "$HELM_RELEASE" ] && echo "- \`helm-values-${TIMESTAMP}.yaml\` - Current Helm values" || echo "")
$([ ! -z "$HELM_RELEASE" ] && echo "- \`helm-manifest-${TIMESTAMP}.yaml\` - Current Helm manifest" || echo "")

## Next Steps
1. Review generated-values-${TIMESTAMP}.yaml
2. Compare with new v1.3.0 values.yaml
3. Run validate-upgrade.sh to check compatibility
4. Execute upgrade-nginx-controller.sh for upgrade

## Backup Created
All current configurations have been backed up to: \`${OUTPUT_DIR}/\`
EOF

echo ""
echo "✅ Configuration extraction completed!"
echo ""
echo "📁 Extracted files location: ${OUTPUT_DIR}/"
echo "📋 Summary report: ${OUTPUT_DIR}/extraction-summary-${TIMESTAMP}.md"
echo "⚙️  Generated values: ${OUTPUT_DIR}/generated-values-${TIMESTAMP}.yaml"
echo ""
echo "🚀 Next steps:"
echo "   1. Review generated values file"
echo "   2. Run: ./validate-upgrade.sh"
echo "   3. Run: ./upgrade-nginx-controller.sh"
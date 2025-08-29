#!/bin/bash

# Upgrade Nginx Ingress Controller Script
# Usage: ./upgrade-nginx-controller.sh [namespace] [values-file]

set -e

# Configuration
NAMESPACE=${1:-"ingress-nginx"}
VALUES_FILE=${2:-"values/nginx-ingress.yaml"}
RELEASE_NAME="ingress-nginx"
BACKUP_DIR="./backup-$(date +%Y%m%d_%H%M%S)"
CHART_PATH="./charts/ingress-nginx-4.1.4.tgz"

echo "🚀 Starting Nginx Ingress Controller upgrade to v1.3.0..."
echo "📦 Namespace: ${NAMESPACE}"
echo "📋 Values file: ${VALUES_FILE}"
echo "💾 Backup directory: ${BACKUP_DIR}"
echo ""

# Pre-flight checks
echo "🔍 Running pre-flight checks..."

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if helm is available
if ! command -v helm >/dev/null 2>&1; then
    echo "❌ helm is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    echo "❌ Namespace ${NAMESPACE} does not exist"
    exit 1
fi

# Check if values file exists
if [ ! -f "${VALUES_FILE}" ]; then
    echo "❌ Values file ${VALUES_FILE} not found"
    echo "💡 Run ./extract-nginx-config.sh first to generate values"
    exit 1
fi

# Check if chart exists
if [ ! -f "${CHART_PATH}" ]; then
    echo "❌ Helm chart ${CHART_PATH} not found"
    exit 1
fi

echo "✅ Pre-flight checks passed"
echo ""

# Create backup directory
echo "💾 Creating backup..."
mkdir -p ${BACKUP_DIR}

# Backup current configuration
echo "📋 Backing up current configuration..."
kubectl get all -n ${NAMESPACE} -o yaml > ${BACKUP_DIR}/current-all-resources.yaml
kubectl get configmap -n ${NAMESPACE} -o yaml > ${BACKUP_DIR}/current-configmaps.yaml
kubectl get secrets -n ${NAMESPACE} -o yaml > ${BACKUP_DIR}/current-secrets.yaml
kubectl get ingress -A -o yaml > ${BACKUP_DIR}/current-ingresses.yaml 2>/dev/null || echo "⚠️  No ingresses found"

# Backup Helm release if exists
EXISTING_RELEASE=$(helm list -n ${NAMESPACE} -q 2>/dev/null | grep -E "(ingress-nginx|nginx-ingress)" | head -1 || echo "")
if [ ! -z "$EXISTING_RELEASE" ]; then
    echo "📋 Backing up Helm release: ${EXISTING_RELEASE}"
    helm get values ${EXISTING_RELEASE} -n ${NAMESPACE} > ${BACKUP_DIR}/helm-values-backup.yaml
    helm get manifest ${EXISTING_RELEASE} -n ${NAMESPACE} > ${BACKUP_DIR}/helm-manifest-backup.yaml
    RELEASE_NAME=${EXISTING_RELEASE}
else
    echo "ℹ️  No existing Helm release found, will create new one"
fi

echo "✅ Backup completed: ${BACKUP_DIR}"
echo ""

# Check current pods status
echo "📋 Current pod status:"
kubectl get pods -n ${NAMESPACE}
echo ""

# Get current service external IP/LoadBalancer info
echo "📋 Current service status:"
kubectl get svc -n ${NAMESPACE}
echo ""

# Confirm upgrade
echo "⚠️  IMPORTANT: This will upgrade nginx-ingress-controller to v1.3.0"
echo "📋 Review the following:"
echo "   - Backup created: ${BACKUP_DIR}/"
echo "   - Chart: ${CHART_PATH}"
echo "   - Values: ${VALUES_FILE}"
echo "   - Release: ${RELEASE_NAME}"
echo "   - Namespace: ${NAMESPACE}"
echo ""
read -p "🤔 Do you want to continue with the upgrade? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Upgrade cancelled by user"
    exit 1
fi
echo ""

# Start upgrade process
echo "🔄 Starting upgrade process..."

# If existing Helm release, upgrade it
if [ ! -z "$EXISTING_RELEASE" ]; then
    echo "🔄 Upgrading existing Helm release: ${RELEASE_NAME}"
    helm upgrade ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --values ${VALUES_FILE} \
        --wait \
        --timeout=10m \
        --history-max=5
else
    echo "🔄 Installing new Helm release: ${RELEASE_NAME}"
    helm install ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --values ${VALUES_FILE} \
        --wait \
        --timeout=10m
fi

echo ""
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx

echo ""
echo "📋 Checking upgrade status..."

# Verify deployment
echo "🔍 Verifying new deployment:"
NEW_IMAGE=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].spec.template.spec.containers[0].image}')
READY_REPLICAS=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.readyReplicas}')
DESIRED_REPLICAS=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].spec.replicas}')

echo "   🏷️  New image: ${NEW_IMAGE}"
echo "   📊 Ready replicas: ${READY_REPLICAS}/${DESIRED_REPLICAS}"

# Check pod status
echo ""
echo "📋 Pod status after upgrade:"
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx

# Check service status
echo ""
echo "📋 Service status after upgrade:"
kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx

# Test basic functionality
echo ""
echo "🧪 Running basic functionality tests..."

# Check if controller is responding
CONTROLLER_POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ ! -z "$CONTROLLER_POD" ]; then
    echo "   ✅ Controller pod found: ${CONTROLLER_POD}"
    
    # Check controller logs for errors
    echo "   🔍 Checking controller logs for errors..."
    ERROR_COUNT=$(kubectl logs ${CONTROLLER_POD} -n ${NAMESPACE} --tail=50 | grep -i error | wc -l || echo "0")
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "   ⚠️  Found ${ERROR_COUNT} errors in controller logs"
        echo "   💡 Check logs with: kubectl logs ${CONTROLLER_POD} -n ${NAMESPACE}"
    else
        echo "   ✅ No errors found in controller logs"
    fi
else
    echo "   ❌ Controller pod not found"
fi

# Create upgrade summary
echo ""
echo "📋 Creating upgrade summary..."
cat > ${BACKUP_DIR}/upgrade-summary.md << EOF
# Nginx Ingress Controller Upgrade Summary

**Upgrade Date:** $(date)
**Namespace:** ${NAMESPACE}
**Release Name:** ${RELEASE_NAME}

## Upgrade Details
- **From:** Previous version (backed up)
- **To:** v1.3.0 (${NEW_IMAGE})
- **Chart:** ${CHART_PATH}
- **Values:** ${VALUES_FILE}

## Post-Upgrade Status
- **Ready Replicas:** ${READY_REPLICAS}/${DESIRED_REPLICAS}
- **Controller Pod:** ${CONTROLLER_POD}
- **Log Errors:** ${ERROR_COUNT}

## Backup Location
All previous configurations backed up to: \`${BACKUP_DIR}/\`

## Rollback Command (if needed)
\`\`\`bash
./rollback-nginx-controller.sh ${NAMESPACE} ${BACKUP_DIR}
\`\`\`

## Verification Steps
1. Check ingress resources: \`kubectl get ingress -A\`
2. Test application access through ingress
3. Monitor controller logs: \`kubectl logs -f ${CONTROLLER_POD} -n ${NAMESPACE}\`
EOF

echo ""
echo "✅ Upgrade completed successfully!"
echo ""
echo "📋 Summary:"
echo "   🎯 Target version: v1.3.0"
echo "   🏷️  Deployed image: ${NEW_IMAGE}"
echo "   📊 Ready replicas: ${READY_REPLICAS}/${DESIRED_REPLICAS}"
echo "   💾 Backup location: ${BACKUP_DIR}/"
echo ""
echo "🔍 Next steps:"
echo "   1. Test your applications through ingress"
echo "   2. Monitor controller logs: kubectl logs -f ${CONTROLLER_POD} -n ${NAMESPACE}"
echo "   3. Check ingress resources: kubectl get ingress -A"
echo "   4. If issues occur, run: ./rollback-nginx-controller.sh ${NAMESPACE} ${BACKUP_DIR}"
echo ""
echo "📋 Upgrade summary: ${BACKUP_DIR}/upgrade-summary.md"
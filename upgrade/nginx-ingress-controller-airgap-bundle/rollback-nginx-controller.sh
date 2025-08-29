#!/bin/bash

# Rollback Nginx Ingress Controller Script
# Usage: ./rollback-nginx-controller.sh [namespace] [backup-directory]

set -e

# Configuration
NAMESPACE=${1:-"ingress-nginx"}
BACKUP_DIR=${2}

echo "🔄 Starting Nginx Ingress Controller rollback..."
echo "📦 Namespace: ${NAMESPACE}"
echo "💾 Backup directory: ${BACKUP_DIR}"
echo ""

# Validation
if [ -z "$BACKUP_DIR" ]; then
    echo "❌ Backup directory is required"
    echo "Usage: $0 [namespace] <backup-directory>"
    echo ""
    echo "Available backup directories:"
    ls -la | grep "^d" | grep "backup-" || echo "No backup directories found"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory does not exist: $BACKUP_DIR"
    echo ""
    echo "Available backup directories:"
    ls -la | grep "^d" | grep "backup-" || echo "No backup directories found"
    exit 1
fi

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    echo "❌ helm is not installed or not in PATH"
    exit 1
fi

if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    echo "❌ Namespace ${NAMESPACE} does not exist"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Show current status
echo "📋 Current status before rollback:"
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx || echo "No nginx-ingress pods found"
kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx || echo "No nginx-ingress services found"
echo ""

# Check available backup files
echo "📁 Available backup files in ${BACKUP_DIR}:"
ls -la ${BACKUP_DIR}/ | grep -E "\.(yaml|yml)$" || echo "No YAML backup files found"
echo ""

# Determine rollback method
HELM_VALUES_BACKUP="${BACKUP_DIR}/helm-values-backup.yaml"
HELM_MANIFEST_BACKUP="${BACKUP_DIR}/helm-manifest-backup.yaml"
K8S_BACKUP="${BACKUP_DIR}/current-all-resources.yaml"

# Find current Helm release
CURRENT_RELEASE=$(helm list -n ${NAMESPACE} -q 2>/dev/null | grep -E "(ingress-nginx|nginx-ingress)" | head -1 || echo "")

if [ -f "$HELM_VALUES_BACKUP" ] && [ ! -z "$CURRENT_RELEASE" ]; then
    ROLLBACK_METHOD="helm"
    echo "🎯 Rollback method: Helm release rollback"
    echo "📋 Release: ${CURRENT_RELEASE}"
elif [ -f "$K8S_BACKUP" ]; then
    ROLLBACK_METHOD="kubectl"
    echo "🎯 Rollback method: Kubernetes resource restore"
else
    echo "❌ No suitable rollback method found"
    echo "Required files missing:"
    echo "   - Helm values backup: ${HELM_VALUES_BACKUP}"
    echo "   - Kubernetes backup: ${K8S_BACKUP}"
    exit 1
fi

echo ""

# Confirm rollback
echo "⚠️  WARNING: This will rollback nginx-ingress-controller to previous version"
echo "📋 Rollback details:"
echo "   - Method: ${ROLLBACK_METHOD}"
echo "   - Namespace: ${NAMESPACE}"
echo "   - Backup: ${BACKUP_DIR}"
if [ "$ROLLBACK_METHOD" = "helm" ]; then
    echo "   - Release: ${CURRENT_RELEASE}"
fi
echo ""
echo "💥 This action may cause service disruption!"
echo ""
read -p "🤔 Are you sure you want to proceed with rollback? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rollback cancelled by user"
    exit 1
fi
echo ""

# Create pre-rollback snapshot
PRE_ROLLBACK_SNAPSHOT="./pre-rollback-snapshot-$(date +%Y%m%d_%H%M%S)"
echo "📸 Creating pre-rollback snapshot: ${PRE_ROLLBACK_SNAPSHOT}"
mkdir -p ${PRE_ROLLBACK_SNAPSHOT}
kubectl get all -n ${NAMESPACE} -o yaml > ${PRE_ROLLBACK_SNAPSHOT}/pre-rollback-resources.yaml
kubectl get configmap -n ${NAMESPACE} -o yaml > ${PRE_ROLLBACK_SNAPSHOT}/pre-rollback-configmaps.yaml

if [ "$ROLLBACK_METHOD" = "helm" ] && [ ! -z "$CURRENT_RELEASE" ]; then
    helm get values ${CURRENT_RELEASE} -n ${NAMESPACE} > ${PRE_ROLLBACK_SNAPSHOT}/pre-rollback-helm-values.yaml
    helm get manifest ${CURRENT_RELEASE} -n ${NAMESPACE} > ${PRE_ROLLBACK_SNAPSHOT}/pre-rollback-helm-manifest.yaml
fi
echo "✅ Snapshot created"
echo ""

# Execute rollback based on method
if [ "$ROLLBACK_METHOD" = "helm" ]; then
    echo "🔄 Performing Helm rollback..."
    
    # Check Helm history
    echo "📋 Helm release history:"
    helm history ${CURRENT_RELEASE} -n ${NAMESPACE} || echo "Could not retrieve history"
    echo ""
    
    # Try to rollback to previous revision
    echo "🔄 Rolling back to previous revision..."
    if helm rollback ${CURRENT_RELEASE} 0 -n ${NAMESPACE} --wait --timeout=10m; then
        echo "✅ Helm rollback successful"
    else
        echo "❌ Helm rollback failed, trying alternative method..."
        
        # Alternative: reinstall with backup values
        echo "🔄 Attempting reinstall with backup values..."
        
        # Find the original chart (may need to be provided)
        echo "⚠️  Note: You may need to provide the original chart for reinstallation"
        echo "Attempting to reinstall with backup values..."
        
        # Uninstall current release
        helm uninstall ${CURRENT_RELEASE} -n ${NAMESPACE} || echo "Failed to uninstall, continuing..."
        
        # Wait for cleanup
        echo "⏳ Waiting for cleanup..."
        sleep 30
        
        echo "❌ Manual intervention required:"
        echo "   1. Obtain the original Helm chart"
        echo "   2. Run: helm install ${CURRENT_RELEASE} <original-chart> --namespace ${NAMESPACE} --values ${HELM_VALUES_BACKUP}"
        echo "   3. Or restore manually using kubectl apply -f ${K8S_BACKUP}"
        exit 1
    fi

elif [ "$ROLLBACK_METHOD" = "kubectl" ]; then
    echo "🔄 Performing Kubernetes resource rollback..."
    
    # Delete current resources first (with grace period)
    echo "🗑️  Removing current nginx-ingress resources..."
    kubectl delete deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx --grace-period=60 || echo "No deployment to delete"
    kubectl delete service -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx --grace-period=30 || echo "No service to delete"
    kubectl delete configmap -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx --grace-period=30 || echo "No configmap to delete"
    
    # Wait for cleanup
    echo "⏳ Waiting for cleanup..."
    sleep 30
    
    # Restore from backup
    echo "🔄 Restoring from backup..."
    if kubectl apply -f ${K8S_BACKUP}; then
        echo "✅ Kubernetes resource rollback successful"
    else
        echo "❌ Kubernetes resource rollback failed"
        echo "💡 Manual restore may be required"
        exit 1
    fi
fi

echo ""
echo "⏳ Waiting for rollback to complete..."
sleep 10

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
if kubectl wait --for=condition=available --timeout=300s deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx 2>/dev/null; then
    echo "✅ Deployment is ready"
else
    echo "⚠️  Deployment may not be fully ready yet"
fi

echo ""
echo "📋 Post-rollback status:"
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx || echo "No pods found"
kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx || echo "No services found"

# Verify rollback
echo ""
echo "🔍 Verifying rollback..."
ROLLBACK_IMAGE=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null || echo "not found")
READY_REPLICAS=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED_REPLICAS=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")

echo "   🏷️  Image after rollback: ${ROLLBACK_IMAGE}"
echo "   📊 Ready replicas: ${READY_REPLICAS}/${DESIRED_REPLICAS}"

# Test basic functionality
CONTROLLER_POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ ! -z "$CONTROLLER_POD" ]; then
    echo "   ✅ Controller pod: ${CONTROLLER_POD}"
    
    # Check for errors in logs
    ERROR_COUNT=$(kubectl logs ${CONTROLLER_POD} -n ${NAMESPACE} --tail=50 | grep -i error | wc -l || echo "0")
    if [ "$ERROR_COUNT" -gt "0" ]; then
        echo "   ⚠️  Found ${ERROR_COUNT} errors in controller logs"
    else
        echo "   ✅ No errors in controller logs"
    fi
else
    echo "   ❌ Controller pod not found"
fi

# Create rollback summary
echo ""
echo "📋 Creating rollback summary..."
cat > ${PRE_ROLLBACK_SNAPSHOT}/rollback-summary.md << EOF
# Nginx Ingress Controller Rollback Summary

**Rollback Date:** $(date)
**Namespace:** ${NAMESPACE}
**Method:** ${ROLLBACK_METHOD}
**Backup Source:** ${BACKUP_DIR}

## Rollback Details
- **Pre-rollback snapshot:** ${PRE_ROLLBACK_SNAPSHOT}
- **Restored image:** ${ROLLBACK_IMAGE}
- **Ready replicas:** ${READY_REPLICAS}/${DESIRED_REPLICAS}
- **Controller pod:** ${CONTROLLER_POD}

## Files Used
- **Backup directory:** ${BACKUP_DIR}
$([ "$ROLLBACK_METHOD" = "helm" ] && echo "- **Helm values:** ${HELM_VALUES_BACKUP}" || echo "")
$([ "$ROLLBACK_METHOD" = "kubectl" ] && echo "- **K8s backup:** ${K8S_BACKUP}" || echo "")

## Post-Rollback Actions
1. Verify application access through ingress
2. Monitor controller logs: \`kubectl logs -f ${CONTROLLER_POD} -n ${NAMESPACE}\`
3. Check ingress resources: \`kubectl get ingress -A\`
4. Test functionality thoroughly

## If Issues Persist
- Check logs: \`kubectl logs ${CONTROLLER_POD} -n ${NAMESPACE}\`
- Check events: \`kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'\`
- Consider manual restoration from backup files
EOF

echo ""
if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" -gt "0" ]; then
    echo "✅ Rollback completed successfully!"
else
    echo "⚠️  Rollback completed with warnings"
    echo "   - Some replicas may not be ready yet"
    echo "   - Monitor the deployment status"
fi

echo ""
echo "📋 Summary:"
echo "   🔄 Rollback method: ${ROLLBACK_METHOD}"
echo "   🏷️  Restored image: ${ROLLBACK_IMAGE}"
echo "   📊 Ready replicas: ${READY_REPLICAS}/${DESIRED_REPLICAS}"
echo "   📸 Pre-rollback snapshot: ${PRE_ROLLBACK_SNAPSHOT}"
echo ""
echo "🔍 Next steps:"
echo "   1. Test your applications through ingress"
echo "   2. Monitor logs: kubectl logs -f ${CONTROLLER_POD} -n ${NAMESPACE}"
echo "   3. Verify ingress functionality"
echo ""
echo "📋 Rollback summary: ${PRE_ROLLBACK_SNAPSHOT}/rollback-summary.md"
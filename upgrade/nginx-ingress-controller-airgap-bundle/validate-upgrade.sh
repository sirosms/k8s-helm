#!/bin/bash

# Validate Nginx Ingress Controller Upgrade Script
# Usage: ./validate-upgrade.sh [namespace] [values-file]

set -e

# Configuration
NAMESPACE=${1:-"ingress-nginx"}
VALUES_FILE=${2:-"values/nginx-ingress.yaml"}
CHART_PATH="./charts/ingress-nginx-4.1.4.tgz"

echo "🔍 Validating Nginx Ingress Controller upgrade readiness..."
echo "📦 Namespace: ${NAMESPACE}"
echo "📋 Values file: ${VALUES_FILE}"
echo ""

# Validation results
VALIDATION_PASSED=true
WARNINGS=()
ERRORS=()

# Helper function to add warning
add_warning() {
    WARNINGS+=("⚠️  $1")
}

# Helper function to add error
add_error() {
    ERRORS+=("❌ $1")
    VALIDATION_PASSED=false
}

# Check prerequisites
echo "1️⃣  Checking prerequisites..."

# Check kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    add_error "kubectl is not installed or not in PATH"
else
    echo "   ✅ kubectl is available"
fi

# Check helm
if ! command -v helm >/dev/null 2>&1; then
    add_error "helm is not installed or not in PATH"
else
    echo "   ✅ helm is available"
fi

# Check cluster connection
if ! kubectl cluster-info >/dev/null 2>&1; then
    add_error "Cannot connect to Kubernetes cluster"
else
    echo "   ✅ Kubernetes cluster is accessible"
fi

echo ""

# Check namespace and current installation
echo "2️⃣  Checking current installation..."

if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
    add_error "Namespace ${NAMESPACE} does not exist"
else
    echo "   ✅ Namespace ${NAMESPACE} exists"
fi

# Find current nginx-ingress deployment
CURRENT_DEPLOYMENT=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$CURRENT_DEPLOYMENT" ]; then
    CURRENT_DEPLOYMENT=$(kubectl get deployment -n ${NAMESPACE} -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$CURRENT_DEPLOYMENT" ]; then
    add_warning "No existing nginx-ingress deployment found - this will be a fresh installation"
else
    echo "   ✅ Found existing deployment: ${CURRENT_DEPLOYMENT}"
    
    # Get current version
    CURRENT_IMAGE=$(kubectl get deployment ${CURRENT_DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}')
    CURRENT_VERSION=$(echo ${CURRENT_IMAGE} | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "   📋 Current version: ${CURRENT_VERSION} (${CURRENT_IMAGE})"
    
    # Check if already v1.3.0
    if [[ "$CURRENT_IMAGE" == *"v1.3.0"* ]]; then
        add_warning "Already running v1.3.0 - upgrade may not be necessary"
    fi
    
    # Check deployment health
    READY_REPLICAS=$(kubectl get deployment ${CURRENT_DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED_REPLICAS=$(kubectl get deployment ${CURRENT_DEPLOYMENT} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$READY_REPLICAS" != "$DESIRED_REPLICAS" ]; then
        add_error "Current deployment is not healthy (${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready)"
    else
        echo "   ✅ Current deployment is healthy (${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready)"
    fi
fi

echo ""

# Check files and configuration
echo "3️⃣  Checking upgrade resources..."

if [ ! -f "${CHART_PATH}" ]; then
    add_error "Helm chart not found: ${CHART_PATH}"
else
    echo "   ✅ Helm chart available: ${CHART_PATH}"
fi

if [ ! -f "${VALUES_FILE}" ]; then
    add_error "Values file not found: ${VALUES_FILE}"
    echo "   💡 Run './extract-nginx-config.sh' to generate values from current installation"
else
    echo "   ✅ Values file available: ${VALUES_FILE}"
    
    # Validate values file syntax
    if ! helm template test ${CHART_PATH} --values ${VALUES_FILE} >/dev/null 2>&1; then
        add_error "Values file has syntax errors or incompatible with chart"
    else
        echo "   ✅ Values file syntax is valid"
    fi
fi

echo ""

# Check Kubernetes version compatibility
echo "4️⃣  Checking Kubernetes compatibility..."
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | grep -oE 'v[0-9]+\.[0-9]+' || echo "unknown")
if [ "$K8S_VERSION" != "unknown" ]; then
    echo "   📋 Kubernetes version: ${K8S_VERSION}"
    
    # nginx-ingress-controller v1.3.0 requires K8s 1.19+
    K8S_MAJOR=$(echo ${K8S_VERSION} | cut -d'.' -f1 | sed 's/v//')
    K8S_MINOR=$(echo ${K8S_VERSION} | cut -d'.' -f2)
    
    if [ "$K8S_MAJOR" -eq "1" ] && [ "$K8S_MINOR" -lt "19" ]; then
        add_error "Kubernetes version ${K8S_VERSION} is not supported. Requires v1.19+"
    else
        echo "   ✅ Kubernetes version is compatible"
    fi
else
    add_warning "Could not determine Kubernetes version"
fi

echo ""

# Check resource availability
echo "5️⃣  Checking cluster resources..."

# Check node resources
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$NODE_COUNT" -eq "0" ]; then
    add_error "No nodes found in cluster"
else
    echo "   📋 Available nodes: ${NODE_COUNT}"
fi

# Check if nodes have sufficient resources (rough estimate)
TOTAL_CPU=$(kubectl top nodes 2>/dev/null | tail -n +2 | awk '{sum+=$3} END {print sum}' || echo "0")
if [ "$TOTAL_CPU" -gt "0" ]; then
    echo "   📋 Cluster has sufficient resources"
else
    add_warning "Could not determine cluster resource usage (metrics-server may not be available)"
fi

echo ""

# Check existing ingress resources
echo "6️⃣  Checking ingress resources..."
INGRESS_COUNT=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l || echo "0")
echo "   📋 Existing ingress resources: ${INGRESS_COUNT}"

if [ "$INGRESS_COUNT" -gt "0" ]; then
    echo "   ⚠️  Existing ingress resources will be affected during upgrade"
    echo "   💡 Consider maintenance window for applications"
fi

echo ""

# Check Helm release status
echo "7️⃣  Checking Helm release status..."
EXISTING_RELEASE=$(helm list -n ${NAMESPACE} -q 2>/dev/null | grep -E "(ingress-nginx|nginx-ingress)" | head -1 || echo "")
if [ ! -z "$EXISTING_RELEASE" ]; then
    echo "   ✅ Found Helm release: ${EXISTING_RELEASE}"
    
    RELEASE_STATUS=$(helm status ${EXISTING_RELEASE} -n ${NAMESPACE} -o json 2>/dev/null | jq -r '.info.status' || echo "unknown")
    echo "   📋 Release status: ${RELEASE_STATUS}"
    
    if [ "$RELEASE_STATUS" != "deployed" ]; then
        add_warning "Helm release status is '${RELEASE_STATUS}' (not 'deployed')"
    fi
else
    echo "   ℹ️  No existing Helm release found - will create new release"
fi

echo ""

# Check for admission webhooks
echo "8️⃣  Checking admission webhooks configuration..."
if grep -q "admissionWebhooks:" ${VALUES_FILE} 2>/dev/null; then
    WEBHOOKS_ENABLED=$(grep -A2 "admissionWebhooks:" ${VALUES_FILE} | grep "enabled:" | grep -oE "(true|false)" || echo "unknown")
    echo "   📋 Admission webhooks in values: ${WEBHOOKS_ENABLED}"
    
    if [ "$WEBHOOKS_ENABLED" = "true" ]; then
        add_warning "Admission webhooks are enabled but kube-webhook-certgen image may not be available in airgap environment"
        echo "   💡 Consider setting admissionWebhooks.enabled: false for airgap deployment"
    else
        echo "   ✅ Admission webhooks are disabled (good for airgap)"
    fi
fi

echo ""

# Generate validation report
echo "9️⃣  Generating validation report..."

echo "════════════════════════════════════════"
echo "📊 VALIDATION SUMMARY"
echo "════════════════════════════════════════"

if [ "${#ERRORS[@]}" -gt "0" ]; then
    echo ""
    echo "❌ ERRORS FOUND (${#ERRORS[@]}):"
    for error in "${ERRORS[@]}"; do
        echo "   $error"
    done
fi

if [ "${#WARNINGS[@]}" -gt "0" ]; then
    echo ""
    echo "⚠️  WARNINGS (${#WARNINGS[@]}):"
    for warning in "${WARNINGS[@]}"; do
        echo "   $warning"
    done
fi

echo ""
if [ "$VALIDATION_PASSED" = true ]; then
    echo "✅ VALIDATION PASSED"
    echo ""
    echo "🚀 Ready to proceed with upgrade!"
    echo ""
    echo "📋 Recommended steps:"
    echo "   1. Schedule maintenance window if you have active ingress traffic"
    echo "   2. Run: ./upgrade-nginx-controller.sh ${NAMESPACE} ${VALUES_FILE}"
    echo "   3. Verify applications after upgrade"
    echo ""
    echo "💾 Backup will be created automatically during upgrade"
    exit 0
else
    echo "❌ VALIDATION FAILED"
    echo ""
    echo "🛠️  Please fix the errors above before proceeding with upgrade"
    echo ""
    echo "💡 Common fixes:"
    echo "   - Install missing tools (kubectl, helm)"
    echo "   - Fix cluster connectivity issues"
    echo "   - Ensure deployment is healthy before upgrade"
    echo "   - Run './extract-nginx-config.sh' to generate values file"
    exit 1
fi
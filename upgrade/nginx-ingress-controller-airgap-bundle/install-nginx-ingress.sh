#!/bin/bash

# Nginx Ingress Controller Test Installation Script for Samsung SDS Environment
# Usage: ./install-nginx-ingress.sh [namespace] [release-name] [values-file]

set -e

# Configuration with Samsung SDS defaults
NAMESPACE=${1:-"nginx-ingress-test"}
RELEASE_NAME=${2:-"nginx-ingress-v130-test"}
VALUES_FILE=${3:-"values/nginx-ingress-sds-environment.yaml"}
SDS_REGISTRY="sscr.comm.scp-in.com"
CHART_PATH="./charts/ingress-nginx-4.1.4.tgz"

echo "🚀 Starting Nginx Ingress Controller v1.3.0 test installation..."
echo "📦 Namespace: ${NAMESPACE}"
echo "🏷️  Release: ${RELEASE_NAME}"
echo "📋 Values file: ${VALUES_FILE}"
echo "📍 Registry: ${SDS_REGISTRY}"
echo "⚠️  This is a TEST installation - separate from production"
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

# Check if values file exists
if [ ! -f "${VALUES_FILE}" ]; then
    echo "❌ Values file not found: ${VALUES_FILE}"
    echo "Available values files:"
    ls -la values/*.yaml 2>/dev/null || echo "No values files found"
    exit 1
fi

# Check if chart exists
if [ ! -f "${CHART_PATH}" ]; then
    echo "❌ Helm chart not found: ${CHART_PATH}"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Pre-flight checks passed"
echo ""

# Check for existing installation in the namespace
EXISTING_RELEASE=$(helm list -n ${NAMESPACE} -q 2>/dev/null | head -1 || echo "")
if [ ! -z "$EXISTING_RELEASE" ]; then
    echo "⚠️  Found existing Helm release in namespace: ${EXISTING_RELEASE}"
    echo "This will upgrade the existing installation"
    echo ""
fi

# Create namespace if it doesn't exist
echo "🏗️  Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Check for Samsung SDS registry secret
echo "🔐 Checking Samsung SDS registry access..."
if kubectl get secret samsungena.io-secret -n ${NAMESPACE} >/dev/null 2>&1; then
    echo "✅ Found existing registry secret: samsungena.io-secret"
elif kubectl get secret samsungena.io-secret -n default >/dev/null 2>&1; then
    echo "📋 Copying registry secret from default namespace..."
    kubectl get secret samsungena.io-secret -n default -o yaml | \
        sed "s/namespace: default/namespace: ${NAMESPACE}/" | \
        kubectl apply -f -
    echo "✅ Registry secret copied to ${NAMESPACE}"
else
    echo "⚠️  No Samsung SDS registry secret found"
    echo "💡 You may need to create registry secret manually:"
    echo "   kubectl create secret docker-registry samsungena.io-secret \\"
    echo "     --docker-server=sscr.comm.scp-in.com \\"
    echo "     --docker-username=<username> \\"
    echo "     --docker-password=<password> \\"
    echo "     --namespace=${NAMESPACE}"
    echo ""
    read -p "🤔 Continue without registry secret? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Installation cancelled - please create registry secret first"
        exit 1
    fi
fi
echo ""

# Show what will be installed
echo "📋 Installation summary:"
echo "   🎯 Target version: v1.3.0"
echo "   📦 Chart: ${CHART_PATH}"
echo "   📋 Values: ${VALUES_FILE}"
echo "   🏷️  Release: ${RELEASE_NAME}"
echo "   🗂️  Namespace: ${NAMESPACE}"
echo "   🏛️  Registry: ${SDS_REGISTRY}"
echo ""

# Confirm installation
read -p "🤔 Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Installation cancelled by user"
    exit 1
fi
echo ""

# Install Nginx Ingress Controller using Helm with values file
echo "📦 Installing Nginx Ingress Controller v1.3.0..."
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --wait \
  --timeout=10m

echo ""
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx || echo "⚠️  Timeout waiting for deployment"

echo ""
echo "✅ Nginx Ingress Controller v1.3.0 test installation completed!"
echo ""

# Get installation details
CONTROLLER_POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not found")
SERVICE_TYPE=$(kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "unknown")
EXTERNAL_IP=$(kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

echo "📋 Installation details:"
echo "   🎯 Version: v1.3.0"
echo "   🗂️  Namespace: ${NAMESPACE}"
echo "   🏷️  Release: ${RELEASE_NAME}"
echo "   🏗️  Controller pod: ${CONTROLLER_POD}"
echo "   🌐 Service type: ${SERVICE_TYPE}"
echo "   🌍 External IP: ${EXTERNAL_IP}"
echo ""

echo "📋 Checking deployment status..."
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx
echo ""
echo "🌐 Checking service status..."
kubectl get svc -n ${NAMESPACE} -l app.kubernetes.io/name=ingress-nginx
echo ""

# Create test ingress for validation
echo "🧪 Creating test ingress for v1.3.0 validation..."
cat > test-ingress-${NAMESPACE}.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress-v130
  namespace: ${NAMESPACE}
  annotations:
    # Use specific ingress class for v1.3.0 test controller
    kubernetes.io/ingress.class: nginx-v130-test
    nginx.ingress.kubernetes.io/rewrite-target: /
    # Add test identifier
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Nginx-Version "v1.3.0-test" always;
spec:
  ingressClassName: nginx-v130-test  # Explicit ingress class for v1.3.0
  rules:
  - host: test-v130.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service
            port:
              number: 80
---
# Create test service for the ingress
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: ${NAMESPACE}
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 8080
---
# Create simple test pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        command: ["/bin/sh"]
        args:
        - -c
        - |
          echo '<h1>Nginx Ingress Controller v1.3.0 Test</h1>
          <p>This is a test page for nginx-ingress-controller v1.3.0</p>
          <p>Namespace: ${NAMESPACE}</p>
          <p>Timestamp: $(date)</p>' > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
EOF

kubectl apply -f test-ingress-${NAMESPACE}.yaml
echo "✅ Test ingress created: test-v130.local"
echo ""

echo "🔍 Testing commands:"
echo "   📋 Check pods: kubectl get pods -n ${NAMESPACE}"
echo "   📋 Check services: kubectl get svc -n ${NAMESPACE}"
echo "   📋 Check ingress: kubectl get ingress -n ${NAMESPACE}"
echo "   📋 Controller logs: kubectl logs -f ${CONTROLLER_POD} -n ${NAMESPACE}"
echo "   🧪 Test ingress: kubectl describe ingress test-ingress-v130 -n ${NAMESPACE}"
echo ""

echo "🧪 Validation steps:"
echo "   1. Verify controller is running and ready"
echo "   2. Check service gets external IP (if LoadBalancer)"
echo "   3. Test ingress functionality with your applications"
echo "   4. Compare performance with v1.12.4 environment"
echo ""

echo "🛠️  Management commands:"
echo "   🗑️  Uninstall: helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "   🗑️  Delete namespace: kubectl delete namespace ${NAMESPACE}"
echo "   🗑️  Remove test files: rm test-ingress-${NAMESPACE}.yaml"
echo ""

echo "⚠️  TESTING NOTES:"
echo "   - This is v1.3.0 test installation (separate from production v1.12.4)"
echo "   - Test thoroughly before considering migration"
echo "   - Compare functionality and performance"
echo "   - Production is running newer v1.12.4 - this is a downgrade test"
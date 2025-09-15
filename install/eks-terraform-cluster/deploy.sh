#!/bin/bash

# EKS Cluster Deployment Script
# This script automates the deployment of EKS cluster using Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check for Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. It will be needed to manage the cluster."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "Prerequisites check completed."
}

# Generate SSH key pair
generate_ssh_key() {
    if [ ! -f "eks-key" ]; then
        print_status "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f eks-key -N "" -C "eks-cluster-key"
        chmod 600 eks-key
        chmod 644 eks-key.pub
        print_success "SSH key pair generated: eks-key, eks-key.pub"
    else
        print_status "SSH key pair already exists."
    fi
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    print_success "Terraform initialized."
}

# Validate Terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    terraform validate
    print_success "Terraform configuration is valid."
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    print_success "Terraform plan completed. Review the plan above."
    
    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user."
        exit 0
    fi
}

# Apply Terraform configuration
apply_terraform() {
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    print_success "EKS cluster deployment completed!"
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    # Get cluster name and region from Terraform output
    CLUSTER_NAME=$(terraform output -raw cluster_id)
    REGION=$(terraform output -raw region 2>/dev/null || echo "ap-northeast-2")
    
    # Update kubeconfig
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    print_success "kubectl configured for cluster: $CLUSTER_NAME"
}

# Verify cluster
verify_cluster() {
    print_status "Verifying cluster..."
    
    # Wait for cluster to be ready
    print_status "Waiting for cluster to be ready..."
    sleep 30
    
    # Check cluster status
    kubectl cluster-info
    
    # Check nodes
    print_status "Checking nodes..."
    kubectl get nodes
    
    # Check system pods
    print_status "Checking system pods..."
    kubectl get pods -n kube-system
    
    print_success "Cluster verification completed!"
}

# Main deployment function
deploy_cluster() {
    print_status "Starting EKS cluster deployment..."
    
    check_prerequisites
    generate_ssh_key
    init_terraform
    validate_terraform
    plan_terraform
    apply_terraform
    configure_kubectl
    verify_cluster
    
    print_success "EKS cluster deployment completed successfully!"
    print_status "Cluster details:"
    terraform output
}

# Cleanup function
cleanup() {
    print_warning "Cleaning up resources..."
    terraform destroy -auto-approve
    print_success "Resources cleaned up."
}

# Help function
show_help() {
    echo "EKS Cluster Deployment Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  deploy    Deploy the EKS cluster"
    echo "  destroy   Destroy the EKS cluster"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy     # Deploy the cluster"
    echo "  $0 destroy    # Destroy the cluster"
}

# Main script logic
case "${1:-deploy}" in
    deploy)
        deploy_cluster
        ;;
    destroy)
        cleanup
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
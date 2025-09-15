#!/bin/bash

# EKS Cluster Deployment using AWS CLI
# This script creates EKS cluster without Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="samsung-eks-cluster"
REGION="ap-northeast-2"
KUBERNETES_VERSION="1.31"
NODE_INSTANCE_TYPE="m5.large"
NODE_DESIRED_CAPACITY=2
NODE_MAX_CAPACITY=4
NODE_MIN_CAPACITY=1
VPC_CIDR="10.0.0.0/16"

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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. Installing..."
        brew install kubectl
    fi
    
    print_success "Prerequisites check completed."
}

# Create VPC
create_vpc() {
    print_status "Creating VPC..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block $VPC_CIDR \
        --region $REGION \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${CLUSTER_NAME}-vpc}]" \
        --query 'Vpc.VpcId' \
        --output text)
    
    print_success "VPC created: $VPC_ID"
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute \
        --vpc-id $VPC_ID \
        --enable-dns-hostnames \
        --region $REGION
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region $REGION \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${CLUSTER_NAME}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID \
        --region $REGION
    
    print_success "Internet Gateway created and attached: $IGW_ID"
    
    # Get availability zones
    AZS=($(aws ec2 describe-availability-zones \
        --region $REGION \
        --query 'AvailabilityZones[0:2].ZoneName' \
        --output text))
    
    # Create public subnets
    PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.101.0/24 \
        --availability-zone ${AZS[0]} \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-public-1},{Key=kubernetes.io/role/elb,Value=1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.102.0/24 \
        --availability-zone ${AZS[1]} \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-public-2},{Key=kubernetes.io/role/elb,Value=1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    # Create private subnets
    PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AZS[0]} \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-1},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.2.0/24 \
        --availability-zone ${AZS[1]} \
        --region $REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private-2},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    print_success "Subnets created:"
    print_status "  Public: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
    print_status "  Private: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
    
    # Create NAT Gateway
    EIP_1=$(aws ec2 allocate-address \
        --domain vpc \
        --region $REGION \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${CLUSTER_NAME}-nat-1}]" \
        --query 'AllocationId' \
        --output text)
    
    NAT_GW_1=$(aws ec2 create-nat-gateway \
        --subnet-id $PUBLIC_SUBNET_1 \
        --allocation-id $EIP_1 \
        --region $REGION \
        --query 'NatGateway.NatGatewayId' \
        --output text)
    
    print_success "NAT Gateway created: $NAT_GW_1"
    
    # Wait for NAT Gateway to be available
    print_status "Waiting for NAT Gateway to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_1 --region $REGION
    
    # Create route tables
    PUBLIC_RT=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --region $REGION \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${CLUSTER_NAME}-public}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    PRIVATE_RT=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --region $REGION \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${CLUSTER_NAME}-private}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    # Create routes
    aws ec2 create-route \
        --route-table-id $PUBLIC_RT \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID \
        --region $REGION
    
    aws ec2 create-route \
        --route-table-id $PRIVATE_RT \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id $NAT_GW_1 \
        --region $REGION
    
    # Associate subnets with route tables
    aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1 --route-table-id $PUBLIC_RT --region $REGION
    aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_2 --route-table-id $PUBLIC_RT --region $REGION
    aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1 --route-table-id $PRIVATE_RT --region $REGION
    aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2 --route-table-id $PRIVATE_RT --region $REGION
    
    print_success "VPC setup completed!"
    
    # Export variables for later use
    export VPC_ID PUBLIC_SUBNET_1 PUBLIC_SUBNET_2 PRIVATE_SUBNET_1 PRIVATE_SUBNET_2
}

# Create IAM roles
create_iam_roles() {
    print_status "Creating IAM roles..."
    
    # Create EKS service role
    cat > eks-service-role-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name ${CLUSTER_NAME}-service-role \
        --assume-role-policy-document file://eks-service-role-trust-policy.json || true
    
    aws iam attach-role-policy \
        --role-name ${CLUSTER_NAME}-service-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy || true
    
    # Create node group role
    cat > eks-nodegroup-role-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --assume-role-policy-document file://eks-nodegroup-role-trust-policy.json || true
    
    aws iam attach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy || true
    
    aws iam attach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy || true
    
    aws iam attach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly || true
    
    print_success "IAM roles created successfully!"
    
    # Get role ARNs
    CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-service-role --query 'Role.Arn' --output text)
    NODEGROUP_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-nodegroup-role --query 'Role.Arn' --output text)
    
    export CLUSTER_ROLE_ARN NODEGROUP_ROLE_ARN
}

# Create EKS cluster
create_eks_cluster() {
    print_status "Creating EKS cluster..."
    
    aws eks create-cluster \
        --name $CLUSTER_NAME \
        --version $KUBERNETES_VERSION \
        --role-arn $CLUSTER_ROLE_ARN \
        --resources-vpc-config subnetIds=$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2,$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2 \
        --region $REGION
    
    print_status "Waiting for EKS cluster to be active..."
    aws eks wait cluster-active --name $CLUSTER_NAME --region $REGION
    
    print_success "EKS cluster created successfully!"
}

# Create node group
create_node_group() {
    print_status "Creating EKS node group..."
    
    aws eks create-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name ${CLUSTER_NAME}-nodes \
        --node-role $NODEGROUP_ROLE_ARN \
        --subnets $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
        --instance-types $NODE_INSTANCE_TYPE \
        --scaling-config minSize=$NODE_MIN_CAPACITY,maxSize=$NODE_MAX_CAPACITY,desiredSize=$NODE_DESIRED_CAPACITY \
        --disk-size 50 \
        --ami-type AL2_x86_64 \
        --capacity-type ON_DEMAND \
        --region $REGION
    
    print_status "Waiting for node group to be active..."
    aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name ${CLUSTER_NAME}-nodes --region $REGION
    
    print_success "Node group created successfully!"
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    print_success "kubectl configured successfully!"
}

# Verify cluster
verify_cluster() {
    print_status "Verifying cluster..."
    
    kubectl cluster-info
    kubectl get nodes
    kubectl get pods -A
    
    print_success "Cluster verification completed!"
}

# Main deployment function
deploy_cluster() {
    print_status "Starting EKS cluster deployment with AWS CLI..."
    
    check_prerequisites
    create_vpc
    create_iam_roles
    create_eks_cluster
    create_node_group
    configure_kubectl
    verify_cluster
    
    print_success "EKS cluster deployment completed successfully!"
    print_status "Cluster name: $CLUSTER_NAME"
    print_status "Region: $REGION"
    print_status "Kubernetes version: $KUBERNETES_VERSION"
}

# Cleanup function
cleanup_cluster() {
    print_warning "Cleaning up EKS cluster resources..."
    
    # Delete node group
    aws eks delete-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name ${CLUSTER_NAME}-nodes \
        --region $REGION || true
    
    print_status "Waiting for node group deletion..."
    aws eks wait nodegroup-deleted \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name ${CLUSTER_NAME}-nodes \
        --region $REGION || true
    
    # Delete cluster
    aws eks delete-cluster \
        --name $CLUSTER_NAME \
        --region $REGION || true
    
    print_status "Waiting for cluster deletion..."
    aws eks wait cluster-deleted \
        --name $CLUSTER_NAME \
        --region $REGION || true
    
    # Delete IAM roles
    aws iam detach-role-policy \
        --role-name ${CLUSTER_NAME}-service-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy || true
    aws iam delete-role --role-name ${CLUSTER_NAME}-service-role || true
    
    aws iam detach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy || true
    aws iam detach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy || true
    aws iam detach-role-policy \
        --role-name ${CLUSTER_NAME}-nodegroup-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly || true
    aws iam delete-role --role-name ${CLUSTER_NAME}-nodegroup-role || true
    
    print_success "EKS cluster cleanup completed!"
}

# Help function
show_help() {
    echo "EKS Cluster Deployment Script (AWS CLI)"
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
        cleanup_cluster
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
# Launch Template for EKS Node Group (commented out for simplicity)
# resource "aws_launch_template" "main" {
#   name_prefix   = "${var.cluster_name}-node-group-"
#   image_id      = data.aws_ami.eks_worker.id
#   instance_type = var.node_instance_type
#
#   vpc_security_group_ids = [aws_security_group.node_group.id]
#
#   user_data = base64encode(templatefile("${path.module}/userdata.sh", {
#     cluster_name        = var.cluster_name
#     endpoint           = aws_eks_cluster.main.endpoint
#     certificate_authority = aws_eks_cluster.main.certificate_authority[0].data
#   }))
#
#   block_device_mappings {
#     device_name = "/dev/xvda"
#     ebs {
#       volume_size           = 50
#       volume_type          = "gp3"
#       delete_on_termination = true
#       encrypted            = true
#     }
#   }
#
#   metadata_options {
#     http_endpoint = "enabled"
#     http_tokens   = "required"
#     http_put_response_hop_limit = 2
#   }
#
#   tag_specifications {
#     resource_type = "instance"
#     tags = merge(var.tags, {
#       Name = "${var.cluster_name}-node"
#       "kubernetes.io/cluster/${var.cluster_name}" = "owned"
#     })
#   }
#
#   tags = var.tags
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# Data source for EKS optimized AMI (commented out)
# data "aws_ami" "eks_worker" {
#   filter {
#     name   = "name"
#     values = ["amazon-eks-node-${var.cluster_version}-v*"]
#   }
#
#   most_recent = true
#   owners      = ["602401143452"] # Amazon EKS AMI Account ID
# }

# Security Group for EKS Node Group
resource "aws_security_group" "node_group" {
  name_prefix = "${var.cluster_name}-node-group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port = 1025
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-group-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  disk_size       = 50

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_capacity
    min_size     = var.node_min_capacity
  }

  update_config {
    max_unavailable = 1
  }

  # launch_template {
  #   id      = aws_launch_template.main.id
  #   version = aws_launch_template.main.latest_version
  # }

  # Remote access configuration (commented out for now)
  # remote_access {
  #   ec2_ssh_key = aws_key_pair.main.key_name
  #   source_security_group_ids = [aws_security_group.node_group.id]
  # }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-group"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_group_amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.node_group_amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.node_group_amazon_ec2_container_registry_read_only,
  ]
}

# Key Pair for EC2 instances (commented out for now)
# resource "aws_key_pair" "main" {
#   key_name   = "${var.cluster_name}-keypair"
#   public_key = file("${path.module}/eks-key.pub")
#
#   tags = var.tags
# }
# =============================================================================
# MAIN INFRASTRUCTURE RESOURCES
# =============================================================================

# =============================================================================
# VPC CONFIGURATION
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # NAT Gateway configuration
  enable_nat_gateway = true
  single_nat_gateway = var.enable_single_nat_gateway

  # Internet Gateway
  create_igw = true

  # DNS configuration
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Manage default resources for better control
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.cluster_name}-default-nacl" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.cluster_name}-default-rt" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.cluster_name}-default-sg" }

  # Apply Kubernetes-specific tags to subnets
  public_subnet_tags  = merge(local.common_tags, local.public_subnet_tags)
  private_subnet_tags = merge(local.common_tags, local.private_subnet_tags)

  tags = local.common_tags
}

# =============================================================================
# EKS CLUSTER CONFIGURATION
# =============================================================================

module "retail_app_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  # Basic cluster configuration
  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  # Cluster access configuration
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  # EKS Auto Mode configuration - simplified node management
  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  # Network configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # KMS configuration to avoid conflicts
  create_kms_key = true
  kms_key_description = "EKS cluster ${local.cluster_name} encryption key"
  kms_key_deletion_window_in_days = 7
  
  # Cluster logging (optional - can be expensive)
  cluster_enabled_log_types = []

  tags = local.common_tags
}
# =============================================================================
# ECR REPOSITORIES
# =============================================================================

resource "aws_ecr_repository" "retail_store" {
  for_each = toset(["cart", "catalog", "orders", "ui", "checkout"])

  name                 = "retail-store-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}
# =============================================================================
# BUILD AND PUSH IMAGES TO ECR
# =============================================================================

resource "null_resource" "build_and_push_images" {
  for_each = toset(["cart", "catalog", "orders", "ui", "checkout"])

  depends_on = [aws_ecr_repository.retail_store]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region us-east-1 | \
        docker login --username AWS --password-stdin \
        839706991042.dkr.ecr.us-east-1.amazonaws.com

      docker build -t retail-store-${each.key} \
        ${path.module}/../src/${each.key}

      docker tag retail-store-${each.key}:latest \
        839706991042.dkr.ecr.us-east-1.amazonaws.com/retail-store-${each.key}:db791a4

      docker push \
        839706991042.dkr.ecr.us-east-1.amazonaws.com/retail-store-${each.key}:db791a4
    EOT
  }
}
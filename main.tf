data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "${var.name}-eks"

  # Production: 3 AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # 3 public + 3 private
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 10), cidrsubnet(var.vpc_cidr, 8, 11), cidrsubnet(var.vpc_cidr, 8, 12)]
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 20), cidrsubnet(var.vpc_cidr, 8, 21), cidrsubnet(var.vpc_cidr, 8, 22)]

  # CRITICAL: EKS module must NEVER see remote_access = null
  # Always pass a MAP (empty or populated) so module’s length() won’t crash.
  remote_access_map = var.enable_ssh ? tomap({
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.eks_ssh_access.id]
  }) : tomap({})
}

# ---------------------------
# VPC (HA NAT: 1 per AZ)
# ---------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_dns_support   = true
  enable_dns_hostnames = true

  # Production HA
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # Needed for EKS load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = var.name
  }
}

# ---------------------------
# Security Groups
# ---------------------------

# Controls access to EKS public API endpoint (443)
resource "aws_security_group" "eks_api_access" {
  name        = "${local.cluster_name}-api-access"
  description = "Access control for EKS public API"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Kubernetes API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.cluster_name}-api-access" }
}

# Optional SSH SG (separate, only used when enable_ssh=true)
resource "aws_security_group" "eks_ssh_access" {
  name        = "${local.cluster_name}-ssh-access"
  description = "SSH to EKS nodes (optional; prefer SSM in prod)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.cluster_name}-ssh-access" }
}

# Extra node SG (additional to module-managed SG rules)
resource "aws_security_group" "eks_nodes_extra" {
  name        = "${local.cluster_name}-nodes-extra"
  description = "Extra SG attached to EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  # Node-to-node traffic
  ingress {
    description = "All node-to-node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.cluster_name}-nodes-extra" }
}

# ---------------------------
# EKS (Prod-grade settings)
# ---------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint access
  cluster_endpoint_public_access  = var.enable_public_api
  cluster_endpoint_private_access = true
  cluster_additional_security_group_ids = var.enable_public_api ? [aws_security_group.eks_api_access.id] : []

  # Production: enable control-plane logs
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  cloudwatch_log_group_retention_in_days = 30

  # Production: encrypt Kubernetes secrets with KMS
  create_kms_key = true
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # Admin for terraform identity (fine for bootstrap; in prod you can add access_entries for roles)
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      name = "${var.name}-ng"

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 6
      desired_size = 2

      disk_size = 80

      # Extra SG for nodes
      additional_security_group_ids = compact([
        aws_security_group.eks_nodes_extra.id,
        var.enable_ssh ? aws_security_group.eks_ssh_access.id : null
      ])

      # ✅ The production-safe fix: never null
      remote_access = local.remote_access_map

      # Production: enable SSM (recommended over SSH)
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      labels = {
        nodegroup = "default"
      }
    }
  }

  # ✅ FIX: v20 expects cluster_addons, not eks_addons
  # NOTE: we set the EBS CSI role via IRSA below (service_account_role_arn)
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  tags = {
    Project = var.name
  }
}

# ---------------------------
# IRSA role for EBS CSI Driver (Production Best Practice)
# MUST be after module.eks exists because it needs module.eks.oidc_provider_arn
# ---------------------------
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Allow control-plane SG to reach nodes (common requirement)
resource "aws_security_group_rule" "nodes_ingress_from_cluster" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_nodes_extra.id
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_primary_security_group_id
  description              = "Control plane to nodes ephemeral kubelet pods"
}


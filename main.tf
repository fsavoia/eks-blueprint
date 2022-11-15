#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.16.0"

  cluster_name    = local.name
  cluster_version = local.version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  managed_node_groups = {
    mg_5 = {
      node_group_name      = local.node_group_name
      instance_types       = local.instance_types
      subnet_ids           = module.vpc.private_subnets
      force_update_version = true
      capacity_type        = local.capacity_type

      # Node Group scaling configuration
      desired_size = local.desired_size
      max_size     = local.max_size
      min_size     = local.min_size

      block_device_mappings = [
        {
          device_name = local.device_name
          volume_type = local.volume_type
          volume_size = local.volume_size
        }
      ]


    }
  }

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.16.0//modules/kubernetes-addons"

  eks_cluster_id               = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint         = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider            = module.eks_blueprints.oidc_provider
  eks_cluster_version          = module.eks_blueprints.eks_cluster_version
  eks_worker_security_group_id = module.eks_blueprints.worker_node_security_group_id
  auto_scaling_group_names     = module.eks_blueprints.self_managed_node_group_autoscaling_groups

  # EKS Addons
  enable_amazon_eks_vpc_cni = true
  amazon_eks_vpc_cni_config = {
    most_recent = true
  }

  enable_amazon_eks_coredns = true
  amazon_eks_coredns_config = {
    most_recent = true
  }

  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  tags = local.tags

  depends_on = [module.eks_blueprints ]
}
#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.16.0"

  cluster_name    = local.name
  cluster_version = local.version

  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = slice(module.vpc.private_subnets, 0, 3)
  control_plane_subnet_ids = module.vpc.intra_subnets

  # https://github.com/aws-ia/terraform-aws-eks-blueprints/issues/485
  # https://github.com/aws-ia/terraform-aws-eks-blueprints/issues/494
  cluster_kms_key_additional_admin_arns = [data.aws_caller_identity.current.arn]

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

      # # Launch template configuration
      custom_ami_id          = data.aws_ssm_parameter.eks_optimized_ami.value
      create_launch_template = true              # false will use the default launch template
      launch_template_os     = "amazonlinux2eks" # amazonlinux2eks or bottlerocket

      block_device_mappings = [
        {
          device_name = local.device_name
          volume_type = local.volume_type
          volume_size = local.volume_size
        }
      ]

      # Custom CNI setup
      # https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods
      pre_userdata = <<-EOT
        MAX_PODS=$(/etc/eks/max-pods-calculator.sh \
        --instance-type-from-imds \
        --cni-version ${trimprefix(data.aws_eks_addon_version.latest["vpc-cni"].version, "v")} \
        --cni-prefix-delegation-enabled \
        --cni-custom-networking-enabled \
        )
      EOT

      # These settings opt out of the default behavior and use the maximum number of pods, with a cap of 110 due to
      # Kubernetes guidance https://kubernetes.io/docs/setup/best-practices/cluster-large/
      # See more info here https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
      kubelet_extra_args   = "--max-pods=$${MAX_PODS}"
      bootstrap_extra_args = "--use-max-pods false"

    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Add-ons
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.16.0//modules/kubernetes-addons"

  eks_cluster_id               = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint         = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider            = module.eks_blueprints.oidc_provider
  eks_cluster_version          = module.eks_blueprints.eks_cluster_version
  eks_worker_security_group_id = module.eks_blueprints.worker_node_security_group_id
  auto_scaling_group_names     = module.eks_blueprints.self_managed_node_group_autoscaling_groups

  #---------------------------------------------------------------
  # EKS Native Add-on
  #---------------------------------------------------------------
  enable_amazon_eks_kube_proxy = true
  enable_amazon_eks_vpc_cni    = true
  amazon_eks_vpc_cni_config = {
    # Version 1.6.3-eksbuild.2 or later of the Amazon VPC CNI is required for custom networking
    # Version 1.9.0 or later (for version 1.20 or earlier clusters or 1.21 or later clusters configured for IPv4)
    # or 1.10.1 or later (for version 1.21 or later clusters configured for IPv6) of the Amazon VPC CNI for prefix delegation
    addon_version     = data.aws_eks_addon_version.latest["vpc-cni"].version
    resolve_conflicts = "OVERWRITE"
  }

  #---------------------------------------------------------------
  # ArgoCD Add-on
  #---------------------------------------------------------------
  enable_argocd         = true
  argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying Add-ons.

  argocd_applications = {
    addons    = local.addon_application
    workloads = local.workload_application
  }

  argocd_helm_config = {
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
  }

  #---------------------------------------------------------------
  # Kubernetes Adds-on managed by ArgoCD
  #---------------------------------------------------------------
  enable_metrics_server     = true
  enable_cluster_autoscaler = true
  enable_ingress_nginx      = true
  

  tags = local.tags

  depends_on = [
    # Modify VPC CNI ahead of addons
    null_resource.kubectl_set_env
  ]

}
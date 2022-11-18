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
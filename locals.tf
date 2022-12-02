locals {
  # EKS variables
  name    = "demo-blueprint"
  region  = "us-east-1"
  version = "1.23"

  # VPC variables
  vpc_cidr           = "10.0.0.0/16"
  secondary_vpc_cidr = "10.99.0.0/16"
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)

  # Managed Node Group Variables
  node_group_name = "managed-ondemand"
  instance_types  = ["m5.xlarge"]
  capacity_type   = "ON_DEMAND"
  desired_size    = 3
  min_size        = 1
  max_size        = 6
  device_name     = "/dev/xvda"
  volume_type     = "gp3"
  volume_size     = 150

  # kubernetes addons
  op_requests_cpu                = "1500m"
  enable_cluster-overprovisioner = false

  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------
  addon_application = {
    path               = "chart"
    repo_url           = "https://github.com/fsavoia/eks-blueprints-add-ons.git"
    add_on_application = true
  }

  #---------------------------------------------------------------
  # ARGOCD WORKLOAD APPLICATION
  #---------------------------------------------------------------
  workload_application = {
    path               = "envs/dev"
    repo_url           = "https://github.com/fsavoia/eks-blueprints-workloads.git"
    add_on_application = false
  }

  # Additional tags
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}
locals {
  # EKS variables
  name    = "demo-blueprint"
  region  = "us-east-1"
  version = "1.23"

  # VPC variables
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  # Managed Node Group Variables
  node_group_name = "managed-ondemand"
  instance_types  = ["m5.large"]
  capacity_type   = "ON_DEMAND"
  desired_size    = 3
  min_size        = 1
  max_size        = 6
  device_name     = "/dev/xvda"
  volume_type     = "gp3"
  volume_size     = 150

  # Additional tags
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}
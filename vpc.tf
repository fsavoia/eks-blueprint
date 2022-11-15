module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                  = local.name
  cidr                  = local.vpc_cidr
  secondary_cidr_blocks = [local.secondary_vpc_cidr]

  azs            = local.azs
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]

  private_subnets = concat(
    [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)],
    [for k, v in local.azs : cidrsubnet(local.secondary_vpc_cidr, 2, k)]
  )

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Modify VPC CNI deployment
#---------------------------------------------------------------
locals {
  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.eks_blueprints.eks_cluster_id
      cluster = {
        certificate-authority-data = module.eks_blueprints.eks_cluster_certificate_authority_data
        server                     = module.eks_blueprints.eks_cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.eks_blueprints.eks_cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}

resource "null_resource" "kubectl_set_env" {
  triggers = {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(local.kubeconfig)
    }

    # Reference https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/#cni-custom-networking
    # Reference https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
    command = <<-EOT
      # Custom networking
      kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true --kubeconfig <(echo $KUBECONFIG | base64 -d)
      kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone --kubeconfig <(echo $KUBECONFIG | base64 -d)
      # Prefix delegation
      kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true --kubeconfig <(echo $KUBECONFIG | base64 -d)
      kubectl set env daemonset aws-node -n kube-system WARM_PREFIX_TARGET=1 --kubeconfig <(echo $KUBECONFIG | base64 -d)
    EOT
  }

  depends_on = [module.eks_blueprints]

}

#---------------------------------------------------------------
# VPC-CNI Custom Networking ENIConfig
#---------------------------------------------------------------
resource "kubectl_manifest" "eni_config" {
  for_each = zipmap(local.azs, slice(module.vpc.private_subnets, 3, 6))

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [
        module.eks_blueprints.cluster_primary_security_group_id,
        module.eks_blueprints.worker_node_security_group_id,
      ]
      subnet = each.value
    }
  })

  depends_on = [module.eks_blueprints]

}
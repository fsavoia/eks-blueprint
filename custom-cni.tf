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
}
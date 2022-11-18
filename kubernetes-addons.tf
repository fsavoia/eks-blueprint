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

  #---------------------------------------------------------------
  # ArgoCD Add-on
  #---------------------------------------------------------------
  enable_argocd         = true
  argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying Add-ons.

  argocd_applications = {
    addons = local.addon_application
    # workloads = local.workload_application #We comment it for now
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
  enable_aws_load_balancer_controller = true
  enable_aws_for_fluentbit            = true
  enable_metrics_server               = true
  enable_cluster_autoscaler           = true

  tags = local.tags

  depends_on = [
    # Modify VPC CNI ahead of addons
    null_resource.kubectl_set_env
  ]

}
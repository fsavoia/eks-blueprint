resource "helm_release" "cluster-overprovisioner" {
  count            = local.enable_cluster-overprovisioner ? 1 : 0
  name             = "cluster-overprovisioner"
  chart            = "cluster-overprovisioner"
  repository       = "./charts"
  namespace        = "overprovisioning"
  create_namespace = true

  set {
    name  = "op.resources.requests.cpu"
    value = local.op_requests_cpu
  }


  depends_on = [
    module.eks_blueprints
  ]

}
resource "helm_release" "cluster-overprovisioner" {
  name             = "cluster-overprovisioner"
  chart            = "cluster-overprovisioner"
  repository       = "./charts"
  namespace        = "overprovisioning"
  create_namespace = true

  set {
    name  = "op.resources.requests.cpu"
    value = "6500m"
  }


  depends_on = [
    module.eks_blueprints
  ]

}
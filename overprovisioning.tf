resource "helm_release" "cluster-overprovisioner" {
  name             = "cluster-overprovisioner"
  chart            = "cluster-overprovisioner"
  repository       = "./charts"
  namespace        = "overprovisioning"
  create_namespace = true

  depends_on = [
    module.eks_blueprints
  ]

}
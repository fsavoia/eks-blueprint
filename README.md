# EKS Cluster w/ VPC-CNI Custom Networking and ArgoCD 

This example shows how to provision an EKS cluster with:
- ArgoCD: Workloads and addons deployed by ArgoCD
To better understand how ArgoCD works with EKS Blueprints, read the EKS Blueprints ArgoCD [Documentation](https://aws-ia.github.io/terraform-aws-eks-blueprints/latest/add-ons/argocd/)

- AWS VPC-CNI custom networking to assign IPs to pods from subnets outside of those used by the nodes
- AWS VPC-CNI prefix delegation to allow higher pod densities - this is useful since the custom networking removes one ENI from use for pod IP assignment which lowers the number of pods that can be assigned to the node. Enabling prefix delegation allows for prefixes to be assigned to the ENIs to ensure the node resources can be fully utilized through higher pod densitities. See the user data section below for managing the max pods assigned to the node.
- Dedicated /28 subnets for the EKS cluster control plane. Making changes to the subnets used by the control plane is a destructive operation - it is recommended to use dedicated subnets for the control plane that are separate from the data plane to allow for future growth through the addition of subnets without disruption to the cluster.

To disable prefix delegation from this example:

1. Remove the `--cni-prefix-delegation-enabled` flag from the user data script
2. Remove the environment environment variables `ENABLE_PREFIX_DELEGATION=true` and `WARM_PREFIX_TARGET=1` assignment from the `aws-node` daemonset (set in the `null_resource.kubectl_set_env` resource in this example)

## Reference Documentation:

- [CNI Documentation](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)
- [ArgoCD Documentation](https://aws-ia.github.io/terraform-aws-eks-blueprints/latest/add-ons/argocd/)
- [CNI Best Practices Guide](https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/#cni-custom-networking)
- [EKS Blueprints Add-ons Repo](https://github.com/aws-samples/eks-blueprints-add-ons)
- [EKS Blueprints Workloads Repo](https://github.com/aws-samples/eks-blueprints-workloads)


## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Deploy

To provision this example:

```sh
terraform init
terraform apply
```

Enter `yes` at command prompt to apply

## Validate CNI configuration

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl` to validate the deployment.

1. Run `update-kubeconfig` command:

```sh
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. List the nodes running currently

```sh
kubectl get nodes

# Output should look similar to below
NAME                                       STATUS   ROLES    AGE   VERSION
ip-10-0-34-74.us-west-2.compute.internal   Ready    <none>   86s   v1.22.9-eks-810597c
```

3. Inspect the nodes settings and check for the max allocatable pods - should be 110 in this scenario with m5.xlarge:

```sh
kubectl describe node ip-10-0-34-74.us-west-2.compute.internal

# Output should look similar to below (truncated for brevity)
  Capacity:
    attachable-volumes-aws-ebs:  25
    cpu:                         4
    ephemeral-storage:           104845292Ki
    hugepages-1Gi:               0
    hugepages-2Mi:               0
    memory:                      15919124Ki
    pods:                        110 # <- this should be 110 and not 58
  Allocatable:
    attachable-volumes-aws-ebs:  25
    cpu:                         3920m
    ephemeral-storage:           95551679124
    hugepages-1Gi:               0
    hugepages-2Mi:               0
    memory:                      14902292Ki
    pods:                        110 # <- this should be 110 and not 58
```

4. List out the pods running currently:

```sh
kubectl get pods -A -o wide

# Output should look similar to below
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                                       NOMINATED NODE   READINESS GATES
kube-system   aws-node-ttg4h             1/1     Running   0          52s   10.0.34.74    ip-10-0-34-74.us-west-2.compute.internal   <none>           <none>
kube-system   coredns-657694c6f4-8s5k6   1/1     Running   0          2m    10.99.135.1   ip-10-0-34-74.us-west-2.compute.internal   <none>           <none>
kube-system   coredns-657694c6f4-ntzcp   1/1     Running   0          2m    10.99.135.0   ip-10-0-34-74.us-west-2.compute.internal   <none>           <none>
kube-system   kube-proxy-wnzjd           1/1     Running   0          53s   10.0.34.74    ip-10-0-34-74.us-west-2.compute.internal   <none>           <none>
```

5. Inspect one of the `aws-node-*` (AWS VPC CNI) pods to ensure prefix delegation is enabled and warm prefix target is 1:

```sh
kubectl describe pod aws-node-ttg4h -n kube-system

# Output should look similar below (truncated for brevity)
  Environment:
    ADDITIONAL_ENI_TAGS:                    {}
    AWS_VPC_CNI_NODE_PORT_SUPPORT:          true
    AWS_VPC_ENI_MTU:                        9001
    AWS_VPC_K8S_CNI_CONFIGURE_RPFILTER:     false
    AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG:     true # <- this should be set to true
    AWS_VPC_K8S_CNI_EXTERNALSNAT:           false
    AWS_VPC_K8S_CNI_LOGLEVEL:               DEBUG
    AWS_VPC_K8S_CNI_LOG_FILE:               /host/var/log/aws-routed-eni/ipamd.log
    AWS_VPC_K8S_CNI_RANDOMIZESNAT:          prng
    AWS_VPC_K8S_CNI_VETHPREFIX:             eni
    AWS_VPC_K8S_PLUGIN_LOG_FILE:            /var/log/aws-routed-eni/plugin.log
    AWS_VPC_K8S_PLUGIN_LOG_LEVEL:           DEBUG
    DISABLE_INTROSPECTION:                  false
    DISABLE_METRICS:                        false
    DISABLE_NETWORK_RESOURCE_PROVISIONING:  false
    ENABLE_IPv4:                            true
    ENABLE_IPv6:                            false
    ENABLE_POD_ENI:                         false
    ENABLE_PREFIX_DELEGATION:               true # <- this should be set to true
    MY_NODE_NAME:                            (v1:spec.nodeName)
    WARM_ENI_TARGET:                        1 # <- this should be set to 1
    WARM_PREFIX_TARGET:                     1
    ...
```

## Validate ArgoCD configuration

1. List out the pods running currently:

    ```sh
    kubectl get pods -A

    NAMESPACE            NAME                                                         READY   STATUS    RESTARTS   AGE
    argo-rollouts        argo-rollouts-5656b86459-jgssp                               1/1     Running   0          6m59s
    argo-rollouts        argo-rollouts-5656b86459-kncxg                               1/1     Running   0          6m59s
    argocd               argo-cd-argocd-application-controller-0                      1/1     Running   0          15m
    argocd               argo-cd-argocd-applicationset-controller-9f66b8d6b-bnvqk     1/1     Running   0          15m
    argocd               argo-cd-argocd-dex-server-66c5769c46-kxns4                   1/1     Running   0          15m
    argocd               argo-cd-argocd-notifications-controller-74c78485d-fgh4w      1/1     Running   0          15m
    argocd               argo-cd-argocd-repo-server-77b8c98d6f-kcq6j                  1/1     Running   0          15m
    argocd               argo-cd-argocd-repo-server-77b8c98d6f-mt7nf                  1/1     Running   0          15m
    argocd               argo-cd-argocd-server-849d775f7b-t2crt                       1/1     Running   0          15m
    argocd               argo-cd-argocd-server-849d775f7b-vnwtq                       1/1     Running   0          15m
    argocd               argo-cd-redis-ha-haproxy-578979d984-5chwx                    1/1     Running   0          15m
    argocd               argo-cd-redis-ha-haproxy-578979d984-74qdg                    1/1     Running   0          15m
    argocd               argo-cd-redis-ha-haproxy-578979d984-9dwf2                    1/1     Running   0          15m
    argocd               argo-cd-redis-ha-server-0                                    4/4     Running   0          15m
    argocd               argo-cd-redis-ha-server-1                                    4/4     Running   0          12m
    argocd               argo-cd-redis-ha-server-2                                    4/4     Running   0          11m
    aws-for-fluent-bit   aws-for-fluent-bit-7gwzd                                     1/1     Running   0          7m10s
    aws-for-fluent-bit   aws-for-fluent-bit-9gzqw                                     1/1     Running   0          7m10s
    aws-for-fluent-bit   aws-for-fluent-bit-csrgh                                     1/1     Running   0          7m10s
    aws-for-fluent-bit   aws-for-fluent-bit-h9vtm                                     1/1     Running   0          7m10s
    aws-for-fluent-bit   aws-for-fluent-bit-p4bmj                                     1/1     Running   0          7m10s
    cert-manager         cert-manager-765c5d7777-k7jkk                                1/1     Running   0          7m6s
    cert-manager         cert-manager-cainjector-6bc9d758b-kt8dm                      1/1     Running   0          7m6s
    cert-manager         cert-manager-webhook-586d45d5ff-szkc7                        1/1     Running   0          7m6s
    geolocationapi       geolocationapi-fbb6987f8-d22qv                               2/2     Running   0          6m15s
    geolocationapi       geolocationapi-fbb6987f8-fqshh                               2/2     Running   0          6m15s
    karpenter            karpenter-5d65d77779-nnsjp                                   2/2     Running   0          7m42s
    keda                 keda-operator-676b4b8d8c-5bjmt                               1/1     Running   0          7m16s
    keda                 keda-operator-metrics-apiserver-5d679f968c-jkhz8             1/1     Running   0          7m16s
    kube-system          aws-node-66dl8                                               1/1     Running   0          14m
    kube-system          aws-node-7fgks                                               1/1     Running   0          14m
    kube-system          aws-node-828t9                                               1/1     Running   0          14m
    kube-system          aws-node-k7phx                                               1/1     Running   0          14m
    kube-system          aws-node-rptsc                                               1/1     Running   0          14m
    kube-system          cluster-autoscaler-aws-cluster-autoscaler-74456d5cc9-hfqlz   1/1     Running   0          7m24s
    kube-system          coredns-657694c6f4-kp6sm                                     1/1     Running   0          19m
    kube-system          coredns-657694c6f4-wcqh2                                     1/1     Running   0          19m
    kube-system          kube-proxy-6zwcj                                             1/1     Running   0          14m
    kube-system          kube-proxy-9kkg7                                             1/1     Running   0          14m
    kube-system          kube-proxy-q9bgv                                             1/1     Running   0          14m
    kube-system          kube-proxy-rzndg                                             1/1     Running   0          14m
    kube-system          kube-proxy-w86mz                                             1/1     Running   0          14m
    kube-system          metrics-server-694d47d564-psr4s                              1/1     Running   0          6m37s
    prometheus           prometheus-alertmanager-758597fd7-pntlj                      2/2     Running   0          7m18s
    prometheus           prometheus-kube-state-metrics-5fd8648d78-w48p2               1/1     Running   0          7m18s
    prometheus           prometheus-node-exporter-7wr8x                               1/1     Running   0          7m18s
    prometheus           prometheus-node-exporter-9hjzw                               1/1     Running   0          7m19s
    prometheus           prometheus-node-exporter-kjsxt                               1/1     Running   0          7m18s
    prometheus           prometheus-node-exporter-mr9cx                               1/1     Running   0          7m19s
    prometheus           prometheus-node-exporter-qmm58                               1/1     Running   0          7m19s
    prometheus           prometheus-pushgateway-8696df5474-cv59q                      1/1     Running   0          7m18s
    prometheus           prometheus-server-58c58c58cc-n4242                           2/2     Running   0          7m18s
    team-burnham         nginx-66b6c48dd5-nnp9l                                       1/1     Running   0          7m39s
    team-riker           guestbook-ui-6847557d79-lrms2                                1/1     Running   0          7m39s
    traefik              traefik-b9955f58-pc2zp                                       1/1     Running   0          7m4s
    vpa                  vpa-recommender-554f56647b-lcz9w                             1/1     Running   0          7m35s
    vpa                  vpa-updater-67d6c5c7cf-b9hw4                                 1/1     Running   0          7m35s
    yunikorn             yunikorn-scheduler-5c446fcc89-lcmmm                          2/2     Running   0          7m28s
    ```

3. You can access the ArgoCD UI by running the following command and get AWS Load Balancer address:

    ```sh
    export ARGOCD_SERVER=`kubectl get svc argo-cd-argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'`
    echo "https://$ARGOCD_SERVER"
    ```

    Then, open your browser and navigate to `https://$ARGOCD_SERVER`
    Username should be `admin`.

    Retrieve the generated secret for ArgoCD UI admin password. (Note: we could also instead have created a Secret Manager Password for Argo with terraform, see this [example](https://github.com/aws-ia/terraform-aws-eks-blueprints/blob/main/examples/gitops/argocd/main.tf#L77) 

    ```sh
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    ```

## Destroy

To teardown and remove the resources created in this example:

First, we need to ensure that the ArgoCD applications are properly cleaned up from the cluster, this can be achieved in multiple ways:

1) Disabling the `argocd_applications` configuration and running `terraform apply` again
2) Deleting the apps using `argocd` [cli](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/#deletion-using-argocd)
3) Deleting the apps using `kubectl` following [ArgoCD guidance](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/#deletion-using-kubectl)

```sh
terraform destroy -target=kubectl_manifest.eni_config -target=module.eks_blueprints_kubernetes_addons -auto-approve
terraform destroy -target=module.eks_blueprints -auto-approve
terraform destroy -auto-approve
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.9 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.4.1 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.39.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.7.1 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 1.14.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_blueprints"></a> [eks\_blueprints](#module\_eks\_blueprints) | github.com/aws-ia/terraform-aws-eks-blueprints | v4.16.0 |
| <a name="module_eks_blueprints_kubernetes_addons"></a> [eks\_blueprints\_kubernetes\_addons](#module\_eks\_blueprints\_kubernetes\_addons) | github.com/aws-ia/terraform-aws-eks-blueprints | v4.16.0//modules/kubernetes-addons |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 3.0 |

## Resources

| Name | Type |
|------|------|
| [helm_release.cluster-overprovisioner](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.eni_config](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [null_resource.kubectl_set_env](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_eks_addon_version.latest](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |
| [aws_ssm_parameter.eks_optimized_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
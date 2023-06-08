## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.1 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.1.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.10.1 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.21.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.1.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.10.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | github.com/terraform-aws-modules/terraform-aws-eks | v19.15.2 |
| <a name="module_eks_blueprints_addons"></a> [eks\_blueprints\_addons](#module\_eks\_blueprints\_addons) | github.com/aws-ia/terraform-aws-eks-blueprints-addons | v0.2.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | github.com/terraform-aws-modules/terraform-aws-vpc | v5.0.0 |

## Resources

| Name | Type |
|------|------|
| [helm_release.flux](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_ecrpublic_authorization_token.token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecrpublic_authorization_token) | data source |
| [aws_eks_cluster_auth.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of EKS Cluster | `string` | n/a | yes |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | EKS Version for Cluster | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR for VPC | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl |

## Project Information
This project accomplishes several key tasks for the creation of an Amazon EKS Cluster, deploying several key cluster addons as well as the creation of a sample workload. 
- Cluster Addons via EKS Blueprints Addons Module
  -  AWS VPC CNI
  -  Kubeproxy
  -  Coredns
  -  Karpenter
- Additional Deployments
  - Flux (installed using Helm provider)

#### Additional Notes
```Within the 'sample-workload' directory a deployment.yaml file is included deploying a simple inflate pod, this is done to demonstrate the proper use of nodeSelectors in order to place workloads on the Karpenter provisioned worker nodes. The workload being deployed by Flux is a sample app so I did not modify the nodeSelectors to utilize the provisioner. Additional Karpenter provisioners can easily be added using different labels to separate workloads based on node requirements, i.e. if a workload needs an arm based worker, a separate provisioner can handle this.```

#### Thoughts on project
```For sake of time, I have included all Flux related configurations in the 'main.tf' file. While this works for demonstration purposes, for long term use I would spend more time figuring out how to bootstrap the cluster at creation with Flux. The Flux Terraform provider has the limitation of only using your kubeconfig for cluster auth and this does not lend itself nicely for an all in one stack. Additionally, the bootstrapping would better allow a single GitOps repo for simplified cluster management and onboarding of future applications.```

#### Flux
```I am installing Flux using the Helm provider with a helm_release resource. For demonstration of application deployment, I am creating two CRD's, GitRepository and Kustomization. The first takes care of setting up the repository and reconciling its state and the second defines the working directory within the repo with the Kustomization files for deploying the sample Go application 'podinfo'. This same pattern could beused for the deployment of the service mentioned in the project, However, it would work much better if the CRD's were instead moved to a GitOps structured repository and the cluster was bootstrapped with this repo at creation. This would allow new applications to easily be onboarded without having to rerun the terraform stack, and thus better leveraging the capabilities of Flux.```
    
#### Thoughts on Observability
```Service health starts at the application, the quality of the healthchecks using Liveness & Readiness probes is the first layer that should receive focus. If the application uses a database or external services, this should be incorporated into a robust '/health' endpoint and exposed via a liveness probe. After health checks are in order, other instrumentation could be leveraged using something like AWS X-RAY or OpenTelemetry SDK's to instrument at the application level. Metrics, logs, and traces can be fed to a collection tool such as prometheus and exported into a tool such as grafana for visualization of the data. If something simpler is in order, or cost is something to consider AWS CloudWatch Container Insights could also be leveraged with a simpler setup (compared to configuring remote write of prometheus to AWS Managed Prometheus (AMP) or even a self hosted solution). This topic is very depenedent on tooling, as many choices are available.```

#### Thoughts on SLA's
```Several factors go into Service Level Agreements, from frequency of upgrades and possible introduction of bugs, to ensuring high availability in case of zonal outages. Starting at the infrastructure, upon creation of the Amazon EKS Cluster ensuring that your subnets are placed in multiple availability zones will help to prevent failure in case of zonal outage. By leveraging Kubernetes concepts such as TopologySpreadConstraints, we can ensure that our replicas are spread evenly across AZ's. This combined with proper autoscaling of the service via Horizontal Pod AutoScalers (HPA's) can help ensure the service scales appropriately in case of high traffic/load. The chance of down time can also be reduced by leveraging more complex deployment patterns, such as blue/green deployments. This pattern allows you to deploy an instance of your service side by side, exposed with its own ingress solution. You can then test the service in the green (or stage) environment prior to cutting production traffic over to the new instance. All of this together, in combination with proper testing and security scanning can all add up to delivering a high level of service availability.```
    
#### Thoughts on future improvements
```Currently I have been deploying the stack using localy installed Terraform CLI with remote state being managed via S3 and state locking with DynamoDB. For state management S3 & DynamoDB are well suited, but the manual execution of the terraform apply can be tedious. My next steps would be to move the cluster provisioning to a CI tool such as GitHub Actions or Jenkins. A custom workflow/or/pipeline could be used for the terraform apply, managing different environments or workspaces and also terraform delete for tearing down the stack. This would provide a central execution point for the automated provisioning pipeline for the infra, and also provide better log retention if you are not using something such as Terraform Cloud for stack creation.```
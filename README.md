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
    Within the 'sample-workload' directory a deployment.yaml file is included deploying a simple inflate pod, this is done to demonstrate the proper use of nodeSelectors in order to place workloads on the Karpenter provisioned worker nodes. Additional Karpenter provisioners can easily be added using different labels to separate workloads based on node requirements, i.e. if a workload needs arm based workers, a separate provisioner can hanbdle this.

#### Thoughts on project
    For sake of time, I have included all Flux related configurations in the 'main.tf' file. While this works for demonstration purposes, for long term use I would spend more time figuring out how to bootstrap the cluster at creation with Flux so that a single GitOps repo could be used for easier management and onboarding of future applications. The current Terraform Flux provider uses the kubeconfig for configuration to talk to the cluster, this presents a problem considering I am creating the cluster in the same stack.

#### Flux
    I am installing Flux using the Helm provider with a helm_release resource. For demonstration of application deployment, I am creating two CRD's, GitRepository and Kustomization. The first takes care of setting up the repository and reconciling its state and the second defines the working directory within the repo with the Kustomization files for deploying the sample go application 'podinfo'. This same pattern could be used for the deployment mentioned in the project, However, it would work much better if the CRD's were instead moved to a GitOps structured repository and the cluster was bootstrapped with this repo at creation. This would allow new applications to easily be onboarded without having to rerun the terraform stack, and thus better leveraging the capabilities of Flux.
    
#### Thought on Observability
    Service health starts at the application, the quality of the healthchecks using Liveness & Readiness probes is the first layer that should receive focus. If the application uses a database or external services, this should be incorporated into a robust /health endpoint and exposed via a liveness probe. After health checks are in order, other instrumentation could be leveraged using something like AWS X-RAY or OpenTelemetry SDK's to instrument at the application level, the metrics, logs, and traces can be fed to a collection tool such as prometheus and exported into a tool such as grafana for visualization of the data. If something simpler is in order, or cost is something to consider AWS CloudWatch Container Insights could also be leveraged with a much simpler setup (compared to configuring remote write of prometheus to AWS Managed Prometheus AMP or even a self hosted solution). This topic is very depenedent on tooling, as many choices are available.
    
#### Thoughts on future improvements
    Currently I have been deploying the stack using localy installed Terraform CLI with remote state being managed via S3 and state locking with DynamoDB. This for state management will suit fine, but the manual execution of the terraform apply can be tedious. My next steps would be to move the cluster provisioning to a CI tool such as GitHub Actions or Jenkins. A custom workflow/or/pipeline could be used for the terraform apply, managing different environments or workspaces and also terraform delete for tearing down the stack. This would provide a central execution point for the automated provisioning pipeline for the infra, and also provide better log retention if you are not using something like Terraform Cloud for stack creation.
    

  



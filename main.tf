######################################
# Configure Providers                #
######################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Requires the awscli to be installed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # Requires the awscli to be installed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Requires the awscli to be installed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

######################################
# Create Cluster                     #
######################################
module "eks" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks?ref=v19.15.2"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  eks_managed_node_groups = {
    mg_5 = {
      node_group_name = "core-node-grp"
      instance_types  = ["m5.xlarge"]
      subnet_ids      = module.vpc.private_subnets
      version         = var.cluster_version
      ami_type        = "AL2_x86_64"                                                       # Amazon Linux 2(AL2_x86_64), AL2_x86_64_GPU, AL2_ARM_64, BOTTLEROCKET_x86_64, BOTTLEROCKET_ARM_64

      # Set Min & Max Size
      desired_size = 3
      min_size     = 3
      max_size     = 9

      k8s_labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }
    }
  }

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

######################################
# Kubernetes Addons                  #
######################################
module "eks_blueprints_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=v0.2.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Enable core addons
  eks_addons = {
    coredns    = {}
    vpc-cni    = {}
    kube-proxy = {}
  }

  # Enable Karpenter
  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

}

######################################
# Install Flux                       #  
######################################
resource "helm_release" "flux" {
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  name             = "flux2"
  namespace        = "flux-system"
  create_namespace = true

  # Need to figure out the correct way to set the gitops repo url. Saving for later.
  set {
    name  = "git.url"
    value = "https://github.com/SnowBiz/flux-gitops.git"
  }

}

######################################
# Supporting Resources               #  
######################################

module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.0.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = var.cluster_name
  }
}


######################################
# Kubernetes CRD's (Flux / Karpenter)#
######################################
# !! << Service Linked Role >>
# !! If you have never used a spot instance, you must run the following command to create the service linked role.
# !! aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
# !! source: https://docs.aws.amazon.com/parallelcluster/latest/ug/spot.html
# !! << Using this provisioner >>
# !! This Karpenter provisioner uses the nodeGroupType: "apps" nodeSelector.
# !! In order to use this, include the nodeSelector on your deployment under Spec -> Template -> Spec in the deployment schema
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["4", "8", "16", "32"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ${jsonencode(local.azs)}
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type" # If not included, the webhook for the AWS cloud provider will default to on-demand
          operator: In
          values: ["spot", "on-demand"]
      kubeletConfiguration:
        containerRuntime: containerd
        maxPods: 110
      limits:
        resources:
          cpu: 1000
      consolidation:
        enabled: true
      providerRef:
        name: default
      labels:
        nodeGroupType: "apps"
      ttlSecondsUntilExpired: 604800 # 7 Days = 7 * 24 * 60 * 60 Seconds
  YAML

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelector:
        karpenter.sh/discovery: ${var.cluster_name}
      instanceProfile: ${module.eks_blueprints_addons.karpenter.node_instance_profile_name}
      tags:
        karpenter.sh/discovery: ${var.cluster_name}
  YAML

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "flux_git_repository" {
  yaml_body = <<-YAML
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata:
      name: podinfo
      namespace: default
    spec:
      interval: 5m0s
      url: https://github.com/stefanprodan/podinfo
      ref:
        branch: master
  YAML

  depends_on = [
    helm_release.flux
  ]
}

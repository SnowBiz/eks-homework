######################################
# Configure Providers                #
######################################
provider "aws" {
  region = "us-east-1"
  alias = "virginia"
}

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
    coredns = {
    # Pass in custom configuration for the managed addon, pin our coredns controller to our core nodegroup
    configuration_values = jsonencode({
      nodeSelector = {
        "NodeGroupType" : "core"
      }
    })
    }
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
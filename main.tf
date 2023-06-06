######################################
# Define Terraform Remote State Info #
######################################
terraform {
  backend "s3" {
    bucket = "eks-homework-terraform-state"
    region = "us-east-1"
    key    = "terraform.tfstate"
    dynamodb_table = "eks-homework-tf-state"
  }
}
######################################
# Configure Providers                #
######################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

######################################
# Create Cluster                     #
######################################
module "eks" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks?ref=v19.15.2"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  #vpc_id     = var.vpc_id
  #subnet_ids = var.private_subnet_ids
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
      #subnet_ids      = var.private_subnet_ids
      subnet_ids      = module.vpc.private_subnets
      version         = var.cluster_version
      ami_type        = "AL2_x86_64"                                                       # Amazon Linux 2(AL2_x86_64), AL2_x86_64_GPU, AL2_ARM_64, BOTTLEROCKET_x86_64, BOTTLEROCKET_ARM_64
      release_version = nonsensitive(data.aws_ssm_parameter.eks_ami_release_version.value) # Enter AMI release version to deploy the latest AMI released by AWS. Used only when you specify ami_type

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

################################################################################
# Supporting Resources
# Note: Normally I would suggest having a separate stack for the base network constructs
#       Then you would feed this in via the variables in the tfvars. This makes the eks
#       stack easier to use for spinning up new clusters within the same vpc, if needed.
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

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
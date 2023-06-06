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
      rolearn  = module.eks_blueprints_kubernetes_addons.karpenter.node_iam_role_arn
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

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.32.1/modules/kubernetes-addons"
  eks_cluster_id = module.eks.cluster_id

  # Enable VPC CNI
  enable_amazon_eks_vpc_cni = true
  amazon_eks_vpc_cni_config = {
    addon_name               = "vpc-cni"
    addon_version            = data.aws_eks_addon_version.default["vpc-cni"].version
    service_account          = "aws-node"
    resolve_conflicts        = "OVERWRITE"
    namespace                = "kube-system"
    additional_iam_policies  = []
    service_account_role_arn = ""
    tags                     = {}
  }

  # Enable CoreDNS - Pin to core nodegroup
  enable_amazon_eks_coredns                      = true
  enable_coredns_cluster_proportional_autoscaler = true
  amazon_eks_coredns_config = {
    addon_name               = "coredns"
    addon_version            = data.aws_eks_addon_version.default["coredns"].version
    service_account          = "coredns"
    resolve_conflicts_on_create        = "OVERWRITE"
    namespace                = "kube-system"
    service_account_role_arn = ""
    configuration_values = jsonencode({
      nodeSelector = {
        "NodeGroupType" : "core"
      }
    })
    additional_iam_policies = []
    tags                    = {}
  }

  # Enable KubeProxy
  enable_amazon_eks_kube_proxy = true
  amazon_eks_kube_proxy_config = {
    addon_name               = "kube-proxy"
    addon_version            = data.aws_eks_addon_version.default["kube-proxy"].version
    service_account          = "kube-proxy"
    resolve_conflicts        = "OVERWRITE"
    namespace                = "kube-system"
    additional_iam_policies  = []
    service_account_role_arn = ""
    tags                     = {}
  }

  # Karpenter
  enable_karpenter = true
  karpenter_helm_config = {
    repository_username = data.aws_ecrpublic_authorization_token.ecr_token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.ecr_token.password
  }

  karpenter_node_iam_instance_profile        = module.karpenter.instance_profile_name
  karpenter_enable_spot_termination_handling = true
  #karpenter_sqs_queue_arn                    = module.karpenter.queue_arn
}

module "karpenter" {
  source = "github.com/terraform-aws-modules/terraform-aws-eks?ref=v19.15.2/modules/karpenter"

  cluster_name = var.cluster_name
  create_irsa  = false # IRSA will be created by the kubernetes-addons module
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
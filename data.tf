data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_id
}

data "aws_ecrpublic_authorization_token" "token" {}

# You can have the node group track the latest version of the Amazon EKS optimized Amazon Linux AMI for a given EKS version by querying an Amazon provided SSM parameter. 
# Replace amazon-linux-2 in the parameter name below with amazon-linux-2-gpu to retrieve the accelerated AMI version and amazon-linux-2-arm64 to retrieve the Arm version.
data "aws_ssm_parameter" "eks_ami_release_version" {
  # aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.24/amazon-linux-2/recommended/image_id --region us-east-1 --query "Parameter.Value" --output text
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2/recommended/release_version"
}

# Grab appropriate versions for addoons
data "aws_eks_addon_version" "default" {
  for_each = toset(["coredns", "kube-proxy", "vpc-cni"])

  addon_name         = each.value
  kubernetes_version = var.cluster_version
  most_recent        = true
}
terraform {
  required_version = ">= 1.0.1"

  backend "s3" {
    bucket = "eks-homework-terraform-state"
    region = "us-east-1"
    key    = "terraform.tfstate"
    dynamodb_table = "eks-homework-tf-state"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.21.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}
######################################
# VPC / Subnet Variables             #
######################################
variable "region" {
    description = "AWS Region"
    type = string
}
variable "vpc_cidr" {
    description = "CIDR for VPC"
    type = string
}

######################################
# EKS Cluster Information            #
######################################
variable "cluster_name" {
    description = "Name of EKS Cluster"
    type = string
}

variable "cluster_version" {
    description = "EKS Version for Cluster"
    type = string
}
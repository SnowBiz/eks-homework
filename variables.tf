# ----------------------------------------------------
# VPC / Subnet Variables - (only needed if I am passing in vpc/subnets)
# ----------------------------------------------------

variable "region" {
    description = "AWS Region"
    type = string
}
/*
variable "vpc_id" {
    description = "Previously created VPC"
    type = string
}
*/
variable "vpc_cidr" {
    description = "CIDR for VPC"
    type = string
}
/*
variable "private_subnet_ids" {
    description = "Private Subnet ID's"
    type = list
}

variable "public_subnet_ids" {
    description = "Public Subnet ID's"
    type = list
}
*/

# ----------------------------------------------------
# EKS Cluster Information
# ----------------------------------------------------
variable "cluster_name" {
    description = "Name of EKS Cluster"
    type = string
}

variable "cluster_version" {
    description = "EKS Version for Cluster"
    type = string
}
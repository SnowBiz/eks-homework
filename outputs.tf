output "configure_kubectl" {
  description = "Configure kubectl"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.cluster_name}"
}
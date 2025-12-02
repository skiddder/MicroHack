variable "resource_group_name" {
  description = "The Azure resource group this AKS Managed Kubernetes Cluster should be provisioned"
  default     = "mh-arc-k8s-onprem"
}

variable "aks_name" {
  description = "This AKS Managed Kubernetes Cluster name"
  default     = "onprem-k8s"
}

variable "prefix" {
  description = "A prefix used for all resources for this AKS Managed Kubernetes Cluster"
  default     = "aks"
}

variable "location" {
  description = "The Azure Region in which all resources for this AKS Managed Kubernetes Cluster should be provisioned"
  default     = "germanywestcentral"
}

variable "kubernetes_version" {
  description = "Kubernetes version deployed"
  default     = "1.31.5"
}

variable "node_count" {
  description = "The number of Azure VMs for this AKS Managed Kubernetes Cluster node pool"
  default     = 2
}

variable "vm_size" {
  description = "The Azure VM size for this AKS Managed Kubernetes Cluster node pool"
  default     = "Standard_D4as_v5" # ATTENTION: While writing this microhack, arc-data-controller images are only available for amd64 architectures!
}

variable "client_id" {
  description = "The Client ID for the Service Principal to use for this AKS Managed Kubernetes Cluster"
}

variable "client_secret" {
  description = "The Client Secret for the Service Principal to use for this AKS Managed Kubernetes Cluster"
  sensitive = true
}
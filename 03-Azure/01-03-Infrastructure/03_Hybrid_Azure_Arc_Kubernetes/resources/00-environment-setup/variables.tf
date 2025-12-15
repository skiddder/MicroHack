variable "start_index" {
  description = "Starting index for resource naming"
  type        = number
  default     = 37
}

variable "end_index" {
  description = "Ending index for resource naming"
  type        = number
  default     = 39
}

variable "arc_location" {
  description = "The Azure Region in which all resources for Azure Arc should be provisioned"
  default     = "westeurope"
}

variable "onprem_resources" {
  description = "The Azure Region in which all resources for this AKS Managed Kubernetes Cluster should be provisioned"
  default     = ["italynorth", "francecentral", "swedencentral", "norwayeast", "germanywestcentral", "switzerlandnorth", "austriaeast", "northeurope", "polandcentral", "uksouth"]
}

variable "resource_group_base_name" {
  description = "Base name for resource groups (will be prefixed with index)"
  default     = "k8s"
}

variable "aks_base_name" {
  description = "This AKS Managed Kubernetes Cluster name"
  default     = "k8s-onprem"
}

variable "prefix" {
  description = "A prefix used for all resources for this AKS Managed Kubernetes Cluster"
  default     = "aks"
}

variable "kubernetes_version" {
  description = "Kubernetes version deployed"
  default     = "1.34"
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
resource "azurerm_resource_group" "mh_arc_aks_onprem" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "onprem" {
  name                = var.aks_name
  location            = azurerm_resource_group.mh_arc_aks_onprem.location
  resource_group_name = azurerm_resource_group.mh_arc_aks_onprem.name
  dns_prefix          = var.prefix

  kubernetes_version = var.kubernetes_version
  
  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }

  tags = {
    Project = "on-prem kubernetes cluster for microhack"
  }

  role_based_access_control_enabled = true
  
}

output "onprem_resource_group" {
  value = azurerm_resource_group.mh_arc_aks_onprem.name
}

output "onprem_aks_name" {
  value = azurerm_kubernetes_cluster.onprem.name
}
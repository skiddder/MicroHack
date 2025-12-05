resource "azurerm_resource_group" "mh_k8s_onprem" {
  count    = length(local.indices)
  name     = "${format("%02d", local.indices[count.index])}-${var.resource_group_base_name}-onprem"
  location = var.onprem_resources[count.index % length(var.onprem_resources)]
}

resource "azurerm_kubernetes_cluster" "onprem" {
  count               = length(local.indices)
  name                = "${format("%02d", local.indices[count.index])}-${var.resource_group_base_name}-onprem"
  location            = azurerm_resource_group.mh_k8s_onprem[count.index].location
  resource_group_name = azurerm_resource_group.mh_k8s_onprem[count.index].name
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
    Project = "simulated onprem k8s cluster for microhack"
  }

  role_based_access_control_enabled = true
  
}

output "rg_names_onprem" {
  #value = azurerm_resource_group.mh_k8s_onprem.name
  value = {
    for i, rg in azurerm_resource_group.mh_k8s_onprem : 
    local.indices[i] => rg.name
  }
}

output "onprem_k8s_name" {
  value = {
    for i, k8s in azurerm_kubernetes_cluster.onprem :
    local.indices[i] => k8s.name
  }
}
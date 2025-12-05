# will be used in challenge 04-gitops
variable "acr_name" {
    description = "The name of the Azure Container Registry"
    default     = "mhacr"
}

variable "container_registry_sku" {
    description = "The SKU of the Azure Container Registry"
    default     = "Basic"
}

variable "container_registry_admin_enabled" {
    description = "Specifies whether the admin user is enabled. Defaults to false."
    type        = bool
    default     = true
}

resource "azurerm_resource_group" "mh_k8s_arc" {
  count    = length(local.indices)
  name     = "${format("%02d", local.indices[count.index])}-${var.resource_group_base_name}-arc"
  location = var.arc_location
}

resource "azurerm_container_registry" "this" {
    count               = length(local.indices)
    name                = "${format("%02d", local.indices[count.index])}${var.acr_name}"
    resource_group_name = azurerm_resource_group.mh_k8s_arc[count.index].name
    location            = azurerm_resource_group.mh_k8s_arc[count.index].location
    sku                 = var.container_registry_sku
    admin_enabled       = var.container_registry_admin_enabled
}

output "rg_names_arc" {
  #value = azurerm_resource_group.mh_k8s_onprem.name
  value = {
    for i, rg in azurerm_resource_group.mh_k8s_arc : 
    local.indices[i] => rg.name
  }
}

output "acr_names" {
    value = {
        for i, acr in azurerm_container_registry.this :
        local.indices[i] => acr.name
    }
}
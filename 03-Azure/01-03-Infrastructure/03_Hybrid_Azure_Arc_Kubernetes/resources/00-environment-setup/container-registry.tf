# will be used in challenge 04-gitops
variable "acr_name" {
    description = "The name of the Azure Container Registry"
    default     = "mharck8sacr01"
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

resource "azurerm_container_registry" "this" {
    name                = var.acr_name
    resource_group_name = var.resource_group_name
    location            = var.location
    sku                 = var.container_registry_sku
    admin_enabled       = var.container_registry_admin_enabled
}
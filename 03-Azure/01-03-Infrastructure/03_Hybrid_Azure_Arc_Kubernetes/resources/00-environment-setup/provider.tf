#
# Providers Configuration
#

terraform {
  required_version = ">= 1.1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.22.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
  subscription_id = "REPLACE-ME"
}

#data "azurerm_subscription" "current" {}
#data "azurerm_client_config" "current" {}
# Blog Infra: Terraform configuration for Azure Container Apps, MySQL, and Storage

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "client_id" {
  description = "The Azure client ID"
  type        = string
}

variable "client_secret" {
  description = "The Azure client secret"
  type        = string
}

variable "tenant_id" {
  description = "The Azure tenant ID"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "uksouth"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "main" {
  name     = "wordpress-rg"
  location = var.location
}

resource "azurerm_container_registry" "main" {
  name                = "wordpressacr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_user_assigned_identity" "main" {
  name                = "wordpress-identity-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
}

resource "azurerm_mysql_flexible_server" "main" {
  name                = "wordpress-mysql-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  administrator_login = "adminuser"
  administrator_password = "P@ssw0rd123!"
  sku_name            = "B_Standard_B1ms"
  version             = "8.0.21"

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
}

resource "azurerm_mysql_flexible_server_active_directory_administrator" "main" {
  server_id   = azurerm_mysql_flexible_server.main.id
  identity_id = azurerm_user_assigned_identity.main.id
  login       = "wordpressadmin"
  tenant_id   = var.tenant_id
  object_id   = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_container_app" "main" {
  name                = "wordpress-container-app-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_registry.main.id
  revision_mode       = "Single"

  identity {
    type = "UserAssigned"
  }

  template {
    container {
      name   = "wordpress"
      image  = "${azurerm_container_registry.main.login_server}/wordpress:latest"
      cpu    = "0.5"
      memory = "1.0Gi"

      env {
        name  = "WORDPRESS_DB_HOST"
        value = azurerm_mysql_flexible_server.main.fqdn
      }
      env {
        name  = "WORDPRESS_DB_USER"
        value = "wordpressadmin"
      }
      env {
        name  = "WORDPRESS_DB_PASSWORD"
        value = null
      }
      env {
        name  = "WORDPRESS_DB_NAME"
        value = "wordpressdb"
      }
    }
  }
}
# Blog Deploy Infrostructure
# This script deploys a WordPress application using Azure Container Apps, MySQL, and Storage.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.64"
    }
  }
}

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

variable "wordpress_db_password" {
  description = "The WordPress database password"
  type        = string
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "main" {
  name     = "mlblog-rg"
  location = var.location
}

resource "azurerm_container_registry" "main" {
  name                = "wordpressacr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
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

resource "azurerm_key_vault" "main" {
  name                = "wordpress-kv-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "standard"
  tenant_id           = var.tenant_id
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = random_password.mysql_admin.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "random_password" "mysql_admin" {
  length  = 16
  special = true
}

resource "azurerm_mysql_flexible_server" "main" {
  name                = "wordpress-mysql-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  administrator_login = "adminuser"
  administrator_password = azurerm_key_vault_secret.mysql_admin_password.value
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

resource "azurerm_virtual_network" "main" {
  name                = "wordpress-vnet-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  address_space = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "main" {
  name                 = "wordpress-subnet-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "MicrosoftWebHostingEnvironments"

    service_delegation {
      name = "Microsoft.Web/hostingEnvironments"

      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_container_app_environment" "main" {
  name                = "wordpress-env-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
}

resource "azurerm_container_app" "main" {
  name                = "wordpress-container-app-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode       = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
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
        value = var.wordpress_db_password
      }
      env {
        name  = "WORDPRESS_DB_NAME"
        value = "wordpressdb"
      }
    }
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  principal_id         = azurerm_container_app.main.identity[0].principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main.id
  depends_on           = [azurerm_container_registry.main]
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  principal_id         = azurerm_user_assigned_identity.main.principal_id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.main.id
}
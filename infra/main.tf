# Blog Deploy Infrastructure using Gemini
# This script deploys a WordPress application using Azure Container Apps, MySQL, and Storage.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.64" # Consider updating to a more recent version if possible
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
  sensitive   = true # <-- UPDATED: Mark sensitive variables
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
  sensitive   = true # <-- UPDATED: Mark sensitive variables
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# <-- ADDED: Data source to get the identity running Terraform -->
data "azurerm_client_config" "current" {}

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
  name                      = "wordpress-kv-${random_string.suffix.result}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  sku_name                  = "standard"
  tenant_id                 = data.azurerm_client_config.current.tenant_id # <-- UPDATED: Use current client config tenant_id
  purge_protection_enabled  = true
  enable_rbac_authorization = true # <-- Keep this as true
}

resource "random_password" "mysql_admin" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?" # <-- UPDATED: Define allowed special characters if needed by MySQL/KV
}

# <-- ADDED: Role Assignment for the Terraform runner identity -->
resource "azurerm_role_assignment" "key_vault_secrets_officer_terraform_runner" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer" # Grants get, list, set, delete permissions
  principal_id         = data.azurerm_client_config.current.object_id
}

# <-- UPDATED: Role Assignment for the Managed Identity (renamed for clarity) -->
resource "azurerm_role_assignment" "key_vault_secrets_officer_managed_identity" {
  principal_id         = azurerm_user_assigned_identity.main.principal_id
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = random_password.mysql_admin.result
  key_vault_id = azurerm_key_vault.main.id

  # <-- UPDATED: Ensure Terraform runner has permissions before attempting to create the secret -->
  depends_on = [
    azurerm_role_assignment.key_vault_secrets_officer_terraform_runner
  ]
}

resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = "sleep 60" # Wait for RBAC propagation for the managed identity role
  }
  # <-- UPDATED: Depend on the renamed role assignment for the managed identity -->
  depends_on = [azurerm_role_assignment.key_vault_secrets_officer_managed_identity]
}

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "wordpress-mysql-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = var.location
  administrator_login    = "adminuser"
  administrator_password = azurerm_key_vault_secret.mysql_admin_password.value
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  # <-- ADDED: Depend on the delay to allow RBAC for managed identity to propagate -->
  depends_on = [null_resource.delay]
}

resource "azurerm_mysql_flexible_server_active_directory_administrator" "main" {
  server_id   = azurerm_mysql_flexible_server.main.id
  identity_id = azurerm_user_assigned_identity.main.id
  login       = "wordpressadmin" # This should match WORDPRESS_DB_USER if using AAD auth for WP
  tenant_id   = data.azurerm_client_config.current.tenant_id # <-- UPDATED
  object_id   = azurerm_user_assigned_identity.main.principal_id

  # <-- ADDED: Depend on the server creation -->
  depends_on = [azurerm_mysql_flexible_server.main]
}

# Consider creating the database itself via Terraform if needed
# resource "azurerm_mysql_flexible_database" "main" {
#   name                = "wordpressdb"
#   resource_group_name = azurerm_resource_group.main.name
#   server_name         = azurerm_mysql_flexible_server.main.name
#   charset             = "utf8mb4"
#   collation           = "utf8mb4_unicode_ci"
#
#   depends_on = [azurerm_mysql_flexible_server_active_directory_administrator.main]
# }


resource "azurerm_virtual_network" "main" {
  name                = "wordpress-vnet-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

# Note: The subnet delegation for 'Microsoft.Web/hostingEnvironments' is typically used for App Service Environments (ASE),
# not directly for Container Apps Environments unless integrating with specific network features.
# Container Apps Environments often integrate via 'Microsoft.App/environments'.
# Double-check if this specific delegation is strictly required for your Container App networking setup.
# If integrating the ACA Env into the VNet, the subnet often needs delegation to 'Microsoft.App/environments'.
# For now, leaving as is, but be aware of potential adjustments needed based on your networking goals.
resource "azurerm_subnet" "main" {
  name                 = "wordpress-subnet-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  # Example delegation for Container Apps Environment VNet integration (replace existing delegation if needed)
  # delegation {
  #   name = "MicrosoftAppDelegate"
  #   service_delegation {
  #     name    = "Microsoft.App/environments"
  #     actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  #   }
  # }

  # Keep original delegation if specifically required
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

# Note: Container App Environments can be VNet integrated or workload profile based.
# The current definition doesn't explicitly link it to the VNet/Subnet.
# If VNet integration is desired, you need to reference the subnet ID here.
# Example for VNet integration: infrastructure_subnet_id = azurerm_subnet.main.id
resource "azurerm_container_app_environment" "main" {
  name                       = "wordpress-env-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  # infrastructure_subnet_id = azurerm_subnet.main.id # <-- Uncomment and adjust if VNet integration needed
}

resource "azurerm_container_app" "main" {
  name                         = "wordpress-container-app-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  # ACR details - still useful if you add other containers using your private ACR later
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.main.id
  }

  template {
    container {
      name   = "wordpress"
      # <-- UPDATED: Use the official public image -->
      image  = "docker.io/library/wordpress:latest"
      cpu    = 0.5
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
        value = "wordpressdb" # Ensure this database exists or WP can create it
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    # azurerm_mysql_flexible_database.main
  ]
}

# <-- UPDATED: Role assignment for ACR Pull using the Managed Identity -->
resource "azurerm_role_assignment" "acr_pull" {
  # Use the principal ID of the *User Assigned Identity* associated with the Container App
  principal_id         = azurerm_user_assigned_identity.main.principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main.id

  # Depend on both the identity and the registry existing
  depends_on = [
    azurerm_user_assigned_identity.main,
    azurerm_container_registry.main
   ]
}

# Note: The key_vault_secrets_officer role for the managed identity is already defined above.
# If the Container App needs to read other secrets (like the WP password if stored in KV),
# ensure the key_vault_secrets_officer_managed_identity assignment is sufficient.
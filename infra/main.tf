terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Uncomment to use Azure Blob as remote state backend
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}


# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Azure Container Registry (ACR)
# ─────────────────────────────────────────────
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name          # globally unique, alphanumeric only
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku           # Basic | Standard | Premium
  admin_enabled       = false                  # needed for App Service pull

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# App Service Plan
# ─────────────────────────────────────────────
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.app_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku   # e.g. "B2", "P1v3"

  tags = local.common_tags
}

# # ─────────────────────────────────────────────
# # App Service (Web App for Containers)
# # ─────────────────────────────────────────────
resource "azurerm_linux_web_app" "main" {
  name                = var.webapp_name       # globally unique
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  # Allow App Service to pull from ACR
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = "8080"
    SPRING_PROFILES_ACTIVE              = var.spring_profile
  }

 logs {
  http_logs {
    file_system {
      retention_in_days = 7
       retention_in_mb   = 35
    }
  }
  application_logs {
    file_system_level = "Information"
  }
}

  tags = local.common_tags
}

# # ─────────────────────────────────────────────
# # Staging Deployment Slot
# # ─────────────────────────────────────────────
resource "azurerm_linux_web_app_slot" "staging" {
  count = local.use_slots ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    SPRING_PROFILES_ACTIVE              = "staging"
    WEBSITES_PORT                       = "8080"
  }


  tags = local.common_tags
}

# # ─────────────────────────────────────────────
# # ACR Pull Role Assignment for production slot
# # (SystemAssigned identity → AcrPull on the registry)
# # ─────────────────────────────────────────────
resource "azurerm_role_assignment" "webapp_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id

  depends_on = [
     azurerm_linux_web_app.main,
    azurerm_container_registry.acr
]
}

resource "azurerm_role_assignment" "staging_acr_pull" {
  count = local.use_slots ? 1 : 0
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id

  depends_on = [
    azurerm_linux_web_app_slot.staging,
    azurerm_container_registry.acr
]
}

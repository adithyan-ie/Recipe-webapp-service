terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

# ── RESOURCE GROUP ──────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ── AZURE CONTAINER REGISTRY ────────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

# ── LOG ANALYTICS + APP INSIGHTS (free tier, 30-day retention) ──────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-recipe-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-recipe-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# ── APP SERVICE PLAN (B1 initial → S1 for slots) ────────────────────────────
resource "azurerm_service_plan" "main" {
  name                = "asp-recipe-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

# ── BACKEND APP SERVICE (Java 17 Spring Boot via Docker) ────────────────────
resource "azurerm_linux_web_app" "backend" {
  name                = var.webapp_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true

    # THIS IS THE CRITICAL FIX - tells App Service which image to pull
    application_stack {
      docker_image_name   = "recipe-backend:latest"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = "8080"
    SPRING_PROFILES_ACTIVE              = var.spring_profile

    # App Insights auto-instrumentation
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.main.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.main.connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"

    # MongoDB Atlas connection - passed from GitHub Secret at plan-time
    MONGODB_URI = var.mongodb_uri
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

  depends_on = [azurerm_role_assignment.acr_pull]
}

# ── ACR PULL PERMISSION FOR APP SERVICE MANAGED IDENTITY ────────────────────
# Without this, the App Service cannot pull from ACR and stays empty
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.backend.identity[0].principal_id
}

# ── STAGING SLOT (only created when SKU >= S1) ──────────────────────────────
resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.backend.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
    application_stack {
      docker_image_name   = "recipe-backend:staging"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = "8080"
    SPRING_PROFILES_ACTIVE              = "staging"
    MONGODB_URI                         = var.mongodb_uri
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count                = var.enable_staging_slot ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

# ── OUTPUTS ─────────────────────────────────────────────────────────────────
output "webapp_url" {
  value = "https://${azurerm_linux_web_app.backend.default_hostname}"
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "staging_slot_url" {
  value = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : "staging slot not provisioned (requires S1+)"
}

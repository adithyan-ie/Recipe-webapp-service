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

# Reference the existing backend RG + ACR + plan (do NOT create new)
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

data "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  resource_group_name = var.resource_group_name
}

# Frontend App Service
resource "azurerm_linux_web_app" "frontend" {
  name                = var.frontend_webapp_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  service_plan_id     = data.azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
    application_stack {
      docker_image_name   = "recipe-frontend:latest"
      docker_registry_url = "https://${data.azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = "3000"
    BACKEND_URL                         = "https://${var.backend_webapp_name}.azurewebsites.net"
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

  tags = {
    project     = "recipe-webapp"
    environment = var.environment
    managed_by  = "terraform"
    tier        = "frontend"
  }

  depends_on = [azurerm_role_assignment.acr_pull_fe]
}

resource "azurerm_role_assignment" "acr_pull_fe" {
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.frontend.identity[0].principal_id
}

output "frontend_url" {
  value = "https://${azurerm_linux_web_app.frontend.default_hostname}"
}

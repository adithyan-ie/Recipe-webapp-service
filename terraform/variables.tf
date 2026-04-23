variable "environment" {
  description = "Environment name (dev, qa, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-recipe-webapp-dev"
}

variable "acr_name" {
  description = "Azure Container Registry name (globally unique, no hyphens)"
  type        = string
  default     = "recipewebappacrdev"
}

variable "webapp_name" {
  description = "App Service name (globally unique)"
  type        = string
  default     = "recipe-backend-dev"
}

variable "app_service_sku" {
  description = "App Service Plan SKU. B1 for initial provisioning (student subscription). S1 required for deployment slots."
  type        = string
  default     = "B1"

  validation {
    condition     = contains(["B1", "B2", "S1", "S2", "P1v3", "P2v3"], var.app_service_sku)
    error_message = "SKU must be one of: B1, B2, S1, S2, P1v3, P2v3."
  }
}

variable "enable_staging_slot" {
  description = "Create staging deployment slot. Requires SKU S1 or higher. Set to true AFTER SKU is upgraded."
  type        = bool
  default     = false
}

variable "spring_profile" {
  description = "Spring profile to activate"
  type        = string
  default     = "dev"
}

variable "mongodb_uri" {
  description = "MongoDB Atlas connection string. Passed from GitHub Secret TF_VAR_mongodb_uri."
  type        = string
  sensitive   = true
}

locals {
  common_tags = {
    project     = "recipe-webapp"
    environment = var.environment
    managed_by  = "terraform"
    module      = "EAD-CA2"
  }
}

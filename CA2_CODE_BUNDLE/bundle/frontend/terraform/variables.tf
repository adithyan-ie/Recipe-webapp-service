variable "environment" {
  type    = string
  default = "dev"
}

variable "resource_group_name" {
  type    = string
  default = "rg-recipe-webapp-dev"
}

variable "acr_name" {
  type    = string
  default = "recipewebappacrdev"
}

variable "app_service_plan_name" {
  type    = string
  default = "asp-recipe-dev"
}

variable "frontend_webapp_name" {
  type    = string
  default = "recipe-frontend-dev"
}

variable "backend_webapp_name" {
  type    = string
  default = "recipe-backend-dev"
}

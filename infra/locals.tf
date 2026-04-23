locals {
  common_tags = {
    project     = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
  use_slots = var.app_service_sku != "B1"
}

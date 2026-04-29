# ─────────────────────────────────────────────────────
# terraform.tfvars — fill in your actual values
# DO NOT commit this file with real secrets to git.
# Add terraform.tfvars to .gitignore.
# ─────────────────────────────────────────────────────

resource_group_name = "rg-recipe-webapp-dev"
location            = "switzerlandnorth"
environment         = "production"
app_name            = "recipe-backend"

# Must be globally unique across all Azure customers
webapp_name = "recipe-backend-prd"

# Must be globally unique, 5-50 alphanumeric chars only
acr_name = "recipewebappacrdev"

acr_sku         = "Basic"      # Upgrade to Standard/Premium for geo-replication
app_service_sku = "B1"       # P1v3 minimum recommended for production + slots

image_name     = "spring-app:bootstrap"

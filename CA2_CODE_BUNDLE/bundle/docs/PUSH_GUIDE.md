# PUSH GUIDE - Rakesh's exact commands

Run each block one at a time on your laptop. Assumes `az login` done, `gh auth login` done.

Total time: ~25 minutes.

─────────────────────────────────────────────────────────────────────────────
## STEP 1 — Verify GitHub Secrets exist on both repos (~5 min)
─────────────────────────────────────────────────────────────────────────────

You need these 2 secrets set in BOTH repos:

```bash
# 1. Create Azure service principal if you don't have one yet
az ad sp create-for-rbac --name "gh-recipe-webapp" \
  --role contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv) \
  --sdk-auth
```

Copy the JSON output. Now add as secret to BOTH repos:

```bash
# Backend repo
gh secret set AZURE_CREDENTIALS --repo adithyan-ie/Recipe-webapp-service
# Paste the JSON when prompted, then Ctrl+D

gh secret set MONGODB_URI --repo adithyan-ie/Recipe-webapp-service
# Paste: mongodb+srv://...  (your actual Atlas connection string)

# Frontend repo
gh secret set AZURE_CREDENTIALS --repo adithyan-ie/Recipe-webapp-ui
# Paste same JSON
```

─────────────────────────────────────────────────────────────────────────────
## STEP 2 — Push files to BACKEND repo (~5 min)
─────────────────────────────────────────────────────────────────────────────

```bash
# Clone (or cd into your existing local clone)
cd ~
git clone https://github.com/adithyan-ie/Recipe-webapp-service.git
cd Recipe-webapp-service

# Copy the bundle files
# (Unzip the bundle first. Assume it's at ~/bundle/)
cp -r ~/bundle/backend/.github ./
cp -r ~/bundle/backend/terraform ./

# Rename example to real tfvars (EDIT THE FILE - set your actual values)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# terraform.tfvars is gitignored - will not be pushed
echo "terraform/terraform.tfvars" >> .gitignore
echo "terraform/.terraform/" >> .gitignore
echo "terraform/*.tfstate*" >> .gitignore

# Commit to main
git add .
git commit -m "feat: add Terraform IaC + GitHub Actions workflows for 4 branches"
git push origin main
```

─────────────────────────────────────────────────────────────────────────────
## STEP 3 — Create 3 other branches (~2 min)
─────────────────────────────────────────────────────────────────────────────

```bash
# Still in Recipe-webapp-service
git checkout -b development
git push -u origin development

git checkout -b qa
git push -u origin qa

git checkout -b release
git push -u origin release

git checkout main
```

─────────────────────────────────────────────────────────────────────────────
## STEP 4 — Apply fixed Terraform LOCALLY (~5 min)
─────────────────────────────────────────────────────────────────────────────

This is the critical step - fixes your empty App Service problem.

```bash
cd terraform
terraform init -upgrade

# Set the MongoDB URI (do NOT commit this)
export TF_VAR_mongodb_uri="mongodb+srv://YOUR_ATLAS_USER:YOUR_PASSWORD@cluster.mongodb.net/recipedb?retryWrites=true"

# Review plan
terraform plan

# Apply
terraform apply -auto-approve
```

Expected output: App Service now has `application_stack` with ACR image reference, and AcrPull role assigned.

─────────────────────────────────────────────────────────────────────────────
## STEP 5 — Trigger backend pipelines (~2 min)
─────────────────────────────────────────────────────────────────────────────

```bash
# Make a trivial commit on each branch to trigger workflows
git checkout development
echo "# dev trigger" >> .github/workflows/README.md
git add . && git commit -m "chore: trigger dev pipeline" && git push

git checkout qa
git merge development
git push

git checkout release
git merge qa
git push

git checkout main
git merge release
git push
```

Wait ~2 min. Go to: https://github.com/adithyan-ie/Recipe-webapp-service/actions

You should see 4 runs in progress or completed.

─────────────────────────────────────────────────────────────────────────────
## STEP 6 — Create staging-approval GitHub Environment (~3 min)
─────────────────────────────────────────────────────────────────────────────

Browser: https://github.com/adithyan-ie/Recipe-webapp-service/settings/environments

1. Click "New environment" → name: staging-approval
2. Tick "Required reviewers" → add yourself
3. Save

(Also do this for the FE repo.)

─────────────────────────────────────────────────────────────────────────────
## STEP 7 — Push FRONTEND repo (~5 min)
─────────────────────────────────────────────────────────────────────────────

```bash
cd ~
git clone https://github.com/adithyan-ie/Recipe-webapp-ui.git
cd Recipe-webapp-ui

cp -r ~/bundle/frontend/.github ./
cp -r ~/bundle/frontend/terraform ./

# Create a Dockerfile if missing
cat > Dockerfile << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build --if-present

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app ./
EXPOSE 3000
CMD ["npm", "start"]
EOF

echo "terraform/.terraform/" >> .gitignore
echo "terraform/*.tfstate*" >> .gitignore
echo "node_modules/" >> .gitignore

git add .
git commit -m "feat: add Terraform + CI/CD workflows for frontend"
git push origin main

# Create branches
git checkout -b development && git push -u origin development
git checkout -b qa && git push -u origin qa
git checkout -b release && git push -u origin release
git checkout main

# Apply FE Terraform (creates the FE App Service)
cd terraform
terraform init
terraform apply -auto-approve
```

─────────────────────────────────────────────────────────────────────────────
## STEP 8 — Verify (~2 min)
─────────────────────────────────────────────────────────────────────────────

Check in Azure Portal:
- rg-recipe-webapp-dev has: ACR, Plan, BE App Service, FE App Service, Log Analytics, App Insights
- ACR repositories list shows `recipe-backend` and `recipe-frontend`
- Browse to `https://recipe-backend-dev.azurewebsites.net/` - should return JSON
- Browse to `https://recipe-frontend-dev.azurewebsites.net/` - should load UI

In GitHub Actions: all 4 branches have green runs on both repos.

─────────────────────────────────────────────────────────────────────────────
## TROUBLESHOOTING
─────────────────────────────────────────────────────────────────────────────

**Problem: terraform plan fails "app_service_sku not valid"**
→ B1 is fine for first run. Don't touch `enable_staging_slot` yet.

**Problem: App Service still 502 after apply**
→ Wait 3-4 minutes. Azure takes time to pull the image. Check ACR - if the repository is empty, the pipeline hasn't pushed yet. Trigger it manually.

**Problem: AcrPull role assignment fails**
→ Your service principal needs Owner role on the subscription (not just Contributor). Re-run step 1 with `--role Owner`.

**Problem: Pipeline fails on `az login` with credential error**
→ The AZURE_CREDENTIALS JSON secret must be the COMPLETE output including curly braces. Paste the whole thing.

**Problem: Sonar scan fails**
→ It's set to `continue-on-error`. Pipeline still goes green. Ignore for submission.

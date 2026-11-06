#!/usr/bin/env bash
# Creates (or refreshes) the service principal Terraform uses, gives it the roles it needs, and writes
# its credentials to infra/.env (git-ignored, mode 600). Safe to re-run: it reuses the app and issues a new secret.
#
# Needs: az login as a user who can create app registrations AND role assignments.
# If role assignment fails with 403, turn on "Access management for Azure resources" first (docs/service-principal.md).
set -euo pipefail

NAME="${SP_NAME:-sp-landing-zone-tf}"
STATE_RG="${STATE_RG:-rg-tfstate-lz-san}"
STATE_ACCOUNT="${STATE_ACCOUNT:?set STATE_ACCOUNT to the storage account name, e.g. STATE_ACCOUNT=stlztf31860625}"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/infra/.env"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
STATE_SCOPE="$(az storage account show -g "$STATE_RG" -n "$STATE_ACCOUNT" --query id -o tsv)"

echo "Subscription: $SUB_ID"
echo "Service principal: $NAME"

APP_ID="$(az ad app list --display-name "$NAME" --query "[0].appId" -o tsv)"
if [ -z "$APP_ID" ]; then
  echo "Creating app registration and service principal..."
  APP_ID="$(az ad sp create-for-rbac --name "$NAME" --query appId -o tsv)"
else
  echo "Reusing existing app $APP_ID"
fi

echo "Issuing a new client secret (1 year)..."
SECRET="$(az ad sp credential reset --id "$APP_ID" --years 1 --query password -o tsv)"

echo "Assigning roles..."
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUB_ID" -o none
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" \
  --scope "$STATE_SCOPE" -o none

umask 077
cat > "$ENV_FILE" <<ENV
export ARM_CLIENT_ID="$APP_ID"
export ARM_CLIENT_SECRET="$SECRET"
export ARM_TENANT_ID="$TENANT_ID"
export ARM_SUBSCRIPTION_ID="$SUB_ID"
ENV

echo
echo "Done. Credentials written to $ENV_FILE (not committed)."
echo "Use it:  cd infra && source .env && terraform plan"

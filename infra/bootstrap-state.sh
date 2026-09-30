#!/usr/bin/env bash
set -euo pipefail

# Creates the remote state backend. It deliberately has no Terraform backend:
# Terraform cannot use a backend that it has not created yet.
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP (for example rg-celrys-platform-prod)}"
: "${LOCATION:?Set LOCATION (for example centralindia)}"
: "${STATE_STORAGE_ACCOUNT:?Set a globally unique, lowercase storage account name}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
az storage account create \
  --name "$STATE_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
  --kind StorageV2 --sku Standard_RAGRS --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false --https-only true \
  --default-action Deny --bypass AzureServices --require-infrastructure-encryption true >/dev/null
ACCOUNT_ID="$(az storage account show --name "$STATE_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$ACCOUNT_ID" >/dev/null 2>&1 || true
az storage container create --name "$STATE_CONTAINER" --account-name "$STATE_STORAGE_ACCOUNT" --auth-mode login >/dev/null
az storage account blob-service-properties update --account-name "$STATE_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 >/dev/null

cat <<EOF
Created the Terraform state backend. Create infra/backend.hcl (it is ignored by Git):

resource_group_name  = "$RESOURCE_GROUP"
storage_account_name = "$STATE_STORAGE_ACCOUNT"
container_name       = "$STATE_CONTAINER"
key                  = "prod.tfstate"
use_azuread_auth     = true
EOF

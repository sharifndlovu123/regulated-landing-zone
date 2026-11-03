# Creates the storage account that holds Terraform state for ../infra.
# Run once, by hand. Its own state stays local (see ../README note), because it cannot store state in itself.

data "azurerm_client_config" "current" {}

locals {
  # Storage names are global, 3-24 lowercase letters/digits. A hash of the subscription keeps it unique but stable.
  account_name = "stlztf${substr(md5(var.subscription_id), 0, 8)}"

  tags = {
    owner       = var.owner
    environment = "platform"
    cost-center = "portfolio"
    managed-by  = "terraform"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-tfstate-lz-san"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                     = local.account_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # No public access and no shared keys: only signed-in identities can touch state.
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true # every state write is kept, so a bad apply can be rolled back

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Not managed here: reading/writing the state blob needs "Storage Blob Data Contributor" on this
# account (shared keys are off). The deploying account only has Contributor, which cannot create
# role assignments, so this role is granted manually outside Terraform.

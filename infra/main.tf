# Piece 1: one resource group for the hub. Networks and the rest are added in later pieces.
resource "azurerm_resource_group" "hub" {
  name     = "rg-hub-${local.suffix}"
  location = var.location
  tags     = local.tags
}

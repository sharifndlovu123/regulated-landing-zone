# Piece 3: hub-and-spoke network. No firewall yet (piece 7), so spokes can reach the hub but not each other:
# VNet peering is not transitive, and nothing routes spoke-to-spoke traffic until the firewall exists.

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${local.suffix}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_cidr]
  tags                = local.tags
}

# Reserved for Azure Firewall. Azure requires this exact name, and a /26 or larger.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 2, 0)]
}

# --- Spokes -----------------------------------------------------------------

resource "azurerm_resource_group" "spoke" {
  for_each = var.spokes

  name     = "rg-spoke-${each.key}-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  for_each = var.spokes

  name                = "vnet-spoke-${each.key}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke[each.key].name
  address_space       = [each.value.cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "spoke" {
  for_each = var.spokes

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.spoke[each.key].name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [cidrsubnet(each.value.cidr, 2, 0)]

  # Private-only: no implicit internet egress. Outbound will go through the firewall (piece 7).
  default_outbound_access_enabled = false
}

# NSG rules arrive with the firewall piece, when there is cross-spoke traffic to allow or deny.
resource "azurerm_network_security_group" "spoke" {
  for_each = var.spokes

  name                = "nsg-${each.key}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke[each.key].name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each = var.spokes

  subnet_id                 = azurerm_subnet.spoke[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}

# --- Peering (two directions, both required) ---------------------------------

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = var.spokes

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = var.spokes

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.spoke[each.key].name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true # lets traffic that the hub firewall forwards in
  allow_virtual_network_access = true
}

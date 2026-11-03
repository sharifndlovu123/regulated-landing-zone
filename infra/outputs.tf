output "hub_resource_group" {
  value = azurerm_resource_group.hub.name
}

output "spoke_subnets" {
  value = { for k, s in azurerm_subnet.spoke : k => s.id }
}

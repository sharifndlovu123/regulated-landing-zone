output "backend_config" {
  description = "Values for the remote backend (consumed by ../infra)"
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
    key                  = "regulated-landing-zone.tfstate"
  }
}
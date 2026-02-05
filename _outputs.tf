output "resource_group_name" {
  value = local.rg_name
}

output "storage_account" {
  value = {
    id   = azurerm_storage_account.this.id
    name = azurerm_storage_account.this.name
  }
}

output "private_dns" {
  value = local.private_enabled ? {
    resource_group_name = local.dns_rg_name
    zones               = { for k, v in local.pe_services_enabled : k => local.private_dns_zone_id[k] }
  } : null
}

output "private_endpoints" {
  value = local.private_enabled ? {
    for k, v in local.pe_services_enabled :
    k => {
      id   = azurerm_private_endpoint.this[k].id
      name = azurerm_private_endpoint.this[k].name
    }
  } : {}
}

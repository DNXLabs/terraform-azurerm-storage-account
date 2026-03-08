resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "azurerm_resource_group" "dns" {
  for_each = local.dns_rg_create ? { "this" = true } : {}
  name     = local.dns_rg_name
  location = local.dns_rg_loc
  tags     = local.tags
}

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = local.rg_name
  location                 = local.rg_loc
  account_kind             = try(var.storage.account_kind, "StorageV2")
  account_tier             = try(var.storage.account_tier, "Standard")
  account_replication_type = try(var.storage.account_replication_type, "LRS")
  access_tier              = try(var.storage.access_tier, "Hot")

  public_network_access_enabled = try(var.storage.public_network_access_enabled, false)
  allow_nested_items_to_be_public = try(var.storage.allow_nested_items_to_be_public, false)
  shared_access_key_enabled     = try(var.storage.shared_access_key_enabled, true)
  min_tls_version               = try(var.storage.min_tls_version, "TLS1_2")
  https_traffic_only_enabled    = try(var.storage.https_traffic_only_enabled, true)

  is_hns_enabled = try(var.storage.is_hns_enabled, false)
  nfsv3_enabled  = try(var.storage.nfsv3_enabled, false)

  dynamic "network_rules" {
    for_each = var.network_rules != null ? [var.network_rules] : []
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }

  tags = local.tags

  blob_properties {
    delete_retention_policy {
      days = 1 # Minimal retention for easy cleanup
    }
    container_delete_retention_policy {
      days = 1 # Minimal retention for easy cleanup
    }
  }
}

resource "azurerm_storage_container" "this" {
  for_each = { for c in var.containers : c.name => c }

  name                 = each.value.name
  storage_account_id   = azurerm_storage_account.this.id
  container_access_type = try(each.value.access_type, "private")
}

resource "azurerm_storage_share" "this" {
  for_each = { for s in var.file_shares : s.name => s }

  name               = each.value.name
  storage_account_id = azurerm_storage_account.this.id
  quota              = try(each.value.quota_gb, 100)
}

resource "azurerm_private_dns_zone" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.dns_zone_should_create[k] }

  name                = each.value.zone_name
  resource_group_name = local.dns_rg_name
  tags                = local.tags
  depends_on = [
    azurerm_resource_group.dns
  ]
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.vnet_link_should_create[k] }

  name                = each.value.link_name
  resource_group_name = local.dns_rg_name

  private_dns_zone_name = coalesce(
    try(azurerm_private_dns_zone.this[each.key].name, null),
    each.value.zone_name
  )

  virtual_network_id = local.vnet_id
  tags               = local.tags

  depends_on = [
    azurerm_resource_group.dns,
    azurerm_private_dns_zone.this
  ]
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.pe_services_enabled
  name                = each.value.pe_name
  location            = local.pe_rg_loc
  resource_group_name = local.pe_rg_name
  subnet_id                     = local.pe_subnet_id
  custom_network_interface_name = each.value.nic_name
  tags                          = local.tags

  private_service_connection {
    name                           = each.value.psc_name
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = [each.value.subresource]
  }

  private_dns_zone_group {
    name                 = "pdzg-${each.key}"
    private_dns_zone_ids = [local.private_dns_zone_id[each.key]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.storage_account_name}"
  target_resource_id             = azurerm_storage_account.this.id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_metric {
    category = "Capacity"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.storage_account_name}-blob"
  target_resource_id             = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }

  enabled_metric {
    category = "Capacity"
  }

  enabled_metric {
    category = "Transaction"
  }
}

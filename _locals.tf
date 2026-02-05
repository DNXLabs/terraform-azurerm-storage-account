locals {
  prefix = "${var.naming.org}-${var.naming.env}-${var.naming.region}-${var.naming.workload}"

  default_tags = {
    org       = var.naming.org
    env       = var.naming.env
    region    = var.naming.region
    workload  = var.naming.workload
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location

  base_sa_name_raw = "${var.naming.org}${var.naming.env}${var.naming.region}${var.naming.workload}${try(var.storage.name_suffix, "001")}"
  base_sa_name     = substr(replace(lower(local.base_sa_name_raw), "/[^0-9a-z]/", ""), 0, 24)

  storage_account_name = coalesce(try(var.storage.name, null), local.base_sa_name)

  private_enabled = try(var.private.enabled, false)

  dns_create_zone      = local.private_enabled && try(var.private.dns.create_zone, true)
  dns_create_vnet_link = local.private_enabled && try(var.private.dns.create_vnet_link, true)

  pe_subnet_id = try(var.private.pe_subnet_id, null)
  vnet_id      = try(var.private.vnet_id, null)

  pe_catalog = {
    blob = {
      subresource = "blob"
      zone_name   = "privatelink.blob.core.windows.net"
      link_name   = "link-privatelink-blob-core-windows-net"
    }
    file = {
      subresource = "file"
      zone_name   = "privatelink.file.core.windows.net"
      link_name   = "link-privatelink-file-core-windows-net"
    }
  }

  pe_services_enabled = local.private_enabled ? {
    for k, enabled in try(var.private.endpoints, {}) :
    k => merge(local.pe_catalog[k], {
      pe_name  = "${local.prefix}-pe-stg-${k}"
      psc_name = "${local.prefix}-psc-stg-${k}"
    })
    if enabled && contains(keys(local.pe_catalog), k)
  } : {}

  dns_cfg = try(var.private.dns, {})

  dns_rg_name_legacy = try(local.dns_cfg.resource_group_name, null)

  dns_rg_create = local.private_enabled && try(local.dns_cfg.resource_group.create, false)

  dns_rg_name = coalesce(
    try(local.dns_cfg.resource_group.name, null),
    local.dns_rg_name_legacy,
    local.rg_name
  )

  dns_rg_loc = coalesce(
    try(local.dns_cfg.resource_group.location, null),
    local.rg_loc
  )

  dns_resource_group_name = local.dns_rg_name

  dns_zone_exists = {
    for k, v in local.pe_services_enabled :
    k => length(try(data.azurerm_resources.private_dns_zones[k].resources, [])) > 0
  }

  dns_zone_id_existing = {
    for k, v in local.pe_services_enabled :
    k => local.dns_zone_exists[k] ? data.azurerm_resources.private_dns_zones[k].resources[0].id : null
  }

  dns_zone_should_create = {
    for k, v in local.pe_services_enabled :
    k => (local.dns_create_zone && !local.dns_zone_exists[k])
  }

  vnet_link_exists = {
    for k, v in local.pe_services_enabled :
    k => length(try(data.azurerm_resources.private_dns_vnet_links[k].resources, [])) > 0
  }

  vnet_link_should_create = {
    for k, v in local.pe_services_enabled :
    k => (local.dns_create_vnet_link && !local.vnet_link_exists[k])
  }

  private_dns_zone_id = {
    for k, v in local.pe_services_enabled :
    k => local.dns_zone_exists[k]
      ? local.dns_zone_id_existing[k]
      : try(azurerm_private_dns_zone.this[k].id, null)
  }

  pe_rg_name = local.private_enabled ? var.private_endpoint.resource_group_name : null
  pe_rg_loc  = local.private_enabled ? coalesce(try(var.private_endpoint.location, null), local.rg_loc) : null
}

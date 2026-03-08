variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "storage" {
  description = "Storage Account configuration."
  type = object({
    name        = optional(string)
    name_suffix = optional(string, "001")

    account_kind             = optional(string, "StorageV2")
    account_tier             = optional(string, "Standard")
    account_replication_type = optional(string, "LRS")
    access_tier              = optional(string, "Hot")

    public_network_access_enabled   = optional(bool, false)
    allow_nested_items_to_be_public = optional(bool, false)
    shared_access_key_enabled       = optional(bool, true)
    min_tls_version                 = optional(string, "TLS1_2")
    https_traffic_only_enabled      = optional(bool, true)

    is_hns_enabled = optional(bool, false)
    nfsv3_enabled  = optional(bool, false)
  })
}

variable "containers" {
  description = "Blob containers to create."
  type = list(object({
    name        = string
    access_type = optional(string, "private")
  }))
  default = []
}

variable "file_shares" {
  description = "File shares to create."
  type = list(object({
    name     = string
    quota_gb = optional(number, 100)
  }))
  default = []
}

variable "private" {
  type = object({
    enabled = bool

    endpoints = optional(map(bool), {
      blob = true
      file = true
    })

    pe_subnet_id = optional(string)
    vnet_id      = optional(string)

    dns = optional(object({
      create_zone      = optional(bool, true)
      create_vnet_link = optional(bool, true)

      resource_group = optional(object({
        create   = bool
        name     = string
        location = optional(string)
      }))

      resource_group_name = optional(string)
    }), {})
  })
}

variable "private_endpoint" {
  description = "Where to place Private Endpoints (RG/location). Only required when private.enabled = true."
  type = object({
    resource_group_name = string
    location            = optional(string)
  })
  default = null
}

variable "network_rules" {
  description = "Network rules for storage account. Only applies when public_network_access_enabled = true."
  type = object({
    default_action             = optional(string, "Allow")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

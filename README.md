# terraform-azure-storage

Terraform module for creating and managing Azure Storage Accounts with blob containers, file shares, and private endpoints with automatic DNS zone management.

This module provides a comprehensive solution for Azure Storage infrastructure with enterprise-grade security through private endpoints and automatic private DNS zone configuration.

## Features

- **Storage Account Management**: Create storage accounts with customizable configurations
- **Blob Containers**: Create and manage multiple blob containers
- **File Shares**: Create and manage Azure File Shares with quota configuration
- **Private Endpoints**: Automatic private endpoint creation for blob and file services
- **Private DNS Zones**: Automatic creation and management of private DNS zones
- **DNS Zone Auto-Discovery**: Reuses existing DNS zones when available
- **VNet Link Management**: Automatic VNet linking to private DNS zones
- **Network Rules**: Optional network access rules with service bypass and IP whitelisting
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support
- **Secure by Default**: Public access disabled by default, HTTPS-only traffic enforced
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)

## Usage

### Example 1 — Non-Prod (Public Access, Simple Config)

A simple storage account for development with public access and network rules.

```hcl
module "storage" {
  source = "./modules/storage"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = true
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "infrastructure"
    environment = "development"
  }

  storage = {
    account_tier             = "Standard"
    account_replication_type = "LRS"
    access_tier              = "Hot"

    public_network_access_enabled = true
  }

  containers = [
    {
      name = "data"
    },
    {
      name = "logs"
    }
  ]

  file_shares = [
    {
      name     = "shared"
      quota_gb = 100
    }
  ]

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [
      "203.0.113.0/24",
      "198.51.100.10"
    ]
  }

  private = {
    enabled = false
  }
}
```

### Example 2 — Production (Private Endpoints, Data Lake, GRS)

A production storage account with private endpoints, Data Lake Gen2 enabled, and geo-redundant replication.

```hcl
module "storage" {
  source = "./modules/storage"

  name = "contoso-prod-aue-data"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-data-001"
    location = "australiaeast"
  }

  tags = {
    project     = "data-platform"
    environment = "production"
    compliance  = "pci-dss"
  }

  storage = {
    account_tier             = "Standard"
    account_replication_type = "GRS"
    access_tier              = "Hot"

    # Security settings
    public_network_access_enabled   = false
    allow_nested_items_to_be_public = false
    shared_access_key_enabled       = true
    min_tls_version                 = "TLS1_2"
    https_traffic_only_enabled      = true

    # Advanced features
    is_hns_enabled = true  # Hierarchical namespace for Data Lake Gen2
    nfsv3_enabled  = false
  }

  containers = [
    {
      name        = "raw-data"
      access_type = "private"
    },
    {
      name        = "processed-data"
      access_type = "private"
    },
    {
      name        = "archive"
      access_type = "private"
    }
  ]

  file_shares = [
    {
      name     = "shared-files"
      quota_gb = 500
    },
    {
      name     = "backups"
      quota_gb = 1000
    }
  ]

  # Private endpoint configuration
  private = {
    enabled = true

    endpoints = {
      blob = true
      file = true
    }

    pe_subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-pe"
    vnet_id      = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod"

    dns = {
      create_zone      = true
      create_vnet_link = true

      resource_group = {
        create = false
        name   = "rg-contoso-prod-aue-dns-001"
      }
    }
  }

  private_endpoint = {
    resource_group_name = "rg-contoso-prod-aue-data-001"
    location            = "australiaeast"
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/platform.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"
  pe_subnet_name: "snet-stg-pe"

platform:
  storages:
    appdata:
      name: managed-services-lab-aue-stg

      tags:
        costCenter: "staging"
        owner: "platform"

      resource_group:
        create: true
        name: "rg-storage-lab-aue-stg-001"
        location: australiaeast

      storage:
        name_suffix: "001"
        account_kind: "StorageV2"
        account_tier: "Standard"
        account_replication_type: "LRS"
        access_tier: "Hot"
        public_network_access_enabled: false
        allow_nested_items_to_be_public: false
        shared_access_key_enabled: true
        min_tls_version: "TLS1_2"
        https_traffic_only_enabled: true
        is_hns_enabled: false
        nfsv3_enabled: false

      containers:
        - name: "app"
          access_type: "private"

      file_shares:
        - name: "files"
          quota_gb: 200

      private:
        enabled: true
        endpoints:
          blob: true
          file: true
        dns:
          create_zone: true
          create_vnet_link: true
          resource_group:
            create: true
            name: "rg-dns-services-lab-aue-001"
            location: australiaeast

    sharedfiles:
      name: managed-services-lab-aue-files

      resource_group:
        create: false
        name: "rg-storage-lab-aue-stg-001"
        location: australiaeast

      storage:
        name_suffix: "001"
        account_replication_type: "ZRS"
        public_network_access_enabled: true

      file_shares:
        - name: "shared"
          quota_gb: 500

      private:
        enabled: false
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

# Filter virtual network and subnet for Private Endpoint (PE)
data "azurerm_resource_group" "network" {
  name = local.workspace.network_lookup.resource_group_name
}

data "azurerm_virtual_network" "this" {
  name                = local.workspace.network_lookup.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

data "azurerm_subnet" "pe" {
  name                 = local.workspace.network_lookup.pe_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_resource_group.network.name
}

module "storage" {
  for_each = try(local.workspace.platform.storages, {})

  source = "./modules/storage"

  name           = each.value.name
  tags           = try(each.value.tags, {})
  resource_group = each.value.resource_group

  storage     = each.value.storage
  containers  = try(each.value.containers, [])
  file_shares = try(each.value.file_shares, [])

  private = merge(
    try(each.value.private, { enabled = false }),
    try(each.value.private, {}).enabled == true ? {
      pe_subnet_id = data.azurerm_subnet.pe.id
      vnet_id      = data.azurerm_virtual_network.this.id
    } : {}
  )

  private_endpoint = {
    resource_group_name = data.azurerm_resource_group.network.name
    location            = data.azurerm_resource_group.network.location
  }

  diagnostics = try(each.value.diagnostics, {})
}
```

## Storage Account Naming

Storage account names must be:
- Between 3 and 24 characters
- Lowercase letters and numbers only
- Globally unique across Azure

The module automatically generates names based on the prefix:
```
st{name_sanitized}{suffix}
```

Example: `stcontosoprodauedata001`

You can override with a custom name:
```hcl
storage = {
  name = "mystorageaccount123"
}
```

## Private Endpoints

### Supported Services

The module supports private endpoints for:
- **blob**: Blob storage (`privatelink.blob.core.windows.net`)
- **file**: Azure Files (`privatelink.file.core.windows.net`)

### DNS Zone Management

The module provides flexible DNS zone management:

1. **Auto-create DNS zones** (default):
```hcl
dns = {
  create_zone      = true
  create_vnet_link = true
}
```

2. **Use existing DNS zones**:
```hcl
dns = {
  create_zone      = false  # Module will discover existing zones
  create_vnet_link = false
  resource_group = {
    create = false
    name   = "rg-shared-dns"
  }
}
```

3. **Create zones, use existing VNet links**:
```hcl
dns = {
  create_zone      = true
  create_vnet_link = false  # Link already exists
}
```

### Private Endpoint Resource Group

Private endpoints can be placed in a different resource group:

```hcl
private_endpoint = {
  resource_group_name = "rg-network-endpoints"
  location            = "australiaeast"
}
```

## Container Access Types

Blob containers support three access levels:

```hcl
containers = [
  {
    name        = "public-container"
    access_type = "container"  # Full public read access
  },
  {
    name        = "blob-public"
    access_type = "blob"       # Public read access for blobs only
  },
  {
    name        = "secure-data"
    access_type = "private"    # No public access (default)
  }
]
```

## File Share Configuration

```hcl
file_shares = [
  {
    name     = "small-share"
    quota_gb = 100  # 100 GB quota
  },
  {
    name     = "large-share"
    quota_gb = 5120  # 5 TB quota
  }
]
```

## Replication Types

| Type | Description | Use Case |
|------|-------------|----------|
| `LRS` | Locally Redundant Storage | Cost-effective, single datacenter |
| `ZRS` | Zone Redundant Storage | High availability within region |
| `GRS` | Geo-Redundant Storage | Disaster recovery across regions |
| `GZRS` | Geo-Zone Redundant Storage | Highest durability and availability |
| `RA-GRS` | Read-Access GRS | GRS with read access to secondary |
| `RA-GZRS` | Read-Access GZRS | GZRS with read access to secondary |

## Storage Account Tiers

| Tier | Performance | Use Case |
|------|-------------|----------|
| `Standard` | Standard performance | General purpose storage |
| `Premium` | High performance | Low latency workloads |

**Note**: Premium tier requires specific account kinds:
- `BlockBlobStorage` for block blobs
- `FileStorage` for file shares
- `StorageV2` for general purpose v2

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- Storage Account: `st{name_sanitized}001`
- Private Endpoint: `pe-blob-st{name_sanitized}001`
- Private Service Connection: `psc-blob-st{name_sanitized}001`

## Tags

The module automatically applies default tags and merges with custom tags:

**Default tags** (applied automatically):
- `name`: from var.name
- `managedBy`: "terraform"

**Custom tags** (merged):
```hcl
tags = {
  project     = "data-platform"
  cost_center = "12345"
  compliance  = "pci-dss"
}
```

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | The name of the resource group |
| `storage_account` | Storage account object with id and name |
| `private_dns` | Private DNS zones information (if private endpoints enabled) |
| `private_endpoints` | Map of private endpoints (if enabled) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `storage` | Storage account configuration | object | yes |
| `private` | Private endpoint configuration | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `containers` | List of blob containers to create | list(object) | no |
| `file_shares` | List of file shares to create | list(object) | no |
| `private_endpoint` | Private endpoint resource group placement | object | no |
| `network_rules` | Network access rules | object | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |

### Detailed Input Specifications

#### storage

```hcl
object({
  name        = optional(string)      # Override auto-generated name
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

  is_hns_enabled = optional(bool, false)  # Data Lake Gen2
  nfsv3_enabled  = optional(bool, false)  # NFSv3 support
})
```

#### containers

```hcl
list(object({
  name        = string
  access_type = optional(string, "private")  # private, blob, or container
}))
```

#### file_shares

```hcl
list(object({
  name     = string
  quota_gb = optional(number, 100)
}))
```

#### private

```hcl
object({
  enabled = bool

  endpoints = optional(map(bool), {
    blob = true
    file = true
  })

  pe_subnet_id = optional(string)  # Required if enabled = true
  vnet_id      = optional(string)  # Required if enabled = true

  dns = optional(object({
    create_zone      = optional(bool, true)
    create_vnet_link = optional(bool, true)

    resource_group = optional(object({
      create   = bool
      name     = string
      location = optional(string)
    }))
  }), {})
})
```

#### network_rules

```hcl
object({
  default_action             = optional(string, "Allow")
  bypass                     = optional(list(string), ["AzureServices"])
  ip_rules                   = optional(list(string), [])
  virtual_network_subnet_ids = optional(list(string), [])
})
```

#### private_endpoint

```hcl
object({
  resource_group_name = string
  location            = optional(string)
})
```

## Best Practices

1. **Security First**: Keep `public_network_access_enabled = false` for production
2. **TLS Version**: Always use `min_tls_version = "TLS1_2"` or higher
3. **Replication**: Choose replication type based on RPO/RTO requirements
4. **Private Endpoints**: Use private endpoints for all production workloads
5. **DNS Management**: Use centralized DNS resource group for multiple storage accounts
6. **Naming**: Let the module auto-generate names to ensure consistency
7. **Tagging**: Always include compliance and cost allocation tags
8. **Quotas**: Set appropriate file share quotas based on actual needs

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

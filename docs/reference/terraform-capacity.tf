# Illustrative Terraform — the shared Fabric capacity. fabric-ops, 2026-11-11.
# Not applied from this repo, and not runnable as written. Values marked PLACEHOLDER are unknown.
#
# One F SKU serves dev, test and prod (ADR 0004). Capacity Admin stays with named humans;
# sp-fabric-admin gets capacity Contributor so it can assign workspaces, and nothing else.

terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # VERIFY: the first azurerm release that ships azurerm_fabric_capacity —
                         # check the provider registry changelog, not the version seen in an example.
    }
  }
}

provider "azurerm" {
  features {}
  # Auth arrives as ARM_* environment variables from the pipeline's federated service connection.
  # No client secret is stored anywhere.
}

resource "azurerm_resource_group" "fabric" {
  name     = "rg-fabric-sales-forecast-shared" # shared: the capacity outlives the environments
  location = var.location                      # PLACEHOLDER: the tenant's Fabric region
  tags     = local.tags
}

# VERIFY: the attribute names below are from memory, not from the azurerm registry docs.
# Check azurerm_fabric_capacity (sku block, administration_members) before applying.
resource "azurerm_fabric_capacity" "shared" {
  name                = "fabric-sales-forecast-shared" # PLACEHOLDER: domain/project still to settle
  resource_group_name = azurerm_resource_group.fabric.name
  location            = azurerm_resource_group.fabric.location

  sku {
    name = var.capacity_sku # F2 | F4 | ... | F2048 — PLACEHOLDER: sizing follows peak load of the
    tier = "Fabric"         # largest environment, per ADR 0004; not yet measured
  }

  # Named humans only. A group here would make everyone in it a capacity administrator.
  administration_members = var.capacity_admin_upns # PLACEHOLDER list; never the service principals

  tags = local.tags
}

locals {
  tags = {
    managed-by  = "terraform"
    environment = "shared" # the capacity is deliberately env-less (see naming.md)
    repo        = "PLACEHOLDER-work-repo"
  }
}

variable "location" {
  type        = string
  description = "Azure region for the capacity. Must be a region Fabric supports."
}

variable "capacity_sku" {
  type        = string
  description = "F SKU size, e.g. F2. Unknown until peak consumption is measured (ADR 0004)."
  default     = "F2" # PLACEHOLDER — smallest SKU is the honest starting point, not a decision
}

variable "capacity_admin_upns" {
  type        = list(string)
  description = "Named humans who administer the capacity."
}

# TODO (workspace assignment): deliberately absent here.
# Assigning a workspace to this capacity is a property of the workspace resource in the
# microsoft/fabric provider (terraform-fabric.tf, `capacity_id`), because azurerm owns the Azure
# resource and fabric owns the workspace side. There is no capacity-assignment resource to write
# in this file — and `fabric_capacity` is a data source only, not a resource (ADR 0003).
# VERIFY: whether fabric_workspace accepts the capacity's Azure resource ID or its Fabric object
# ID; the Fabric docs for the workspace resource name the property, but not the ID form.

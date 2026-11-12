# Illustrative Terraform — the shared Fabric capacity. fabric-ops, 2026-11-11.
# Not applied from this repo, not runnable as written. PLACEHOLDER marks an unknown value.
# One F SKU serves dev, test and prod (ADR 0004). Capacity Admin stays with named humans;
# sp-fabric-admin holds capacity Contributor so it can assign workspaces, and nothing more.

terraform {
  required_version = ">= 1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13" # 5.13.0 is the release that ships azurerm_fabric_capacity (checked 2026-11-12)
    }
  }
}

provider "azurerm" {
  features {}
  # Auth arrives as ARM_* variables from the federated service connection; no secret on disk.
}

resource "azurerm_resource_group" "fabric" {
  name     = "rg-fabric-sales-forecast-shared" # shared: the capacity outlives the environments
  location = var.location                      # PLACEHOLDER: the tenant's Fabric region
  tags     = local.tags
}

# Attribute names confirmed against the azurerm registry docs and the provider's own capacity
# example (2026-11-12). The resource is pinned to API 2023-11-01, so it cannot express capacity
# overage or suspend/resume, and its SKU range stops at F2048 — see the capacity research note.
resource "azurerm_fabric_capacity" "shared" {
  name                = "fabric-sales-forecast-shared" # PLACEHOLDER: domain/project not settled
  resource_group_name = azurerm_resource_group.fabric.name
  location            = azurerm_resource_group.fabric.location

  sku {
    name = var.capacity_sku # F2 | F4 | … | F2048 — PLACEHOLDER: sizing follows peak load of the
    tier = "Fabric"         # largest environment (ADR 0004), and has not been measured
  }

  # Named humans only. A group here would make every member a capacity administrator.
  administration_members = var.capacity_admin_upns # PLACEHOLDER; never the service principals
  tags                   = local.tags
}

locals {
  # "shared" because the capacity is deliberately env-less (see naming.md).
  tags = { managed-by = "terraform", environment = "shared", repo = "PLACEHOLDER-work-repo" }
}

variable "location" { type = string }                  # region Fabric supports
variable "capacity_sku" { default = "F2" }             # PLACEHOLDER: smallest SKU is a start, not a decision
variable "capacity_admin_upns" { type = list(string) } # named humans

# TODO (workspace assignment): deliberately absent. Assigning a workspace is a property of the
# workspace resource in the microsoft/fabric provider (terraform-fabric.tf, `capacity_id`).
# `capacity_id` is a **Fabric GUID**, not this resource's ARM ID — pass the ARM ID and the provider
# rejects it. Resolve it in the workspaces root with `data "fabric_capacity"`; `fabric_capacity` is
# a data source only, never a resource (ADR 0003).

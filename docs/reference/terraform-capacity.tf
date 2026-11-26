# Illustrative Terraform — the platform root: one resource group, one shared Fabric capacity.
# fabric-ops, dated 2026-11-26. Not runnable from this repo and not applied by it (ADR 0001).
# PLACEHOLDER marks a value only the tenant can supply.
#
# Band 1 of the pipeline contract (docs/reference/pipeline-contract.md §2): a single state,
# `platform.tfstate`, applied by `sc-fabric-admin` when the capacity changes and otherwise left
# alone. The capacity outlives every environment, so it belongs here and never in a per-environment
# state (ADR 0004, ADR 0007). Each environment reads it back as `data "fabric_capacity"`.

terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13" # 5.13.0 is the release that ships azurerm_fabric_capacity (checked 2026-11-12)
    }
  }

  # The work repo pins exactly through the committed .terraform.lock.hcl (contract §7); this
  # reference shows the constraint, not the pin. No other provider belongs in this root: adding one
  # here widens the blast radius of the only root that touches the shared capacity.
}

provider "azurerm" {
  features {}

  # Authentication is not in this file. The `sc-fabric-admin` service connection federates into the
  # run and exports ARM_CLIENT_ID / ARM_OIDC_TOKEN / ARM_USE_OIDC, so there is no client secret on
  # disk, in state, or in the pipeline (ADR 0002).
  #
  # subscription_id and tenant_id are passed explicitly rather than inherited from the agent's
  # ambient context, so a plan cannot quietly target the subscription the agent happens to be
  # logged into. VERIFY whether the pipeline supplies both or leans on ARM_SUBSCRIPTION_ID /
  # ARM_TENANT_ID; the two mechanisms must agree.
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# ---------------------------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "platform" {
  name     = var.resource_group_name # rg-fabric-sales-forecast (contract §1)
  location = var.location            # PLACEHOLDER: a region that offers Fabric, not merely Azure
  tags     = local.tags

  # Destroying the group destroys the capacity, and with it every workspace's capacity binding.
  # A guard only fires on a plan someone reads, and it is not recorded in state — so it stops an
  # accidental `destroy`, not a deliberate one. Retirement is a `removed` block, never a deletion
  # of this block (terraform-operating-model.md §3).
  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------
# Shared capacity
# ---------------------------------------------------------------------------------------------

# This resource exposes no argument for capacity overage billing, surge protection, or
# suspend/resume. Those are not managed by Terraform here and should not be imitated with an
# argument that merely looks like it manages them; pausing or resuming is an out-of-band action,
# and the workspaces root guards against applying to a paused capacity with a postcondition on
# `state == "Active"`.
#
# Attribute names below were confirmed against the azurerm registry docs and the provider's own
# capacity example (2026-11-12). The resource wraps ARM API 2023-11-01, whose SKU range stops at
# F2048.
resource "azurerm_fabric_capacity" "shared" {
  name                = var.capacity_name # fabric-sales-forecast-shared (contract §1)
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location

  sku {
    name = var.capacity_sku # F2 | F4 | … | F2048 — PLACEHOLDER: sizing has not been measured
    tier = "Fabric"
  }

  # The admin service principal is made a capacity *administrator*, not a Contributor. The provider
  # documents these entries as "an Entra user or a service principal" (object ID for an SP), and
  # Create Workspace accepts a caller that is "an Admin on the capacity" — so this is the only way
  # to give `sp-fabric-admin` what the pipeline needs without first answering issue #15, "can an SP
  # hold capacity Contributor?".
  #
  # It is deliberately broader than Contributor: an administrator can also assign workspaces,
  # change capacity settings and manage other admins. That breadth is the price of not depending on
  # an unanswered tenant question, and it is the one decision in this file that a reviewer should
  # argue with. A group here would make every member an administrator; list the admin SP
  # (1111…) and only the humans who must administer the capacity (2222…).
  administration_members = var.capacity_admin_object_ids

  tags = local.tags

  # Same caveat as the resource group: deleting this block is not the same as deleting a resource —
  # it bypasses `prevent_destroy` and destroys the capacity. Retire it with
  # `removed { lifecycle { destroy = false } }` instead.
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # "shared" because the capacity is deliberately environment-less (naming.md), and the two tags
  # are the whole of the labelling contract: who owns the object, and that it is not per-environment.
  tags = {
    managed-by  = "terraform"
    environment = "shared"
  }
}

# ---------------------------------------------------------------------------------------------
# Variables — the platform interface from pipeline-contract.md §3, no more and no less
# ---------------------------------------------------------------------------------------------

variable "subscription_id" {
  type        = string
  description = "Subscription that owns the resource group and the capacity. PLACEHOLDER."
}

variable "tenant_id" {
  type        = string
  description = "Entra tenant of the capacity and of every object ID passed in. PLACEHOLDER."
}

variable "location" {
  type        = string
  description = "Azure region for both objects; must be a region Fabric serves. PLACEHOLDER."
}

variable "resource_group_name" {
  type        = string
  default     = "rg-fabric-sales-forecast"
  description = "Fixed by contract §1. Overridable so a pre-existing group can be imported rather than recreated."
}

variable "capacity_name" {
  type        = string
  default     = "fabric-sales-forecast-shared"
  description = "Fixed by contract §1. The environments look this name up, so renaming it breaks every workspaces state."
}

variable "capacity_sku" {
  type        = string
  default     = "F2"
  description = "F2 is the smallest SKU and a starting point, not a sizing decision (ADR 0004). PLACEHOLDER: peak load of the largest environment has not been measured."
}

variable "capacity_admin_object_ids" {
  type        = list(string)
  description = "Entra object IDs made capacity administrators: the admin SP, plus only humans who must administer it. PLACEHOLDER: 1111… for the SP, 2222… for a human."

  # No default on purpose — an omitted list would leave the capacity with no administrator, which
  # is a state the pipeline cannot recover from with its own credentials.
  validation {
    condition     = length(var.capacity_admin_object_ids) > 0
    error_message = "At least one capacity administrator is required; the admin service principal should be one of them."
  }
}

# ---------------------------------------------------------------------------------------------
# Outputs — consumed by the workspaces root as `data "fabric_capacity"`
# ---------------------------------------------------------------------------------------------

output "capacity_name" {
  value       = azurerm_fabric_capacity.shared.name
  description = "Display name the workspaces root looks the capacity up by."
}

output "capacity_arm_id" {
  # The ARM ID, not the Fabric GUID. `fabric_workspace.capacity_id` wants the GUID and rejects this
  # value, which is why the workspaces root resolves the GUID with `data "fabric_capacity"`
  # (`fabric_capacity` is a data source only, never a resource — ADR 0003).
  value       = azurerm_fabric_capacity.shared.id
  description = "ARM resource ID of the capacity; useful for Azure RBAC and for diagnostics, not for Fabric assignment."
}

output "resource_group_name" {
  value       = azurerm_resource_group.platform.name
  description = "Resource group holding the capacity, for runbooks and out-of-band queries."
}

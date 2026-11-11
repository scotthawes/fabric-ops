# Illustrative Terraform — Fabric control plane. fabric-ops, 2026-11-11. Not applied from here.
# Runs as sp-fabric-admin, because role assignments need Member-or-higher and this principal is
# the only one allowed to grant access (ADR 0002, 0006). Items are NOT managed here — fabric-cicd
# deploys those from content/ (ADR 0003).
#
# Every GUID below is a placeholder. Real tenant, group and workspace IDs never enter the repo.

terraform {
  required_version = ">= 1.8"

  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.15" # v1.15.1 seen 2026-11-11. Outside Microsoft support (ADR 0003).
    }
  }
}

provider "fabric" {
  # VERIFY: the auth block shape is a guess. Check the provider's docs/index.md for the current
  # attribute names and which of tenant_id/client_id/oidc are required for a federated principal.
  tenant_id = var.tenant_id          # PLACEHOLDER
  client_id = var.admin_client_id    # sp-fabric-admin — not the deploy principal
  use_oidc  = true
}

locals {
  # No environment token inside item names; the workspace carries it (naming.md).
  workspaces = {
    dev  = "fabric-sales-forecast-dev"
    test = "fabric-sales-forecast-test"
    prod = "fabric-sales-forecast-prod"
  }

  # One Entra security group per workspace, named for the workspace (ADR 0006).
  # Groups carry Contributor or Viewer only; Admin is granted to named humans, not listed here.
  contributor_groups = {
    dev  = "00000000-0000-0000-0000-0000000000d1"
    test = "00000000-0000-0000-0000-0000000000d2"
    prod = "00000000-0000-0000-0000-0000000000d3"
  }

  git_connection_id = "00000000-0000-0000-0000-0000000000c1" # PLACEHOLDER Azure DevOps connection
}

resource "fabric_workspace" "this" {
  for_each = local.workspaces

  display_name = each.value
  description  = "Sales forecast, ${each.key}. Workspace managed by Terraform; items by fabric-cicd."

  # The shared F SKU (ADR 0004). Which ID form this takes is the open question below.
  capacity_id = var.capacity_id # PLACEHOLDER
  # VERIFY: whether capacity_id is the Azure resource ID or the Fabric capacity object ID —
  # check the fabric_workspace resource docs.
}

resource "fabric_workspace_role_assignment" "contributors" {
  for_each = local.workspaces

  workspace_id = fabric_workspace.this[each.key].id
  role         = "Contributor"

  principal {
    id   = local.contributor_groups[each.key]
    type = "Group"
  }
  # VERIFY: nested principal block vs flat principal_id/principal_type attributes, against the
  # fabric_workspace_role_assignment resource docs. The role/principal enums are confirmed
  # (Admin/Member/Contributor/Viewer; User/Group/ServicePrincipal/ServicePrincipalProfile).
}

# Git integration on dev only. test and prod are deployment targets with no way in but the
# pipeline, so a portal edit there is overwritten rather than resurrected into the repo (ADR 0005).
resource "fabric_workspace_git" "dev" {
  workspace_id            = fabric_workspace.this["dev"].id
  initialization_strategy = "PreferRemote" # VERIFY: allowed values, per the fabric_workspace_git docs
  git_provider_type       = "AzureDevOps"  # VERIFY: exact enum spelling

  git_credentials {
    source        = "ConfiguredConnection"
    connection_id = local.git_connection_id
  }

  # VERIFY: the git_repository block (organisation, project, repository, branch, directory) —
  # field names are not established by the research note, only that the connection is managed.
  # The branch is the one authors commit out of, not `main`: `main` is what the pipeline deploys.
}

variable "tenant_id" {
  type        = string
  description = "Entra tenant of the work tenant. Not a secret, still not committed."
}

variable "admin_client_id" {
  type        = string
  description = "Application (client) ID of sp-fabric-admin."
}

variable "capacity_id" {
  type        = string
  description = "The shared F SKU created in terraform-capacity.tf."
}

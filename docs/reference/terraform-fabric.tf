# Illustrative Terraform — Fabric control plane. fabric-ops, 2026-11-11. Not applied from here.
# Runs as sp-fabric-admin: role assignments need Member-or-higher, and this is the only principal
# allowed to grant access (ADR 0002, 0006). Items are NOT managed here — fabric-cicd deploys those
# from content/ (ADR 0003). Every GUID below is a placeholder.

terraform {
  required_version = ">= 1.8"
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.15" # v1.15.1 seen 2026-11-11; outside Microsoft support (ADR 0003)
    }
  }
}

provider "fabric" {
  # Verified 2026-11-12: federated auth is supported. use_oidc takes the token from the environment;
  # from an Azure DevOps pipeline, azure_devops_service_connection_id (a GUID) is the documented path.
  # Audience api://AzureADTokenExchange, scope https://api.fabric.microsoft.com/.default.
  tenant_id                         = var.tenant_id       # PLACEHOLDER: the work tenant
  client_id                         = var.admin_client_id # sp-fabric-admin — not the deploy principal
  use_oidc                          = true
  azure_devops_service_connection_id = var.ado_service_connection_id # PLACEHOLDER
}

# capacity_id is a Fabric GUID, not the ARM ID of the azurerm_fabric_capacity resource. Resolve it
# here and assert the capacity is running, so a paused capacity fails loudly instead of drifting.
data "fabric_capacity" "shared" {
  display_name = "fabric-sales-forecast-shared" # PLACEHOLDER: matches naming.md

  postcondition {
    condition     = self.state == "Active"
    error_message = "Shared capacity is ${self.state}; resume it before applying (ADR 0004)."
  }
}

locals {
  # No environment token inside item names; the workspace carries it (naming.md).
  workspaces = {
    dev  = "fabric-sales-forecast-dev"
    test = "fabric-sales-forecast-test"
    prod = "fabric-sales-forecast-prod"
  }

  # One Entra group per workspace (ADR 0006): Contributor or Viewer only; Admin goes to humans.
  contributor_groups = {
    dev  = "00000000-0000-0000-0000-0000000000d1"
    test = "00000000-0000-0000-0000-0000000000d2"
    prod = "00000000-0000-0000-0000-0000000000d3"
  }

  git_connection_id = "00000000-0000-0000-0000-0000000000c1" # PLACEHOLDER ADO connection
}

resource "fabric_workspace" "this" {
  for_each     = local.workspaces
  display_name = each.value
  description  = "Sales forecast, ${each.key}. Container from Terraform; items from fabric-cicd."
  capacity_id  = data.fabric_capacity.shared.id # a Fabric GUID, never the ARM resource ID
}

resource "fabric_workspace_role_assignment" "contributors" {
  for_each     = local.workspaces
  workspace_id = fabric_workspace.this[each.key].id
  role         = "Contributor"

  principal {
    id   = local.contributor_groups[each.key]
    type = "Group"
  }
  # VERIFY: nested principal block vs flat principal_id/principal_type, per the resource docs.
}

# Git integration on dev only: test and prod are deployment targets whose only way in is the
# pipeline, so a portal edit there is overwritten rather than resurrected into the repo (ADR 0005).
resource "fabric_workspace_git" "dev" {
  workspace_id            = fabric_workspace.this["dev"].id
  initialization_strategy = "PreferRemote" # VERIFY: allowed values, per the resource docs
  git_provider_type       = "AzureDevOps"  # VERIFY: exact enum spelling

  git_credentials {
    source        = "ConfiguredConnection"
    connection_id = local.git_connection_id
  }
  # VERIFY: the git_repository block (project/repository/branch) — field names are not established
  # by the research note. The branch is the one authors commit out of, not `main`.
}

variable "tenant_id" { type = string }       # work tenant; not a secret, still not committed
variable "admin_client_id" { type = string } # sp-fabric-admin application ID

# Illustrative Terraform — the **workspaces root**, one environment per apply. fabric-ops, 2026-11-26.
# Not runnable from this repo and not a manifest (ADR 0001). PLACEHOLDER marks an unknown value;
# VERIFY marks a schema that was not confirmed against provider docs.
#
# ONE environment per apply, selected by `var.environment` (state key + tfvars file). There is no
# for_each over dev/test/prod: an apply must not be able to reach another environment's workspace,
# and a plan must not contain all three (ADR 0007 — one root, one state key per environment).
# Applies in order dev -> test -> prod; needs a lock only on its own blob, so environments run
# concurrently. Runs as sp-fabric-admin (sc-fabric-admin). Items are NOT here: fabric-cicd owns
# them (ADR 0003). The capacity is NOT here: platform.tfstate owns it (ADR 0004).
#
# Order inside the root is forced by references, not taste:
#   capacity (data) -> groups -> workspace + identity -> group assignments
#   -> identity workspace grant -> storage RBAC -> [resource instance rule] -> [dev Git binding]

terraform {
  required_version = ">= 1.8"

  required_providers {
    fabric = {
      source = "microsoft/fabric"
      # Exact pin: v1.15.1 verified 2026-11-11. A minor shipped a breaking change (v1.6.0), so a
      # range is not a pin. Commit .terraform.lock.hcl in the work repo (ADR 0007).
      version = "= 1.15.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13" # used here only for the identity's Storage Blob Data Contributor grant
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.1" # groups as code; VERIFY the minor current at build time
    }
    # azapi is needed ONLY for the commented resource-instance-rule hatch in §11. Declaring it in
    # this root does not turn anything on; uncomment with that block.
    # azapi = {
    #   source  = "Azure/azapi"
    #   version = "~> 2.0"
    # }
  }

  backend "azurerm" {
    # Federated auth: no storage account key, no secret. The applying app needs Storage Blob Data
    # Contributor on the container — "recommended for least privilege" in the azurerm backend docs.
    #
    # A backend block cannot use variables, so this is a *partial* configuration: the pipeline
    # supplies the rest at init, which is what makes one root serve three states:
    #
    #   terraform init \
    #     -backend-config="tenant_id=$ARM_TENANT_ID" \
    #     -backend-config="subscription_id=$ARM_SUBSCRIPTION_ID" \
    #     -backend-config="storage_account_name=PLACEHOLDER" \
    #     -backend-config="container_name=tfstate" \
    #     -backend-config="key=workspaces/dev.tfstate"
    #
    # One blob per environment => one lock per environment. A dev apply cannot block a prod apply,
    # which is the concurrency property the pipeline needs. NEVER share this key across stages.
    use_azuread_auth = true
    use_oidc         = true
  }
}

# ---------------------------------------------------------------------------------------------
# Providers — both authenticate as the federated admin app, never with a secret on disk.
# ---------------------------------------------------------------------------------------------

provider "fabric" {
  tenant_id                          = var.tenant_id
  client_id                          = var.admin_client_id # sp-fabric-admin, not the deploy principal
  use_oidc                           = true
  azure_devops_service_connection_id = var.ado_service_connection_id # GUID, not a connection name

  # Audience api://AzureADTokenExchange, scope https://api.fabric.microsoft.com/.default.
  # In an AzureCLI@2 job the connection ID is already AZURESUBSCRIPTION_SERVICE_CONNECTION_ID,
  # surfaced to the provider as FABRIC_AZURE_DEVOPS_SERVICE_CONNECTION_ID.
}

provider "azuread" {
  tenant_id = var.tenant_id
  client_id = var.admin_client_id
  use_oidc  = true
  # Federated: the token is exchanged for an ADO assertion, no client secret exists anywhere.
  # This is the azuread provider's own argument name — `oidc_azure_service_connection_id` is an
  # azurerm spelling, and using it here fails at provider configuration.
  ado_pipeline_service_connection_id = var.ado_service_connection_id
}

provider "azurerm" {
  features {}
  # Only the storage RBAC grant needs ARM; the Fabric resources do not.
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# ---------------------------------------------------------------------------------------------
# 1. The shared capacity, read back as a Fabric GUID (never the ARM resource ID).
# ---------------------------------------------------------------------------------------------

data "fabric_capacity" "shared" {
  display_name = var.capacity_name # from the platform stage output / tfvars

  # A paused or inactive capacity is the one drift the provider admits it cannot see: applying
  # against it can remove state entries. Fail before touching anything.
  postcondition {
    condition     = self.state == "Active"
    error_message = "Shared capacity '${self.display_name}' is ${self.state}; resume it before applying (ADR 0004)."
  }
}

# ---------------------------------------------------------------------------------------------
# 2. Entra groups, built as code in this root so the role assignment has a real resource edge.
#    This is the requested destination; it amends ADR 0010 §2 and costs directory write.
# ---------------------------------------------------------------------------------------------

data "azuread_client_config" "current" {}

resource "azuread_group" "this" {
  for_each = var.groups # keys are `contributors` / `viewers`; the key becomes part of the name

  # <workspace>-<role> per naming.md, so one Entra search finds the group (ADR 0006).
  display_name = "${var.workspace_name}-${each.key}"
  description  = "Workspace ${each.value.role} group for ${var.workspace_name} (ADR 0006)."

  security_enabled = true
  # Owners as humans: the applying SP needs Graph User.Read.All on top of Group.Create. An empty
  # list is not the same as omitting the argument — "groups cannot be created with no owners" — so
  # fall back to the applying principal, which is the provider's documented default.
  owners = length(each.value.owners) > 0 ? toset(each.value.owners) : toset([data.azuread_client_config.current.object_id])

  # Group display names are NOT unique in Entra. Without this, a second group with the same name
  # is allowed and every name-based lookup becomes ambiguous (ADR 0010 §2).
  prevent_duplicate_names = true

  lifecycle {
    # The group outlives a workspace rebuild. Destroying it would churn the object ID every
    # assignment, data source and access review points at.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------
# 3. The workspace container. Identity is a property of this resource in Terraform even though
#    Fabric provisions it with a separate POST — the provider hides the ordering.
# ---------------------------------------------------------------------------------------------

resource "fabric_workspace" "this" {
  display_name = var.workspace_name # PLACEHOLDER via tfvars; unique in the tenant by API rule
  description  = var.workspace_description
  capacity_id  = data.fabric_capacity.shared.id # Fabric GUID; the ARM ID is rejected here

  # VERIFY: dynamic block support for `identity`, and whether the block can be added to or removed
  # from an existing workspace in place. The schema shows no ForceNew; that is not proof.
  dynamic "identity" {
    for_each = var.enable_workspace_identity ? [1] : []
    content {
      type = "SystemAssigned" # the only supported value
    }
  }

  lifecycle {
    prevent_destroy = true
    # Restore from soft delete does NOT restore the identity: new app and SP IDs, so every Azure
    # RBAC assignment and connection that referenced the old one is stale. Never destroy in prod;
    # retire by deleting this block only alongside a `removed { lifecycle { destroy = false } }`
    # hand-off, because removing a block bypasses prevent_destroy (operating model §3).
  }
}

# ---------------------------------------------------------------------------------------------
# 4. Workspace roles, one resource per group. The reference builds the edge
#    group -> workspace -> assignment, so a missing group fails plan rather than apply.
# ---------------------------------------------------------------------------------------------

resource "fabric_workspace_role_assignment" "groups" {
  for_each = var.groups

  workspace_id = fabric_workspace.this.id
  role         = each.value.role # Contributor | Viewer — never Admin (ADR 0006)

  # VERIFY: nested `principal` block vs flat principal_id/principal_type. The provider documents
  # principal.id as the Entra object ID and principal.type as Group/ServicePrincipal/User.
  principal {
    id   = azuread_group.this[each.key].object_id
    type = "Group"
  }
}

# ---------------------------------------------------------------------------------------------
# 5. Optional: the workspace identity's own workspace role. Trusted workspace access expects
#    Contributor; without a role the identity can hold storage permissions and still get no token.
# ---------------------------------------------------------------------------------------------

resource "fabric_workspace_role_assignment" "identity" {
  count = var.enable_workspace_identity ? 1 : 0

  workspace_id = fabric_workspace.this.id
  role         = "Contributor"

  # A DIRECT service-principal grant, which ADR 0006 refuses for people. The exception is written
  # down rather than inferred: this principal is a workload owned by the workspace, has no human
  # membership to delegate, and its life must end with the workspace. The deploy SP still needs its
  # own role for Fabric to issue this identity's token to scheduled runs (workspace-identity §6).
  principal {
    id   = fabric_workspace.this.identity[0].service_principal_id
    type = "ServicePrincipal"
  }
}

# ---------------------------------------------------------------------------------------------
# 6. Optional: Azure RBAC for the identity on a firewall-enabled storage account. The role must be
#    at storage-account scope; a folder-level grant does not satisfy trusted workspace access.
# ---------------------------------------------------------------------------------------------

resource "azurerm_role_assignment" "identity_storage" {
  count = var.enable_workspace_identity && var.identity_storage_account_id != "" ? 1 : 0

  scope                = var.identity_storage_account_id # ARM ID, passed in; never an ambient name
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = fabric_workspace.this.identity[0].service_principal_id
}

# ---------------------------------------------------------------------------------------------
# 7. ILLUSTRATIVE ONLY — NOT ACTIVE. Resource instance rule (network path) for that storage.
#
#    Neither azurerm_storage_account nor azurerm_storage_account_network_rules documents
#    `resource_access_rules` (checked 2026-11-12), so there is no typed resource for this field.
#    The rule names the WORKSPACE, not the identity, and the subscription segment is all-zero by
#    design. Maximum 200 rules per account. An azapi destroy is a no-op: the rule stays live while
#    state forgets it, so this is a field hatch with one named owner, not an object.
#
# resource "azapi_update_resource" "storage_resource_instance_rule" {
#   count = var.identity_storage_account_id != "" ? 1 : 0
#
#   resource_id = var.identity_storage_account_id
#   type        = "Microsoft.Storage/storageAccounts@2023-05-01" # VERIFY the api-version
#
#   # VERIFY the body schema: properties.networkAcls.resourceAccessRules, element shape
#   # { tenantId, resourceId }. Read back the live account before trusting this to merge rather
#   # than replace the existing networkAcls.
#   body = {
#     properties = {
#       networkAcls = {
#         resourceAccessRules = [
#           {
#             tenantId   = var.tenant_id
#             resourceId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/PLACEHOLDER/providers/Microsoft.Fabric/workspaces/${fabric_workspace.this.id}"
#           }
#         ]
#       }
#     }
#   }
# }

# ---------------------------------------------------------------------------------------------
# 8. Dev only: the Git binding. `bind_git = false` everywhere else — test and prod are deployment
#    targets whose only way in is the pipeline, so a portal edit is overwritten, not resurrected.
# ---------------------------------------------------------------------------------------------

resource "fabric_workspace_git" "dev" {
  count = var.bind_git ? 1 : 0

  workspace_id = fabric_workspace.this.id

  # PreferWorkspace, NOT PreferRemote: adopting must never overwrite the workspace's items from
  # the branch. This resource is not importable, so adoption runs the create path, and the create
  # path commits or updates on the returned requiredAction (operating model §3).
  initialization_strategy = "PreferWorkspace"
  git_provider_type       = "AzureDevOps"

  git_credentials {
    source        = "ConfiguredConnection" # required since v1.6.0, with connection_id
    connection_id = "00000000-0000-0000-0000-000000000000" # PLACEHOLDER ADO connection GUID
  }

  # VERIFY: the repository block field names and whether `directory_name` is required. Plausible
  # from the provider's Terraform docs, not confirmed by the research note.
  git_repository {
    organization_name = "PLACEHOLDER-org"
    project_name      = "PLACEHOLDER-project"
    repository_name   = "PLACEHOLDER-work-repo"
    branch_name       = "PLACEHOLDER-authoring-branch" # the branch authors commit out of, not main
    directory_name    = "/"
  }

  # A binding created by Terraform both binds AND syncs; it is a writer, not a passive pointer.
  # Grant order matters: the deploy SP needs its workspace role before the first content run.
}

# ---------------------------------------------------------------------------------------------
# Variables — exactly the contract's interface (§3), plus what the backend and providers need.
# ---------------------------------------------------------------------------------------------

variable "environment" {
  type        = string
  description = "dev | test | prod. Selects the state key and the tfvars file; one per apply."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of dev, test, prod."
  }
}

variable "workspace_name" {
  type        = string
  description = "From naming.md: fabric-<domain>-<project>-<env>."
}

variable "workspace_description" {
  type        = string
  default     = "Sales forecast. Container from Terraform; items deployed by fabric-cicd."
  description = "Optional; describe the container, not the items."
}

variable "capacity_name" {
  type        = string
  description = "Shared capacity display name, from the platform stage output."
}

variable "groups" {
  type = map(object({
    role   = string
    owners = list(string) # Entra object IDs of the human owners; [] means the SP is sole owner
  }))
  description = "Map key becomes the group name suffix; role is Contributor or Viewer only."

  # Example tfvars (env/dev.tfvars), PLACEHOLDER object IDs:
  # groups = {
  #   contributors = { role = "Contributor", owners = ["11111111-1111-1111-1111-111111111111"] }
  #   viewers      = { role = "Viewer",      owners = ["22222222-2222-2222-2222-222222222222"] }
  # }
  # An empty owners list falls back to the applying service principal, not to a group with no owner.
}

variable "enable_workspace_identity" {
  type        = bool
  default     = true
  description = "System-assigned workspace identity. Restore from soft delete does not bring it back."
}

variable "identity_storage_account_id" {
  type        = string
  default     = ""
  description = "ARM ID of a firewall-enabled storage account; empty when there is none."
}

variable "bind_git" {
  type        = bool
  default     = false
  description = "true only in dev (ADR 0005). test and prod stay unbound."
}

# Backend and provider inputs. None is a secret; none is committed with a real value.
variable "tenant_id" {
  type        = string
  description = "Entra tenant. PLACEHOLDER in examples."
}

variable "subscription_id" {
  type        = string
  description = "Subscription holding the state account and capacity. PLACEHOLDER."
}

variable "admin_client_id" {
  type        = string
  description = "sp-fabric-admin application (client) ID — not the deploy principal."
}

variable "ado_service_connection_id" {
  type        = string
  description = "GUID of sc-fabric-admin, not its display name. Not a secret."
}

# storage_account_name and container_name are deliberately NOT variables: a backend block cannot
# read variables, so init supplies them with -backend-config (see the backend comment above).

# ---------------------------------------------------------------------------------------------
# Outputs — exactly the contract's three.
# ---------------------------------------------------------------------------------------------

output "workspace_id" {
  value       = fabric_workspace.this.id
  description = "Fabric workspace GUID, consumed by the content stage."
}

output "workspace_identity_principal_id" {
  # Null-safe: when the identity is disabled the block is absent, so index [0] would error.
  value       = try(fabric_workspace.this.identity[0].service_principal_id, null)
  description = "Service principal object ID of the workspace identity, or null when disabled."
}

output "group_object_ids" {
  value       = { for key, group in azuread_group.this : key => group.object_id }
  description = "contributors/viewers -> Entra object IDs, for reviews and downstream grants."
}

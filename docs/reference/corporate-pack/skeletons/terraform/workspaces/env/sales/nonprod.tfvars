# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only; preflight.py rejects this file
# Pack: 2026-11-26.1 — illustrative skeleton; placeholders only.
# until every PLACEHOLDER and all-zero GUID is replaced.
# State key: workspaces/sales/nonprod.tfstate

domain         = "sales"
environment    = "nonprod"
workspace_name = "fabric-sales-nonprod" # fixed by contract §3

workspace_description = "Sales forecast (nonprod). Container only; items are deployed by fabric-cicd."
capacity_name         = "fabric-capacity-nonprod"

# Three groups, one per role. Owners are Entra object IDs; an empty list falls back to the
# applying service principal. The all-zero GUID here is a PLACEHOLDER and must be replaced.
groups = {
  viewers = {
    role   = "Viewer"
    owners = ["00000000-0000-0000-0000-000000000000"]
  }
  contributors = {
    role   = "Contributor"
    owners = ["00000000-0000-0000-0000-000000000000"]
  }
  members = {
    role   = "Member"
    owners = ["00000000-0000-0000-0000-000000000000"]
  }
}

enable_workspace_identity   = true
identity_storage_account_id = "" # set only when a firewall-enabled storage account exists

# nonprod is the only environment allowed to bind Git (ADR 0005). This resource binds AND syncs.
bind_git = true

tenant_id                 = "00000000-0000-0000-0000-000000000000"
subscription_id           = "00000000-0000-0000-0000-000000000000"
admin_client_id           = "00000000-0000-0000-0000-000000000000"
ado_service_connection_id = "00000000-0000-0000-0000-000000000000"

# Git binding inputs. The repository name is derived (fabric-<domain>-nonprod); these three are
# the organisation, project and ADO connection that bootstrap creates.
ado_organization  = "PLACEHOLDER-org"
ado_project       = "PLACEHOLDER-project"
git_branch        = "main"
git_connection_id = "00000000-0000-0000-0000-000000000000"

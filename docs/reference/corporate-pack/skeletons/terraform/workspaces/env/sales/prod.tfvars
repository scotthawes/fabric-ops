# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only; preflight.py rejects this file
# Pack: 2026-11-27.1 — illustrative skeleton; placeholders only.
# until every PLACEHOLDER and all-zero GUID is replaced.
# State key: workspaces/sales/prod.tfstate

domain         = "sales"
environment    = "prod"
workspace_name = "fabric-sales-prod" # fixed by contract §3

workspace_description = "Sales forecast (prod). Container only; items are deployed by fabric-cicd."
capacity_name         = "fabric-capacity-prod"

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
identity_storage_account_id = ""

# Prod is never Git-bound (ADR 0005). The Git resource precondition fails if this is flipped.
bind_git = false

tenant_id                 = "00000000-0000-0000-0000-000000000000"
subscription_id           = "00000000-0000-0000-0000-000000000000"
admin_client_id           = "00000000-0000-0000-0000-000000000000"
ado_service_connection_id = "00000000-0000-0000-0000-000000000000"

# Present for interface parity; unused while bind_git is false.
ado_organization  = "PLACEHOLDER-org"
ado_project       = "PLACEHOLDER-project"
git_branch        = "main"
git_connection_id = "00000000-0000-0000-0000-000000000000"

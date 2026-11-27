# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only.
# Pack: 2026-11-27.1 — illustrative skeleton; placeholders only.
# State key: assignments/sales.tfstate

# `domain` is the lowercase domain key from config/domains.yaml; the root resolves it against
# the Fabric domain DISPLAY name, case-insensitively. No GUID is committed here.
domain = "sales"

# Workspace GUIDs come from `terraform output workspace_id` in workspaces/sales/<env>.tfstate.
# The all-zero value is a placeholder; preflight.py and the variable validation reject it.
workspace_ids = [
  "00000000-0000-0000-0000-000000000000", # nonprod
  "00000000-0000-0000-0000-000000000000", # prod
]

tenant_id                 = "00000000-0000-0000-0000-000000000000"
admin_client_id           = "00000000-0000-0000-0000-000000000000"
ado_service_connection_id = "00000000-0000-0000-0000-000000000000"

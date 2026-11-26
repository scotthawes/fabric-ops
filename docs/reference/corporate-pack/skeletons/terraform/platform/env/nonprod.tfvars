# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only; preflight.py rejects this file
# Pack: 2026-11-26.2 — illustrative skeleton; placeholders only.
# until every PLACEHOLDER and all-zero GUID is replaced.
# State key for this file: platform/nonprod.tfstate

environment = "nonprod" # one of nonprod | prod

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"

location = "PLACEHOLDER-region" # e.g. uksouth; a real region name, not a display name

# Fixed by contract §3.
capacity_name = "fabric-capacity-nonprod"
# Smallest billable F SKU; enough for container CRUD.
capacity_sku = "F2"

# UPN for a human capacity administrator, object ID for the automation service principal.
# Include sp-fabric-admin or data "fabric_capacity" in the workspaces root will not find it.
capacity_admin_object_ids = [
  "00000000-0000-0000-0000-000000000000",
]

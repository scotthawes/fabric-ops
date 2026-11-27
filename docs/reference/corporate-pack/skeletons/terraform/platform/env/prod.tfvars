# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only; preflight.py rejects this file
# Pack: 2026-11-27.1 — illustrative skeleton; placeholders only.
# until every PLACEHOLDER and all-zero GUID is replaced.
# State key for this file: platform/prod.tfstate

environment = "prod"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"

location = "PLACEHOLDER-region"

# Fixed by contract §3.
capacity_name = "fabric-capacity-prod"
# P1 parity; size up only from Capacity Metrics evidence.
capacity_sku = "F64"

capacity_admin_object_ids = [
  "00000000-0000-0000-0000-000000000000",
]

# Deliberately absent, because this resource cannot express them (see capacity.tf.tmpl):
#   overage state / threshold  -> portal or a separate azapi field hatch, one owner
#   suspend / resume           -> pipeline or CLI action, never while Terraform is applying

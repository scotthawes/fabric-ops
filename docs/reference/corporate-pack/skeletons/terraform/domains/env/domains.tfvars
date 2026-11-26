# corporate-pack 2026-11-26 — ILLUSTRATIVE. Placeholders only; preflight.py rejects this file.
# Pack: 2026-11-26.2 — illustrative skeleton; placeholders only.
# State key: domains.tfstate

# This root is CONDITIONAL on sp-fabric-admin holding Fabric administrator. Leave false (or omit
# the key) until bootstrap has checked it with a real admin API call. Applying with false fails
# at plan, which is the intended behaviour when someone starts the stage by mistake.
fabric_administrator_confirmed = false

tenant_id                 = "00000000-0000-0000-0000-000000000000"
admin_client_id           = "00000000-0000-0000-0000-000000000000"
ado_service_connection_id = "00000000-0000-0000-0000-000000000000"

domains = {
  sales = {
    display_name  = "Sales"
    description   = "Sales domain. PLACEHOLDER."
    parent_domain = ""
    admins = [
      { id = "00000000-0000-0000-0000-000000000000", type = "User" },
    ]
    contributors = [
      { id = "00000000-0000-0000-0000-000000000000", type = "Group" },
    ]
  }

  # Child domains are expressed by key, not by a pre-resolved GUID. Comment out until used:
  # marketing = {
  #   display_name  = "Marketing"
  #   description   = "Marketing domain."
  #   parent_domain = "sales"
  #   admins        = [{ id = "00000000-0000-0000-0000-000000000000", type = "User" }]
  #   contributors  = []
  # }
}

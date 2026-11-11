# Recommendations

Four one-pagers, one per area. Each states the recommendation first and the evidence second, so
a reviewer can disagree with a decision without reading the research.

Read in this order — later ones assume the earlier ones.

| # | Area | Supports |
| --- | --- | --- |
| [01](01-identity-and-access.md) | Identity and access: two federated service principals, four tenant settings, the permission thresholds that surprise people | [ADR 0002](../adr/0002-two-service-principals-federated.md) |
| [02](02-workspace-and-capacity.md) | Workspace and capacity model: one shared SKU, three workspace sets, cost levers, why pause is not a Terraform property | [ADR 0004](../adr/0004-one-shared-capacity.md) |
| [03](03-deployment-and-environments.md) | Deployment and environments: Terraform then `fabric-cicd`, three stages, approval before prod, pinned commit | [ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md), [ADR 0005](../adr/0005-authoring-and-promotion.md) |
| [04](04-users-and-governance.md) | Users and governance: group-based access, what sits below workspace roles, auditing who can see what | [ADR 0006](../adr/0006-access-through-entra-groups.md) |

## What these do not cover

- Anything tenant-specific: which settings are actually on, which SKUs exist, how many workspaces.
  Those are run-book checks ([run-book 01](../runbook/01-work-tenant-checklist.md)), not
  recommendations.
- Cost figures. The pack states what drives cost and what the defaults are; it does not quote
  prices, which change.
- Anything already decided in the work repo. These are inputs to its ADRs, not a substitute.

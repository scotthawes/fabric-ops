# 0003 — Terraform for the control plane, fabric-cicd for items

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott
- **Evidence:** [`deployment-mechanism-comparison.md`](../research/deployment-mechanism-comparison.md)

## Context

No single mechanism covers both halves of the job. Git integration and Fabric deployment
pipelines are workspace-bound and neither carries role assignments; deployment pipelines never
read a repository at all. Item-definition REST (which `fabric-cicd` wraps) deploys items
headlessly but cannot create a workspace, assign a role or set a tenant setting. Terraform
manages workspaces, role assignments, domains, the Git connection and tenant settings, but
`fabric_capacity` is a data source only, item coverage is partial, and Microsoft does not
support the provider under Fabric support policies.

## Decision

- **Control plane → Terraform.** `azurerm_fabric_capacity` for the F SKU (Azure resource),
  `microsoft/fabric` for `fabric_workspace`, `fabric_workspace_role_assignment`,
  `fabric_workspace_git`, `fabric_domain` where used, and `fabric_tenant_setting` for the
  settings the run-book turns on.
- **Items → `fabric-cicd`,** reading definitions in Fabric's source-control format from the
  work repo and deploying per environment.
- **Two pipelines, two service connections,** matching ADR 0002.

## Consequences

- Two lifecycle models to keep coherent: Terraform state for containers, a redeploy-every-run
  model for content. The workspace must exist before items land, so pipeline ordering is a real
  dependency, not a detail.
- If the work tenant uses **workspace-level** private link, this decision does not survive: those
  workspaces cannot hold deployment pipelines or semantic models, and Git APIs are reachable
  only from inside the approved VNet. Tenant-level private link, by contrast, leaves deployment
  pipelines usable.
- `fabric-cicd` deploys everything on every run and does not diff commits, so a portal edit to
  a deployed item is silently overwritten rather than surfaced as drift. Content edits belong
  in the dev workspace, committed through a pull request (ADR 0005).
- Item types with no public create/update definition API cannot be deployed this way: the SQL
  analytics endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model and ML
  experiment are manual-only, and lakehouse tables and workspace settings are not items at all.
  See [`item-type-deployment-coverage.md`](../research/item-type-deployment-coverage.md) before
  promising an item type ships with the pipeline.
- For Warehouse, SQL database and Lakehouse, this deploys the **item shell only** — DDL, tables
  and schemas need a separate step, so a green pipeline can leave an empty warehouse behind.
- **Connectivity is not deployable.** A deployed semantic model or pipeline that reads a gated
  source arrives with no gateway binding and no credentials: the item exists and the report opens,
  but refresh fails with a connection error. Binding is per stage and per item, and must be done by
  a human — see [`gateway-and-connectivity.md`](../research/gateway-and-connectivity.md). This is
  the largest hole in the "everything deploys unattended" assumption and should be stated to
  report authors before the first test deploy.
- The `microsoft/fabric` provider is explicitly outside Microsoft support. When it breaks, the
  fallback is the Core REST API by hand — keep the Terraform small enough that this is cheap.
- Tenant settings in Terraform are tenant-wide. A pipeline that can set them is a
  tenant-administration tool wearing a deployment hat; gate it accordingly.

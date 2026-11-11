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
- `fabric-cicd` deploys everything on every run and does not diff commits, so a portal edit to
  a deployed item is silently overwritten rather than surfaced as drift. Content edits belong
  in the dev workspace, committed through a pull request (ADR 0005).
- Item types with no public create/update definition API cannot be deployed this way. Check the
  item against the supported list before promising it.
- The `microsoft/fabric` provider is explicitly outside Microsoft support. When it breaks, the
  fallback is the Core REST API by hand — keep the Terraform small enough that this is cheap.
- Tenant settings in Terraform are tenant-wide. A pipeline that can set them is a
  tenant-administration tool wearing a deployment hat; gate it accordingly.

# Spec 0003 — Migration pathway: from Azure SQL and ADF to Fabric, with a Databricks gate

- **Status:** synthesis — sequencing for the work repo, not a plan executed here
- **Date:** 2026-11-24
- **Derived from:** [ADR 0011](../adr/0011-fabric-now-databricks-at-a-gate.md), and the research notes
  [`data-stack`](../research/data-stack-which-layers-exist-and-what-replaces-each.md),
  [`tooling`](../research/tooling-which-specialists-earn-their-place-beside-fabric.md),
  [`ingestion`](../research/ingestion-what-is-the-lowest-maintenance-route-from-an-app-database.md),
  [`schema`](../research/schema-and-ddl-management.md),
  [`capacity`](../research/capacity-provisioning-and-cost-control.md)
- **Builds in:** the work repo — **not** this repository, per [ADR 0001](../adr/0001-research-artefact-not-deployment-tool.md)

## Problem Statement

The estate can be migrated in any order, and the wrong order makes the migration look like a
failure. The constraints that decide it:

- **The application database does not move.** It is read, not replaced.
- **Reports depend on the warehouse**, so a warehouse cutover without a data path is a dead end, and
  a data path without a warehouse has nowhere to land.
- **The deployment pipeline is the current bottleneck.** One run rebuilds the factory and the
  infrastructure across all three environments; without per-environment stages, every migration step
  inherits the existing blast radius.
- **The ARM export is a dead end.** Microsoft's ADF migration position is factory-based assessment,
  not ARM-to-item conversion, so the export has to be treated as frozen evidence, not a deliverable.

## Solution

Four phases and a gate. Durations are indicative and assume three delivery engineers; they are
sequencing, not a schedule. Each phase has an exit criterion that can be checked, and a phase does
not start until the previous one's exit is met.

### Phase 0 — Stop the whole-estate rebuild

**Goal:** make every later phase reviewable and reversible.

- Split the shared YAML into one stage per environment, each with its own service connection and
  an approval on production.
- Freeze the ADF ARM export: no new exports, no edits. Record the factory as it stands.
- Decide the capacity: one F SKU, one region, shared by the three environments (ADR 0004).
- Confirm the tenant facts the research could not: private link scope, service-principal licensing,
  gateway type.

**Exit:** a change can reach dev without touching test or prod; a production deploy needs an
approval; the ARM export is read-only.

**Still manual:** nothing new. This phase only removes a failure mode.

### Phase 1 — Land the warehouse

**Goal:** a Fabric Warehouse with the existing schema, deployed from source control, before any data
moves.

- Run the Fabric **Migration Assistant** against a DACPAC of the Azure SQL Database warehouse. Treat
  the incompatible-object list as the scope of repair, not a surprise.
- Stand up the Warehouse, and wire `.sqlproj` + `SqlPackage` into the pipeline with
  `DeployReport` as the drift gate, using `Microsoft.SqlServer.Dacpacs.FabricDw`.
- Reconcile the T-SQL surface: recursive queries, materialized views, synonyms, triggers and
  `CREATE USER` are unsupported; cross-database queries are current-workspace only.
- Keep the Azure SQL Database warehouse running. It is the comparison target.

**Exit:** the schema deploys to an empty Warehouse from the repository, the drift report is clean,
and the incompatible-object list has an owner for each item.

**Open unknowns to test here, not assume:** whether `sqlpackage Publish` is transactional on Fabric
Warehouse, whether `CREATE OR ALTER` executes, and whether `MERGE` tolerates new source columns.

### Phase 2 — Move the data and the pipelines

**Goal:** production data lands in the Warehouse, produced by Fabric pipelines.

- Decide the application-database route with the schema-change test: mirror a stable schema, or copy
  a reporting schema the data team controls.
- Run ADF's built-in **upgrade assessment** against the live factory; migrate pipelines in
  priority order. Mapping Data Flows, SSIS and custom activities are the scoping risk.
- Recreate connections, gateways, schedules and global parameters as Fabric items; they are not
  carried by the item definition.
- Parallel-run: Fabric and the Azure SQL Database warehouse both populated, reports compared.

**Exit:** every production report reads Fabric; the legacy path still runs but is no longer the
source of truth.

**Still manual:** connections, gateway bindings and trigger state are not deployed by `fabric-cicd`.

### Phase 3 — Build the practices

**Goal:** "modern" as a way of working, not a product.

- Git-bound dev workspace, pull-request review, promotion by pinned commit (ADR 0005).
- Item deployment via `fabric-cicd`; Terraform limited to containers and grants.
- Tests where they pay: schema assertions, row-count and freshness checks on the critical marts.
- Catalog hygiene: domains, endorsement, ownership; sensitivity labels where automation allows.
- Capacity operations: Capacity Metrics, an overage threshold, a weekly review with a named owner.
- Access recertification against the 3N Entra groups.

**Exit:** a colleague can add a pipeline or a table and ship it through review without asking a
question; the capacity review has an owner and an alert.

**Deliberately not in this window:** lakehouse-first, Spark notebooks as the primary compute, dbt,
the dbt job, Airflow, an external catalog, streaming, and ML. Each has a trigger in ADR 0011; none
is required to replace the warehouse and ADF.

### The gate

Twelve months after the first production workload — or earlier if a trigger fires — review the
Databricks question against ADR 0011's triggers, with operating evidence: release failures, capacity
figures, query latency, and any funded ML or streaming case. A named platform owner is the
precondition for taking the Databricks branch.

## What this does not establish

- **Durations.** No dates are promised; the phases are ordered, not scheduled.
- **Capacity size.** The SKU depends on volume and concurrency, which are not measured yet.
- **The application-database route.** It turns on schema-change frequency, which is a question for
  the application team.
- **That the migration mechanics work as documented.** Three warehouse behaviours are unverified in
  a tenant (transactional publish, `CREATE OR ALTER`, `MERGE` schema evolution), and the first phase
  tests them rather than assuming them.
- **The ADF inventory.** Pipeline and activity counts, and how many are "Ready" versus
  "Not compatible", are unknown until the assessment runs.

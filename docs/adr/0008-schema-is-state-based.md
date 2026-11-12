# 0008 — Schema is state-based, deployed after the items

- **Status:** accepted
- **Date:** 2026-11-12
- **Deciders:** Scott
- **Evidence:** [`schema-and-ddl-management.md`](../research/schema-and-ddl-management.md)

## Context

`fabric-cicd` deploys item shells. For a Warehouse and a SQL database it says "Only the item shell
is deployed"; for a Lakehouse, "Schemas are not deployed". So the pipeline that makes an item exist
says nothing about whether the item has tables, and a green run can leave an empty warehouse that
looks deployed.

Two engines means two schema stories: T-SQL for the warehouse, Spark/Delta for the lakehouse. And
because the deployer redeploys everything on every merge, anything that is not part of the deployed
definition is invisible to it — a `CREATE TABLE` typed into the portal survives every merge and is
reported by nothing.

Atomicity is partial and worth stating: DDL inside a transaction covers tables, not views, stored
procedures or `CREATE SCHEMA`, and there are no savepoints.

## Decision

- **Two stages, one run.** Stage A deploys item shells with `fabric-cicd`. Stage B, later in the
  same pipeline, brings schema up to date.
- **Warehouse and SQL database: state-based.** An SDK-style database project (`.sqlproj`) published
  with `SqlPackage`, with `DeployReport` as the drift gate and `BlockOnPossibleDataLoss=true`.
  `DropObjectsNotInSource` stays off: it deletes data.
- **Lakehouse tables: `dbt-fabricspark`**, accepting that dbt's keys are `NOT ENFORCED` and therefore
  advisory.
- **One-offs** that neither models go through T-SQL in a notebook item rather than becoming a
  hand-maintained script folder.
- **If the DacFx preview is unacceptable**, fall back to ordered `.sql` files plus a
  `__schema_migrations` table, one transaction per script — and accept that ordering becomes a
  filename convention rather than a computed plan.

## Consequences

- Drift detection comes free for the warehouse: `DeployReport` compares desired against actual, which
  is the only thing in this design that notices a portal edit to a table.
- State-based means no ledger and no filename ordering. That removes a class of bug (a skipped
  migration) and adds a constraint: every schema change must be expressible as a desired state.
- Lakehouse and warehouse can drift from each other in principle, because they are separate tools.
  Keep table definitions owned by one of them, not both.
- A partial failure leaves schema ahead of items or behind them, and the pipeline must not treat
  stage B failure as cosmetic — the run fails.
- Preview status of DacFx against Fabric is a standing risk. The fallback exists so that it is a
  swap rather than a redesign.

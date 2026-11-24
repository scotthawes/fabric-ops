# 0011 — Consolidate on Fabric now, and gate Databricks on a named trigger

- **Status:** accepted
- **Date:** 2026-11-24
- **Deciders:** Scott, with the data team
- **Evidence:** [`data-stack-which-layers-exist-and-what-replaces-each.md`](../research/data-stack-which-layers-exist-and-what-replaces-each.md),
  [`tooling-which-specialists-earn-their-place-beside-fabric.md`](../research/tooling-which-specialists-earn-their-place-beside-fabric.md),
  [`ingestion-what-is-the-lowest-maintenance-route-from-an-app-database.md`](../research/ingestion-what-is-the-lowest-maintenance-route-from-an-app-database.md),
  [`capacity-provisioning-and-cost-control.md`](../research/capacity-provisioning-and-cost-control.md),
  [`schema-and-ddl-management.md`](../research/schema-and-ddl-management.md),
  [`mirroring-which-sources-latency-and-cost.md`](../research/mirroring-which-sources-latency-and-cost.md)
- **Relates to:** [ADR 0003](0003-terraform-control-plane-fabric-cicd-items.md),
  [ADR 0004](0004-one-shared-capacity.md), [ADR 0005](0005-authoring-and-promotion.md),
  [ADR 0008](0008-schema-is-state-based.md)
- **Pathway:** [`specs/0003-migration-pathway.md`](../specs/0003-migration-pathway.md)

## Context

The estate is an on-premises SQL Server application database, an Azure SQL Database warehouse, Azure
Data Factory deployed from a committed ARM export, Terraform for Azure infrastructure, a `.sqlproj`
for warehouse schema, and **one shared ADO YAML pipeline that rebuilds the factory and the
infrastructure across dev, test and prod in a single run**. Adding a pipeline, a table or a
resource is a change to that repository followed by a whole-estate rebuild.

The team is three data engineers, two DBAs who own the on-premises server, and one data lead.
T-SQL and ADF are the strongest skills; Python and Spark are learnable but not established. The
organisation is Microsoft-centric for governance, and **Power BI is the central BI layer**. The
stated tie-breaker between options is **least operational burden**, and the stated ambition is a
modern data engineering stack rather than a like-for-like replacement of ADF.

Three findings drive the decision:

1. **The two destinations differ in motion, not just product.** Fabric is a refactor for this
   estate — ADF has a documented upgrade path, Azure SQL Database is a supported Migration Assistant
   source, and `.sqlproj` survives. Databricks is a rebuild: T-SQL becomes Spark SQL, ADF becomes
   Lakeflow, and `.sqlproj` has no equivalent. That is a one-time cost difference, not a capability
   difference.
2. **Maintenance is counted in planes, not clicks.** Fabric is four control planes and six skill
   sets for this team; Databricks is six planes and eight, and adds a metastore, cluster policies,
   bundle state, cloud IAM and DBU cost attribution. For three delivery engineers, that is a second
   platform discipline.
3. **Power BI is native only on Fabric.** Direct Lake, XMLA and the semantic model are first-class
   there; on Databricks, Power BI becomes an external consumer over a SQL warehouse and Direct Lake
   is lost. With Power BI central, that is a decisive asymmetry.

The counter-force is real and is recorded rather than dismissed: Fabric's CI and item-deployment
surface is its weakest part, several item types are manual-only, the T-SQL surface is reduced, and
the product changes monthly. Databricks has the better engineering substrate — bundles, Unity
Catalog, Delta, Spark and ML on one platform.

## Decision

**Fabric is the platform for the warehouse, orchestration, storage, catalog and BI. Databricks is
deferred, not rejected: it becomes the platform only when one of the named triggers below fires and
a platform owner is funded.**

The scope inside Fabric is deliberately narrow — Warehouse first, Data Factory pipelines,
OneLake/Delta, `fabric-cicd` with one schema stage, Terraform limited to containers, Capacity
Metrics before any Eventhouse design. `.sqlproj` stays. Power BI stays. No dbt, no connector vendor,
no external catalog and no second semantic layer while the native surface works.

The option to leave is protected by three commitments: **data lands in Delta in OneLake**, **no
Databricks-specific object is a dependency of a Fabric workload**, and **the gate is reviewed with
operating evidence at a fixed point**, not argued from preference.

### Triggers for the gate

Databricks is reconsidered when **at least one** of these is true, and a named owner exists:

| Trigger | Evidence that would count |
| --- | --- |
| A funded ML or streaming use case | A named product or decision, an owner, and a date — not "we might want ML" |
| Power BI is replaced or decommissioned | The native-BI advantage disappears |
| Fabric capacity cannot serve the workload at an agreed cost | Measured throttling or overage across consecutive months, with a sizing attempt recorded |
| Fabric's CI causes a recurring release failure | A repeated class of failure that `fabric-cicd`, deployment pipelines and ADO approvals cannot fix |
| Data volume or concurrency outgrows the warehouse | Sustained query latency or capacity pressure that a larger SKU does not resolve economically |

A **platform owner is a precondition, not a trigger**: a named internal owner, or a funded hire. The
gate is reviewed **twelve months after the first production workload**, or earlier if a trigger
fires.

## Consequences

**What becomes easy.** One tenant, one capacity, one bill and one catalog. T-SQL, `sqlproj` and the
DBAs' existing knowledge remain usable. ADF has a documented upgrade path rather than a rewrite.
Power BI stays native. Mirroring adds no replication cost and no per-item meter. There is no Spark
platform to operate before there is a reason to.

**What becomes hard.** The T-SQL surface is a subset — recursive queries, materialized views,
synonyms and `CREATE USER` are unsupported, and cross-database queries are current-workspace only.
Item deployment has gaps, several item types are manual, and `fabric-cicd` deploys everything on
every run with no state ledger. Capacity overage is on by default at three times the pay-as-you-go
rate. Fabric ships monthly, so any claim older than a few months is a question.

**What we are now committed to maintaining.** Capacity utilisation and overage; the on-premises data
gateway if the application database is mirrored; 3N Entra groups (three environments × N
workspaces); schema drift checks via `DeployReport`; two service principals; and the gate review
itself.

**What this does not decide.** The ingestion route from the application database — mirroring versus
a scheduled copy — turns on how often its schema changes, and is recorded separately. It does not
decide whether the team adopts dbt later; on Fabric the current evidence says keep `.sqlproj`. It
does not commit to a capacity SKU, a migration date or a training budget.

## Alternatives rejected

- **Databricks now.** Rejected on current evidence: it is a rebuild for a team whose strongest
  skills are the ones being replaced, it loses native Power BI, and it requires a platform owner who
  is not named. Kept as the gated upgrade.
- **Fabric plus Databricks split.** Rejected. It creates a second governance plane for six people,
  and OneLake is not governed by Unity Catalog, so the split does not even share a catalog.
- **Stay on Azure SQL Database and ADF.** Rejected. It is the estate the team is trying to leave:
  a whole-estate rebuild pipeline, an ARM export that cannot be consumed by either destination, and
  no path to a modern practice without replacing the orchestrator anyway.
- **Lakehouse-first on Fabric.** Rejected for the first phase. It adds Spark and notebook skills
  before the warehouse has been replaced, and the `sqlproj` asset would be discarded for no gain.

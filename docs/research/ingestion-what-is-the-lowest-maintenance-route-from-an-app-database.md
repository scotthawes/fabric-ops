# What is the lowest-maintenance route from an on-premises application database into analytics, and what does each option cost?

- **Status:** answered
- **Checked:** 2026-11-24
- **Blocks:** the ingestion decision for the application database, and the scope of the first
  migration phase. It does not decide the platform; it assumes the source stays where it is.
- **Sibling notes:** [`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md)
  for the full mirroring source list, latency and billing detail;
  [`gateway-and-connectivity.md`](gateway-and-connectivity.md) for the gateway;
  [`data-stack-which-layers-exist-and-what-replaces-each.md`](data-stack-which-layers-exist-and-what-replaces-each.md)
  for the platform comparison; [`schema-and-ddl-management.md`](schema-and-ddl-management.md) for
  what DDL does to a deployed estate.

## Short answer

**Mirroring has the least build effort and the lowest Fabric-side cost, but it is fragile to
schema change — so "lowest maintenance" depends on how often the application's schema moves.**
On SQL Server 2016–2022 a DDL change breaks mirroring and needs CDC disabled and re-enabled plus a
full reseed of the table; on SQL Server 2025 one changed table reseeds. An application database with
per-sprint releases can therefore be the worst fit for the nominally lowest-maintenance option.

The durable answer is a **dedicated reporting schema you control**: mirror that, or copy it on a
schedule, and let the application's churn stay inside the application. The application database
itself does not move.

## Detail

### 1. What "maintenance" means in this note

Two different costs get collapsed under the word:

| Cost | What it counts |
| --- | --- |
| **Build effort** | The work to get the route running once: pipeline authoring, CDC setup, gateway install |
| **Recurring ownership** | What fails, needs patching, or needs a decision after it is running: reseeds, gateway updates, schema drift, credential rotation |

A route can be cheap to build and expensive to own. Mirroring is the clearest example.

### 2. The routes, compared

| Route | Build effort | Recurring ownership | Source impact | Cost shape | Fits when |
| --- | --- | --- | --- | --- | --- |
| **Fabric mirroring** (SQL Server 2016–2022 via CDC; 2025 via the Arc change feed) | Install gateway, enable CDC, start mirroring | DDL breaks or reseeds; no pause, so stop/start is a full reseed; gateway patched monthly | Initial snapshot reads every table; CDC adds log volume and capture work | **Replication free and no CU**; storage free to 1 TB per CU; queries at normal CU | Schema is stable for months and the tables fit the caps |
| **Fabric Copy job** over a reporting schema | Author the copy, schedule it | Schedule and watermarks; schema drift if the source shape changes | Reads the reporting schema on a schedule | `ActivityRun` / `DataMovement` CU plus storage | Schema changes often, or only a subset is needed |
| **Dataflow Gen2** | Author the query | Refresh failures, capacity for the mashup engine | Reads the source on refresh | Power Query engine CU | Light transformation is needed in the copy |
| **Existing ADF route** | Already built | The shared rebuild pipeline, IR/gateway, activity monitoring | Reads the source on schedule | ADF activity and data-movement billing | Only as a transition; it is the thing being replaced |
| **Databricks Lakeflow Connect (CDC)** | Gateway plus ingestion pipeline, deployed by bundle | Gateway runs as a continuous job; pipeline, UC grants, staging storage, DBU cost | CDC on the source, same capture overhead as mirroring | **DBU-metered** ingestion plus gateway compute, staging and ADLS; no free replication tier | Databricks is already the platform |
| **Databricks Lakehouse Federation** | Register a foreign catalog | Warehouse sizing, pushdown limits | Load lands **at query time**, not continuously | SQL warehouse DBUs per query | Ad-hoc or low-frequency reads |
| **Connector vendor** (Fivetran, Airbyte and similar) | Connection setup | Connector maintenance, MAR billing, an extra hop if it has no Fabric destination | Depends on the connector's read method | Monthly-active-rows or similar meter | Many SaaS sources, not one SQL Server |

Fivetran's documented destination list contains no Fabric or OneLake destination, so on a Fabric
target it lands in SQL Server/Synapse/Databricks and copies again. That makes it a second plane
for a problem native mirroring already solves.

### 3. Cost, on both sides

**Fabric side.** "Fabric compute used to replicate your data into Fabric OneLake is free" and does
not consume capacity; storage is free to **1 TB per CU** (F64 → 64 TB), mirroring data only; query
compute is billed at normal rates. The only other mirroring meter is the optional extended
capabilities at 3 CU-hours. For a sub-terabyte application database inside a capacity the warehouse
already needs, the marginal Fabric cost is approximately zero.

**Databricks side.** Ingestion pipelines are serverless and DBU-metered; the database connector
also requires an **ingestion gateway**, which "runs in its own job as a continuous task", plus
staging storage and ADLS. There is no free replication allowance. The cost is modest but permanent.

**Source side, both.** Microsoft does not publish a CPU or IOPS figure. What it documents is the
shape:

- "During initial snapshot, there might be more resource usage on the source database, for both
  CPU and IOPS."
- "Long-running transactions might result in the transaction log filling up more than usual. The
  source database transaction log should be monitored so that the transaction log does not fill."
- Fabric's caps: **1,000 tables** per mirrored database and **1 TB of change data per day**, after
  which replication throttles.

### 4. Why an application database is the hard case

Mirroring treats schema change as a replication failure, not a normal event:

- **SQL Server 2016–2022:** the table fails with "definition has changed since CDC was enabled" and
  recovery is `sp_cdc_disable_table` + `sp_cdc_enable_table`, which reseeds the table.
- **SQL Server 2025:** the changed table reseeds; the rest continue.
- **Stop/start:** starting mirroring "reseeds all the tables, effectively starting from scratch".
- **Capacity pause:** replication stops; the free storage allowance stops with it; a long pause can
  force a reseed on resume.

An application database whose schema changes every release turns each release into a reseed: source
I/O, Fabric work, and a window where the table is incomplete. That is maintenance, even though the
route needed the least building.

### 5. The decision rule

1. **Is the schema stable for months, and under 1,000 tables?** Mirror it. Nothing else is close on
   build effort or cost.
2. **Does the schema change per release?** Create a reporting schema that only the data team
   changes, and mirror or copy that. The application's DDL never reaches the replication path.
3. **Is the need ad-hoc or rare?** Federate. No copy, no storage, but the source pays at query time.
4. **Is the destination Databricks anyway?** Lakeflow Connect works, but it is billed and adds a
   gateway; do not choose Databricks for the ingestion.
5. **Never mirror an application database whose schema you do not control** without a tested
   recovery procedure for the DDL failure mode.

## What this settles

- Mirroring is the lowest-build, lowest-Fabric-cost route, and its weakness is schema change, not
  money.
- A reporting schema is the maintenance boundary: it decouples the application's release cadence
  from the replication route.
- Databricks has an equivalent for every route but no free replication; ingestion there is a DBU
  line item plus a gateway to operate.
- The application database stays. This note is about reading it, not replacing it.

## What this does not establish

- **The application's schema-change frequency**, which is the input that decides between mirroring
  and a scheduled copy.
- **Database size, daily change volume and read concurrency**, so no cost figure is produced and
  none of the caps are shown to be safe.
- **The per-GB OneLake overflow rate**, which Learn does not publish as static text.
- **The on-premises SQL Server version**, which decides CDC (2016–2022) versus the Arc change feed
  (2025) and therefore the DDL failure mode.
- **Whether a reporting schema can be created in the application database**, or whether the
  application team will accept the coupling that implies.
- **The gateway topology** — on-premises data gateway versus VNet data gateway — which depends on
  the network posture.
- **Databricks Lakeflow Connect's release state for SQL Server**, since the connector index states
  that release states vary.

## Sources

All pages read on **2026-11-24**; the date column is the page's own `ms.date` where published.

| Source | Used for | Dated |
| --- | --- | --- |
| [Mirror SQL Server](https://learn.microsoft.com/en-us/fabric/mirroring/sql-server) | CDC for 2016–2022 vs Arc change feed for 2025; snapshot CPU/IOPS; log growth; free replication and capacity-based storage | ms.date 2025-11-05, updated 2026-07-06 |
| [Mirroring overview](https://learn.microsoft.com/en-us/fabric/mirroring/overview) | cost of mirroring; 1 TB per CU; query compute; latency claim | ms.date 2026-08-28 |
| [`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md) | 1,000-table cap; 1 TB/day change ceiling; DDL failure and reseed; no pause; extended-capabilities meter | checked 2026-11-12 |
| [`gateway-and-connectivity.md`](gateway-and-connectivity.md) | gateway requirement, monthly updates, no rollback | checked 2026-11-12 |
| [Lakeflow Connect connector concepts](https://learn.microsoft.com/en-us/azure/databricks/ingestion/lakeflow-connect/) | database connectors use CDC; ingestion gateway as a continuous job; staging storage; serverless; on-prem via ExpressRoute; bundles | ms.date 2026-11-18 |
| [Lakehouse Federation](https://learn.microsoft.com/en-us/azure/databricks/query-federation/) | read-only foreign catalog; no copy; query-time source load | ms.date 2026-11-12 |
| [Lakebase Postgres](https://learn.microsoft.com/en-us/azure/databricks/oltp/projects/) | the app-hosting answer is Postgres, not SQL Server; scale-to-zero; UC registration | ms.date 2026-11-11 |
| [SQL database in Fabric limitations](https://learn.microsoft.com/en-us/fabric/database/sql/limitations) | 32 vCores and 4 TB if Fabric were asked to host the application database | read 2026-11-24 |
| [Fivetran Destinations](https://fivetran.com/docs/destinations) | no Fabric or OneLake destination; the extra-hop consequence | read 2026-11-24 |

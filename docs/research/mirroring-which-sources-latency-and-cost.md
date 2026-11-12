# Which sources can Fabric mirror, how fast, and what does it cost per mirrored item?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** whether ingestion is a pipeline concern at all (spec 0001's scope), and the capacity-sizing input for a mirrored source.

## Short answer

Twelve sources can be mirrored and are generally available — six database engines, SQL Server, Oracle, Snowflake, BigQuery, SAP (via Datasphere), Fabric's own SQL database, plus open mirroring and Databricks metadata — with six more preview-only, so mirroring is a design foundation for the relational estate and only an option for MySQL, SharePoint and the newer catalogs. Replication is **free**: the replicator is background compute that "doesn't consume capacity", and storage is free up to one terabyte per capacity unit, so mirroring adds **no per-item, per-table or per-GB meter** and sizes a capacity on storage and query compute rather than on ingestion. The catch is behavioural, not financial: there is **no pause**, `stopMirroring` disables it and `startMirroring` reseeds every table from scratch, latency is stated only as "near real-time" and "as fast as every 15 seconds" with no target, and the source-side cost (Snowflake credits, BigQuery CDC, Datasphere outbound, log growth) is real even though the Fabric-side cost is zero.

## Detail

Read against the `docs/mirroring/` documentation set, `ms.date` recorded per page in Sources. Conventions first, because they decide the answer: the mirroring pages mark preview sources inline and the get-started page states the rule — "Sources marked **(preview)** are in [public preview]; all other sources are generally available." That is the GA/preview discriminator used throughout below; where a page carries its own preview banner I say so.

### 1. The source list, with GA and preview separated

Database mirroring copies data; metadata mirroring does not — it "references source data through OneLake shortcuts instead of replicating it", so a metadata source is not an ingestion path at all. That distinction matters more than the row count.

**Generally available (12)**

| Source | Kind | What it needs |
| --- | --- | --- |
| Azure SQL Database | Database | Writable primary; not already CDC- or Synapse-Link-enabled; SAMI or UAMI on the logical server as primary identity; `ALTER ANY EXTERNAL MIRROR`; all vCore tiers, but not Free/Basic/Standard under 100 DTU |
| Azure SQL Managed Instance | Database | Same as above; single instance or instance pool; all vCore tiers |
| Azure Database for PostgreSQL **flexible server** | Database | Versions 14–18; General Purpose or Memory Optimized — **Burstable not supported**; role with `LOGIN`, `REPLICATION`, `azure_cdc_admin` and table ownership; SAMI enabled |
| Azure Cosmos DB | Database | **Only the NoSQL API**; continuous backup (7- or 30-day) is a prerequisite; single write region only; not in sovereign clouds |
| SQL Server 2016–2022 | Database | CDC; Standard/Enterprise/Developer; on-prem, Azure VM or another cloud; gateway if not reachable |
| SQL Server 2025 | Database | Azure Arc + Azure Extension for SQL Server; its own change feed, **not** CDC; not on Linux, not on Azure VM |
| Oracle | Database | Versions 10+ with LogMiner, `ARCHIVELOG`, supplemental logging; **on-premises data gateway only** (no VNet gateway); write-mode databases |
| Snowflake | Database (plus metadata for Iceberg) | `CREATE STREAM`, `SELECT`, `SHOW`, `DESCRIBE`; a storage connection for Iceberg tables; case-sensitive identifiers |
| Google BigQuery | Database | BigQuery CDC; Storage Write API |
| SAP | Database | **Via SAP Datasphere only** — Datasphere replicates to ADLS Gen2, Fabric mirrors that container; S/4HANA, ECC, BW/4HANA, BW, Datasphere |
| Fabric SQL database | Database, automatic | Nothing: "Mirroring starts upon creation … with **no user action required**", always on, cannot be turned off |
| Open mirrored database | Open | Your own writer; a landing-zone URL and the open mirroring format |
| Azure Databricks (Unity Catalog) | **Metadata** | Catalog access; no data movement — tables are shortcuts into the lake |

**Preview (6)**

| Source | Kind | Note |
| --- | --- | --- |
| Azure Database for MySQL | Database | Flexible server; **VNet-enabled servers and HA not supported**; General Purpose or Memory Optimized, not Burstable |
| SharePoint List | Database + metadata | Documents surface as shortcuts; list data is replicated |
| Dremio catalog | Metadata | ICEberg REST catalog |
| AWS Glue catalog | Metadata | Iceberg REST catalog; IAM key only; Lake Formation permissions if governed |
| Google Lakehouse runtime catalog | Metadata | Iceberg REST catalog; Google Workload Identity Federation |
| Azure Monitor | Metadata (reference) | Log Analytics tables referenced through shortcuts; **no replication and no backfill**; ~500 tables; ~15 minutes before tables appear |

Two things this list corrects from the obvious reading of the product: **Oracle is GA**, not preview, and **BigQuery moved to GA** — its page now opens "Mirroring for Google BigQuery is now generally available. Production workloads are fully supported." Conversely **MySQL has been in preview for a long time** and its page still carries the preview banner, so it is not a foundation.

Not in the list, and therefore not mirrored: Salesforce, Dynamics, Dataverse, MongoDB, Cassandra, Teradata, Netezza, Db2, Azure Table/Blob/ADLS (those are shortcuts or Copy job sources), and any REST or file source. The documented escape routes are open mirroring and the open mirroring partner ecosystem.

### 2. Latency — a claim, not a target

Every number Microsoft publishes about mirroring latency is descriptive. There is **no latency SLO, no percentile, and no per-source target** anywhere in the set. The strongest statement is in the overview:

> "Inside Fabric, a replicator engine always runs and scans for newly published files at a high frequency. Fabric immediately merges incoming changes into the target delta table. Changes can be published as fast as every 15 seconds."

with the qualifiers listed immediately above it — source region, destination region, "Volume of changes", "Frequency of changes", "Network bandwidth and latency from source", and "Compute resources allocated to the on-premises data gateway".

Per source, what is actually stated:

| Source | Statement |
| --- | --- |
| Azure SQL Database / MI | FAQ: "How long does it take to replicate inserts/updates/deletes? **Near real-time latency.**" Initial replication: "It depends on the size of the data that is being brought in." |
| Cosmos DB | "It could take **a few minutes** to replicate your Azure Cosmos DB Data into Fabric OneLake. Depending on your data's initial snapshot or the frequency of updates/deletes, replication could also take longer." |
| Metadata catalogs (Databricks, AWS Glue, Google Lakehouse) | "Propagation can take anywhere from **a few seconds to several minutes**." |
| Snowflake views / materialized views | "Supported with **syncs every 12 hours**." Idle tables back off "up to an hour". |
| Azure Monitor | "Updates appear in Fabric **in minutes**"; ~15 minutes for tables to appear after item creation. |
| PostgreSQL, MySQL, Oracle, SAP, BigQuery, SQL Server | **No number stated** — only "near real-time". |

So the honest design statement is: **sub-minute for change data on a healthy relational source, minutes for initial snapshot and for metadata, and up to 12 hours if what you mirrored is a Snowflake view.** Mirroring is not a streaming system and no page claims it is.

**Is the lag visible?** Yes, and this is better documented than the claim. Two independent surfaces:

- **Per-table metrics in the KQL table** `MirroredDatabaseTableExecution` (workspace monitoring, Eventhouse): `ReplicatorBatchLatency` — "The latency to replicate the batch of data during mirroring. **Unit is in seconds**" — alongside `ProcessedRows`, `ProcessedBytes`, `OperationName` (`StartSnapshotting`, `Snapshotting`, `StartReplicating`, `Replicating`, `StartReseeding`, `FailTable`, …) and `OperationStartTime`/`OperationEndTime`. The troubleshooting page says explicitly: "you can check the mirroring execution latency by querying the `ReplicatorBatchLatency` value".
- **Portal "Last completed"** per table, which the troubleshooting page treats as the primary delay signal — "An empty value means the table isn't yet mirrored."
- **Source side**, for the SQL family: `sys.dm_change_feed_log_scan_sessions.latency`, and `reseed_state` in `sys.sp_help_change_feed_settings`.

The REST API gives status and per-table status but **not** a latency number — `getTablesMirroringStatus` returns status and metrics, and the older note already covers its enumerations. Grading a mirror against a latency budget therefore needs workspace monitoring enabled, or the portal.

### 3. Cost — three zeroes and one meter

The billing model is unusual and is the finding that changes the design: **the thing you would expect to cost money is free, and the thing that costs money is the optional add-on.**

**(a) Replication compute — free, and not CU.**

> "Background Fabric compute used to replicate your data into Fabric OneLake is **free and doesn't consume capacity**. Requests directly to the OneLake for mirrored data consume capacity as normal OneLake compute consumption."

Every source page repeats it in its own words ("Fabric compute used to replicate your data into Fabric OneLake is free"), and the extended-capabilities page puts it bluntly: "Mirroring without extended capabilities is free."

**(b) OneLake storage — free to 1 TB per CU.**

> "Mirroring offers a free terabyte of mirroring storage **for every capacity unit (CU)** you purchase. For example, if you purchase an F64 capacity, you get 64 free terabytes worth of storage, exclusively used for mirroring. You pay for OneLake storage if you exceed the free mirroring storage limit **or when the capacity is paused**."

The pricing page publishes the whole ladder: F2 → 2 TB, F4 → 4, F8 → 8, F16 → 16, F32 → 32, F64/P1 → 64, F128/P2 → 128, F256/P3 → 256, F512/P4 → 512, F1024/P5 → 1,024, F2048 → 2,048, F4096 → 4,096, F8192 → 8,192. Two riders: "The free Mirroring storage can only be used for storing Mirroring replica data—no other data", and "Free Mirroring storage is also only for purchased capacities; **it does not come with the Fabric free trial**."

The per-GB overflow rate is **not** in any static text I could read — the Azure pricing page renders it client-side, and every Learn page defers to it. *Could not establish* the rate; the free threshold is the number that matters for sizing anyway.

**(c) Query compute — normal rates.** "The compute for querying data by using SQL, Power BI, or Spark is charged at regular rates." This is the real ongoing cost of a mirror: reading it.

**(d) Extended capabilities — the only mirroring meter.** Delta change data feed and mirroring views are **GA** and paid:

| Aspect | Delta change data feed | Views |
| --- | --- | --- |
| Consumption meter | Data movement – incremental replication | same |
| CU consumption rate | **3 CU-hours** | 3 CU-hours |
| Granularity | per-second | per-second (views only) |
| Empty runs | not charged | n/a |

The rate is borrowed, not invented: it is the same `DataMovementIncrementalCopy` meter as incremental copy in Copy job ("3 CUs hours" there too), and "the operation name appears as Mirror Replication Premium using DataMovementIncrementalCopy". Billing is per mirrored database item for CDF and per view for views, and "Delta change data feed and mirroring views enabled together result in one unified charge for the mirror workload, not double charging."

So the meter vocabulary is: **capacity units for incremental replication work, GB-months of OneLake storage above the free tier, and ordinary CU for queries.** Nothing is billed per mirrored item, per table, or per ingested GB — which is exactly the opposite of the pipeline-plus-storage mental model the rest of the pack uses.

**(e) Source-side cost — not zero, and not Microsoft's to quote.** Fabric's replicator reads the source, so the source pays:

- **Snowflake**: "virtual warehouse compute and cloud services compute" — "queries that do produce data such as a `SELECT *` will wake up the Snowflake warehouse and compute will be charged", plus cloud-services credits by edition. Guidance is to **reuse an existing warehouse** rather than a dedicated one, and to "mirror only the tables you need", because "mirroring an entire database can cause unexpectedly high Snowflake consumption".
- **BigQuery**: "BigQuery Change Data Capture (CDC) utilizes BigQuery compute for row modification, Storage Write API for data ingestion, BigQuery storage".
- **SAP**: "SAP Datasphere Premium Outbound Integration pricing applies."
- **Cosmos DB**: continuous backup is a prerequisite; "7-day continuous backup is recommended, as it is free of cost" — the 30-day tier is not.
- **Egress**: free into OneLake ("Fabric doesn't charge for network data ingress fees into OneLake for Mirroring"), but cross-region reads are not — "If the Azure SQL Database is located in a different region from your Fabric capacity, data egress will be charged", and Snowflake warns of "higher replication latency and data egress charges" across regions.
- **Source resources**: "During initial snapshot, there might be more resource usage on the source database, for both CPU and IOPS", and active transactions hold log truncation, so "the source database transaction log should be monitored".

**What the initial seeding costs, and whether it can be avoided.** On the Fabric side, nothing: the snapshot is replication work, and replication work is free unless CDF is on. On the source side it is a full table read — I/O, CPU, and for Snowflake a full warehouse read with the one concrete published example being "a reseed of a **226 million-row table (~26.5 GB)** takes significant compute time."

There is **no documented way to seed cheaply or incrementally**. Every documented path is a full reseed:

- "Stopping mirroring disables mirroring completely." / "**Starting mirroring reseeds all the tables, effectively starting from scratch.**"
- "When there's DDL change, a complete data snapshot is restarted for the changed table, and data is reseeded."
- "Each time you stop and start, the entire table is fetched again."
- PostgreSQL: "DDL operations on existing mirrored tables aren't supported … Modify existing tables requires to stop and restart replication."
- Autoreseed fires by design when the source log passes `@autoreseedthreshold` (70% in the example) with `log_reuse_wait_desc = REPLICATION`, to protect write availability.
- A long capacity pause can force a reseed on resume.

What the docs offer instead are **triggers to avoid**, which is the closest thing to a cost control:

- Do not stop/start for routine reasons — it is a full re-read, and the Snowflake page says a reseed is preferable only when "you're changing most of the data in a large table".
- Keep DDL out of the replication window: "Schedule schema changes outside of active mirroring. If you use DBT or other schema management tools, schedule them during maintenance windows **or pause mirroring before running schema changes**". DBT's drop-and-recreate is called out as able to "cause continuous reseeding loops".
- Mirror selected tables, not the whole database.
- For Oracle, "stagger large tables and avoid bulk restarts that trigger multiple reseeds concurrently" — concurrent reseeds "cause sharp memory spikes" on the gateway.
- A **deployment does not reseed**, because "Mirrored database isn't started after deployment" (see §5).

### 4. Limits

| Limit | Value | Source |
| --- | --- | --- |
| Tables per mirrored database | **1,000** ("Any tables above the 1000 limit currently can't be replicated"); with *Mirror all data*, the first 1,000 alphabetically by schema then table | Limitations pages, and the error-message table |
| Change data per mirrored database per day | **1 TB**, after which "The replication is being throttled and expected to continue at YYYY-MM-DDTHH:MM:ss" | Troubleshooting |
| Mirrored items per workspace or capacity | **not documented** — *could not establish* | — |
| Azure Monitor item | ~500 tables, soft during preview | Azure Monitor catalog page |
| LOB columns | truncated to **1 MB** (Azure SQL/MI/SQL Server), 2 MB (Cosmos); `varchar(max)` in the SQL endpoint up to 16 MB for tables created after 2025-11-18 | Troubleshooting |
| Delta precision | six fractional digits — `datetime2(7)`, `datetimeoffset(7)`, `time(7)` lose precision, and cannot be a primary key | Limitations pages |

**Unsupported, consistently across sources:** `geometry`, `geography`, `hierarchyid`, `sql_variant`, `timestamp`/`rowversion`, `xml`, `image`, `text`/`ntext`, CLR and user-defined types, computed columns, and — for the newer sources — `json` and `vector`. Tables using Always Encrypted, in-memory OLTP, graph, external tables, temporal/ledger history, or clustered columnstore cannot be mirrored at all. PostgreSQL adds a long list (`json`, `jsonb`, `inet`, `cidr`, range types, `tsvector`, …) and excludes views, materialized views, foreign tables, partitioned tables and TimescaleDB hypertables. Delta supports six digits of precision, so precision loss is expected rather than an error.

**Schema change behaviour differs per source, and the difference is operational:**

| Source | On DDL |
| --- | --- |
| Azure SQL DB / MI, SQL Server 2025 | One changed table reseeds; the rest keep running |
| SQL Server 2016–2022 | Mirroring **fails** with "Table 'SCHEMA.TABLE' definition has changed since CDC was enabled", and must be recovered by `sys.sp_cdc_disable_table` + `sys.sp_cdc_enable_table` |
| PostgreSQL | **Not supported at all** — stop and restart replication |
| Oracle | Add/drop/rename column partially supported; **type changes not supported** |
| Cosmos DB | New properties become columns, missing ones null, renames keep both columns, incompatible type changes become null |
| Snowflake | Any DDL that moves the DDL timestamp triggers a reseed; schema changes may need a data change before they appear |

**Source unavailable.** The platform protects the source rather than the mirror: the log cannot truncate past unreplicated changes, so it grows, and autoreseed eventually truncates it and reinitialises. On the Fabric side the item keeps its status; a network-security-perimeter block is the sharpest example — "Replication stops, but the mirrored database still looks healthy in the Fabric portal."

**Can a mirrored database be paused without losing replication? No.** There is no pause verb. The portal's "Stop replication" is described as "OneLake files remain as is, but incremental replication stops" — but the limitations pages state the consequence plainly: "Stopping mirroring disables mirroring completely", and starting reseeds everything. Pausing the **capacity** is not a pause either: the item reads `Paused`, changes are not replicated, and it stays `Paused` after the capacity resumes until someone selects **Resume replication** — and if the pause was long, "mirroring might not resume from its stopping point and will reseed data from the beginning."

Two more that constrain operations rather than data: **ownership cannot be transferred** ("If a mirrored database stops working because the item owner left the organization or is no longer valid, you need to recreate the mirrored database"), and **CMK on OneLake is not supported** for mirrored data.

### 5. What this means for the design

**For the sources it covers, mirroring replaces the extract-and-load half of ingestion — and only that half.**

What disappears from the pipeline for a mirrored source:

- change capture, snapshot + CDC, watermarks, incremental polling and its schedule;
- landing to Delta, Parquet conversion, table and column mapping, schema-hierarchy replication;
- the orchestration of all of the above — there is no job to schedule. It runs continuously.

What does **not** disappear, and therefore stays in the pipeline:

1. **Transformation.** Mirroring is verbatim. You cannot add a calculated column or calculated table — "Mirrored databases are read-only … To add calculated columns, create a Lakehouse and use shortcuts to reference the mirrored data, then create your calculated columns in the Lakehouse using notebooks or SQL." Silver and gold layers, conforming, SCD history and cross-source joins all remain pipeline work. A mirrored database is a bronze layer and the docs say so: "cleansing and transforming the data that is landing into mirrored database as the bronze layer."
2. **Security re-implementation.** Source permissions do not travel: "Row-level security is supported, but permissions are currently not propagated to the replicated data in Fabric OneLake", and the same for object-level permissions, dynamic data masking, and Purview sensitivity labels. Snowflake RLS/CLS "must be manually reconfigured in Fabric". That is deployment work, per environment.
3. **Coverage of everything unlisted.** Non-listed sources are Copy job, pipelines or open mirroring — an ingestion pipeline by another name. Preview sources (MySQL, SharePoint, the catalogs) are not a foundation.
4. **Selection and ownership of the table list.** Which tables, and `defaultSchema`, are part of the item definition and therefore a review artefact.
5. **Starting it.** This is the one hard deploy-time consequence: "Mirrored database **isn't started after deployment**. You need to start it manually or through API." Deployment ships the shell; the run is a separate, capacity-dependent step. Combined with §4, a naive deploy-then-start cycle on an *existing* mirror is a full reseed of every table.
6. **Monitoring it.** Not on the job surface at all — the sibling note covers why — so it needs a poll of `getMirroringStatus` or the workspace-monitoring table, plus a check that nobody stopped it.

**Deployment shape, since this is what the pipeline would actually carry.** A mirrored database is a deployable item: Git produces `{display name}.MirroredDatabase/` containing `mirroring.json` and `.platform`, deployment pipelines can promote it, and **deployment rules** parameterise the source — "Data source rules → + Add rule, input the target connection ID and optionally database". Only the item is tracked: "The SQL analytics endpoint, views, and other child items aren't tracked." Promotion therefore moves *what to mirror*, not *the mirrored data*, which is correct for dev/test/prod but means each environment re-seeds from its own source on first start.

**The capacity-sizing input, which is the number spec 0001 actually needs.** Mirroring contributes **zero CUs to replication** and therefore zero to the interactive or background smoothing windows — it cannot push a capacity into throttling by replicating. It contributes (i) storage, measured against the 1 TB-per-CU free allowance, so the sizing question is "how many TB of replica do we hold" rather than "how busy is the replicator", and (ii) query compute, which is the same CU any read of that data would cost. Extended capabilities, if enabled, do consume: 3 CU-hours against the incremental-replication meter, billed per second of actual work.

**One design tension worth naming against ADR [0004](../adr/0004-one-shared-capacity.md).** That ADR accepts a single shared capacity, and the capacity note observes this gives up scheduled pause. Mirroring sharpens it in both directions: a paused capacity stops replication *and* starts billing the mirrored storage it was giving away free, and a long pause can force a full reseed on resume. So a mirror makes pause more expensive than the capacity note assumed — the storage charge turns on exactly when you stop paying for compute — while also making pause less necessary, because replication itself is free. Whether that changes the ADR is a decision for the ADR, not this note.

## What this settles

- **Ingestion is not entirely a pipeline concern, but it is not eliminated either.** For a GA database source, mirroring removes extract, load, change capture and scheduling from the pipeline's job. Transformation, security, non-listed sources, starting the mirror and watching it all remain.
- **Twelve GA sources, six preview.** GA: Azure SQL Database, Azure SQL Managed Instance, Azure Database for PostgreSQL (flexible server), Azure Cosmos DB (NoSQL), SQL Server 2016–2025, Oracle, Snowflake, Google BigQuery, SAP via Datasphere, Fabric SQL database, open mirroring, Azure Databricks metadata. Preview: Azure Database for MySQL, SharePoint List, Dremio catalog, AWS Glue catalog, Google Lakehouse runtime catalog, Azure Monitor.
- **Latency is a claim, not an SLO.** "As fast as every 15 seconds" for change data; minutes for initial snapshot and metadata sync; 12 hours for Snowflake views. The lag *is* measurable — `ReplicatorBatchLatency` in `MirroredDatabaseTableExecution`, or the portal's "Last completed".
- **Cost is not per item, per table or per GB ingested.** Replication compute is free and consumes no CU; storage is free to 1 TB per CU; the only mirroring meter is extended capabilities at 3 CU-hours on `DataMovementIncrementalCopy`. Source-side compute (Snowflake credits, BigQuery CDC, Datasphere outbound) is the cost that is easy to miss.
- **There is no pause.** Stop disables; start reseeds every table. A capacity pause stops replication without resuming it, and bills the storage. This is a behavioural limit, not a billing one.
- **Sizing a capacity for mirroring is a storage question, not a compute question** — 1 TB per CU of free replica storage is the figure to plan against.

## What this does not establish

- The **per-GB OneLake overflow rate** for mirrored storage beyond the free tier; the Azure pricing page renders it dynamically and Learn only publishes the free allowance.
- Whether **deploying a mirrored database over a running one stops it** and therefore forces a reseed. The CI/CD page states only that a newly deployed mirror is not started.
- The **number of mirrored items** a workspace or capacity can hold; no page gives a ceiling.
- Any **latency percentile or target** per source. Every figure is "near real-time", a worked example, or a unit-of-measure definition; none is an SLO, and none is measured here.
- Whether `ReplicatorBatchLatency` reflects end-to-end staleness or only the batch-merge step — the column description says "the latency to replicate the batch of data", which is narrower than "how old is my newest row".
- What **`startMirroring` costs on the source** in wall-clock terms for a given table size; only the shape ("depends on the size") and one 226M-row/26.5 GB example exist.
- Whether **mirroring views** (preview, Snowflake-only) will ever extend to other sources; the extended-capabilities page is GA for the capability while the views note says "views are only supported in preview in mirroring for Snowflake".
- Whether the **1 TB/day change-data ceiling** is per capacity or per item under contention — the error text says "per Mirrored database", and no page explains what happens across many concurrent mirrors.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Mirroring overview](https://learn.microsoft.com/en-us/fabric/mirroring/overview) | the source table, the three mirroring types, "as fast as every 15 seconds", the latency factors list, cost of mirroring (free compute, 1 TB per CU), retention defaults, paused capacity | ms.date 2026-08-28 |
| [Get started with mirroring](https://learn.microsoft.com/en-us/fabric/mirroring/get-started-with-mirroring) | the GA-vs-preview rule ("Sources marked (preview) … all other sources are generally available") and the per-source tutorial list | ms.date 2026-07-27, upd. 2026-08-19 |
| [Mirror Azure SQL Database](https://learn.microsoft.com/en-us/fabric/mirroring/azure-sql-database) and [limitations](https://learn.microsoft.com/en-us/fabric/mirroring/azure-sql-database-limitations) | tier support, gateway/network security perimeter, 1,000-table cap, unsupported types, stop-disables/start-reseeds, SAMI/UAMI | ms.date 2026-10-08, upd. 2026-11-06 |
| [Mirror Azure SQL Managed Instance](https://learn.microsoft.com/en-us/fabric/mirroring/azure-sql-managed-instance) | vCore tiers, instance pool, gateway requirement, free replication wording | ms.date 2025-05-08, upd. 2026-05-21 |
| [Mirror Azure Database for PostgreSQL](https://learn.microsoft.com/en-us/fabric/mirroring/azure-database-postgresql) and [limitations](https://learn.microsoft.com/en-us/fabric/mirroring/azure-database-postgresql-limitations) | GA status, versions 14–18, no Burstable, HA from v17, DDL unsupported, 1,000 tables | ms.date 2025-07-15, upd. 2026-05-21 / ms.date 2026-02-27, upd. 2026-11-05 |
| [Mirror Azure Database for MySQL (preview)](https://learn.microsoft.com/en-us/fabric/mirroring/azure-database-mysql) | preview banner, no VNet servers, no HA, no Burstable | ms.date 2026-03-18, upd. 2026-08-24 |
| [Mirror Azure Cosmos DB](https://learn.microsoft.com/en-us/fabric/mirroring/azure-cosmos-db) | NoSQL only, continuous backup prerequisite, "a few minutes", schema-change handling, no CMK, no multi-write | ms.date 2026-10-21, upd. 2026-10-22 |
| [Mirror SQL Server](https://learn.microsoft.com/en-us/fabric/mirroring/sql-server) and [limitations](https://learn.microsoft.com/en-us/fabric/mirroring/sql-server-limitations) | 2016–2022 CDC vs 2025 change feed, Arc requirement, AG behaviour, DDL failure mode, 1,000 tables | ms.date 2025-11-05, upd. 2026-07-06 / ms.date 2026-05-15 |
| [Optimize SQL Server mirroring performance](https://learn.microsoft.com/en-us/fabric/mirroring/sql-server-performance) | `maxtrans`, `dynamicmaxtrans`, three-minute scan timeout, resource governor pools | ms.date 2025-08-19 |
| [Mirror Oracle](https://learn.microsoft.com/en-us/fabric/mirroring/oracle) and [limitations](https://learn.microsoft.com/en-us/fabric/mirroring/oracle-limitations) | LogMiner, archive log mode, OPDG-only, 1,000 tables, partial DDL support, unsupported types | ms.date 2025-08-22 / ms.date 2026-02-26 |
| [Mirror Snowflake](https://learn.microsoft.com/en-us/fabric/mirroring/snowflake) and [limitations](https://learn.microsoft.com/en-us/fabric/mirroring/snowflake-limitations) | object-type table, 12-hour view syncs, no scheduling or replication windows, reseed triggers and DBT loops, 226M-row example, Snowflake-side cost | ms.date 2025-09-16, upd. 2026-10-23 / ms.date 2026-02-26 |
| [Mirror Google BigQuery](https://learn.microsoft.com/en-us/fabric/mirroring/google-bigquery) | GA banner, BigQuery-side CDC/Storage Write API cost | ms.date 2026-08-18, upd. 2026-08-28 |
| [Mirror SAP](https://learn.microsoft.com/en-us/fabric/mirroring/sap) | Datasphere two-step path, supported SAP sources, outbound integration pricing | ms.date 2026-02-26, upd. 2026-06-27 |
| [Mirror SharePoint List](https://learn.microsoft.com/en-us/fabric/mirroring/sharepoint-list) | preview status, document-library shortcuts vs list replication | ms.date 2026-08-27, upd. 2026-09-29 |
| [Mirror Azure Databricks](https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks) | metadata-only mirroring, seconds-to-minutes propagation, catalog selection | ms.date 2026-10-24, upd. 2026-10-28 |
| [AWS Glue catalog](https://learn.microsoft.com/en-us/fabric/mirroring/catalog-mirroring/aws-glue) and [Google Lakehouse runtime catalog](https://learn.microsoft.com/en-us/fabric/mirroring/catalog-mirroring/google-lakehouse-runtime) | preview banners, Iceberg REST catalog, auth models, metadata-sync behaviour | ms.date 2026-07-28 / ms.date 2026-08-21 |
| [Mirror Azure Monitor (preview)](https://learn.microsoft.com/en-us/fabric/mirroring/catalog-mirroring/azure-monitor) | preview banner, no replication/backfill, ~500 tables, ~15-minute setup latency, no duplicate storage charge | ms.date 2026-11-10, upd. 2026-11-11 |
| [Mirror SQL database in Fabric](https://learn.microsoft.com/en-us/fabric/database/sql/mirroring-overview) | automatic mirroring, always-on, no table selection, PITR and capacity-pause behaviour | ms.date 2025-07-02, upd. 2026-02-17 |
| [Monitor mirrored database replication](https://learn.microsoft.com/en-us/fabric/mirroring/monitor) | portal statuses, rows replicated, "Last completed", workspace-monitoring pointer | ms.date 2025-09-05, upd. 2026-07-06 |
| [Mirrored database operation logs](https://learn.microsoft.com/en-us/fabric/mirroring/monitor-logs) | `MirroredDatabaseTableExecution` columns, `OperationName` values, `ReplicatorBatchLatency` in seconds | ms.date 2025-05-12, upd. 2026-02-17 |
| [Troubleshoot mirroring](https://learn.microsoft.com/en-us/fabric/mirroring/troubleshooting) | 1 TB daily change-data ceiling, capacity pause/resume/scaling behaviour, stop-replication semantics, no ownership change, LOB truncation, "view is not supported" | ms.date 2026-03-18, upd. 2026-07-26 |
| [Automatic reseed (Azure SQL Database)](https://learn.microsoft.com/en-us/fabric/mirroring/azure-sql-database-automatic-reseed) | autoreseed trigger conditions, `reseed_state`/`state = 7`, log-reuse diagnosis, long-pause reseed | ms.date 2025-10-15, upd. 2026-07-06 |
| [Azure SQL Database mirroring FAQ](https://learn.microsoft.com/en-us/fabric/mirroring/azure-sql-database-mirroring-faq) | "near real-time latency", initial-replication answer, "entire table is fetched again", egress by region, failover needs stop/start | ms.date 2026-10-08, upd. 2026-11-06 |
| [Extended capabilities in mirroring](https://learn.microsoft.com/en-us/fabric/mirroring/extended-capabilities) and [billing](https://learn.microsoft.com/en-us/fabric/mirroring/extended-capabilities-billing) | GA status for CDF and views, free core mirroring, 3 CU-hours on `DataMovementIncrementalCopy`, per-second billing, no double charge | ms.date 2026-06-24, upd. 2026-10-27 / ms.date 2026-03-11, upd. 2026-05-06 |
| [Pricing for copy job](https://learn.microsoft.com/en-us/fabric/data-factory/pricing-copy-job) | the `DataMovementIncrementalCopy` rate the mirroring meter reuses ("3 CUs hours") | ms.date 2026-05-18 |
| [CI/CD for mirrored databases](https://learn.microsoft.com/en-us/fabric/mirroring/mirrored-database-cicd) | `mirroring.json` in Git, deployment pipelines and data source rules, "not started after deployment", only the item is tracked | ms.date 2026-03-18, upd. 2026-03-19 |
| [Microsoft Fabric pricing](https://azure.microsoft.com/en-us/pricing/details/microsoft-fabric/) | the free-mirroring-storage ladder by SKU, trial exclusion, billing while paused | read 2026-11-12 |

# How do warehouse and lakehouse schemas get versioned, deployed and evolved when item deployment only ships shells?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's pipeline stage design (where DDL runs), and any promise that "merge to main" produces a working warehouse or lakehouse rather than an empty shell.
- **Sibling notes:** [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) for which types deploy at all; ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) for the shell-only consequence.

## Short answer

`fabric-cicd` deploys *no* warehouse, SQL-database or lakehouse content: the shell arrives and the schema does not, so a green pipeline can leave an empty database. Fabric's own Git sync does carry warehouse schema — as a SQL database project deployed by DacFx — but that is a different mechanism from the one this repo chose, and `fabric-cicd` never reads it. The workable answer is a second, ordered step against the TDS endpoint (`sqlpackage` for warehouse, `dbt-fabricspark` or notebook DDL for lakehouse), run after item deployment, with its own drift check because the redeploy-every-merge model does not revert or detect DDL changes.

## Detail

### 1. What is deployed, and what the item definition actually contains

Three different things get conflated: the item *shell*, the item *definition* parts, and the database *objects*. They diverge per item type.

| | Warehouse | SQL database | Lakehouse |
| --- | --- | --- | --- |
| Definition parts | `.platform` plus, when Git-bound, a whole SQL database project | `.platform`; Git-bound it carries the database objects | `alm.settings.json`, `shortcuts.metadata.json`, `data-access-roles.json`, metadata JSON |
| What `fabric-cicd` deploys | **"Warehouse content is not deployed. Only the item shell is deployed. Warehouse DDL must be deployed separately using a DACPAC or other tools such as dbt."** | **"SQL Database content is not deployed. Only the item shell is deployed. The SQL database schema (DDL) must be deployed separately using a DACPAC or other tools such as dbt."** | **"Schemas are not deployed unless the schema has a shortcut present."** |
| What Fabric Git sync deploys | Schema, as a database project: "the schema appears as individual `.sql` files", applied by "**DacFx-based incremental schema deployment**" | "modify the database objects while leaving existing data in place" | Metadata only: **"Tables (Delta and non-Delta) ❌ Not tracked"**, "Spark views ❌ Not tracked" |
| Never deployed | SQL security: "roles, users, and `GRANT`/`DENY` permissions aren't included in the SQL database project" | collation and compatibility level | table data, table schema, Spark views, Files folders |

The warehouse Git page also calls the database project "the authoritative representation of the warehouse schema in source control" and says objects are stored as `.sql` files "that contains its data definition language (DDL) syntax, such as `CREATE TABLE`", describing "the *desired state* of the schema". So the repo can hold DDL, and one Microsoft mechanism can apply it — but not the one ADR 0003 picked. On a lakehouse, "**git and deployment operations never overwrite data in tables or files**", which is the documented reason tables are out of scope rather than an oversight.

### 2. DDL as code: five routes and their real limits

| Route | Fabric endpoint | Verified support | What it cannot do |
| --- | --- | --- | --- |
| `dbt-fabric` | Warehouse TDS (`<id>.datawarehouse.fabric.microsoft.com`) | Microsoft-maintained adapter, `type: fabric`, driver `mssql-python` | No SQL authentication. Keys are `NONCLUSTERED NOT ENFORCED` / `NOT ENFORCED`, "Warehouse does not enforce those keys during subsequent DML". DDL holds catalog locks that stall `list_<schema>`; own docs recommend `threads: 4`–`8`, `query_timeout: 30`, `flags: cache_selected_only: true` for 500+ models |
| `dbt-fabricspark` | Lakehouse via Livy, or an in-process session | Microsoft-maintained, `type: fabricspark`, autodetects schema-enabled lakehouses via `properties.defaultSchema` | Spark semantics throughout (see §4); 4-part naming needs a schema-enabled lakehouse; `method: session` cannot create a remote schema |
| `.sqlproj` + `sqlpackage` | Warehouse **and** SQL database | Explicit: "SqlPackage and DacFx supports … **Fabric Data Warehouse**". Warehouse projects target `Synapse Data Warehouse in Microsoft Fabric`, DSP `SqlDwUnifiedDatabaseSchemaProvider`, package `Microsoft.SqlServer.Dacpacs.FabricDw`; "Only **SDK-style** projects are supported" | Preview. Publish is a schema diff, so it owns *every* object in scope — `DropObjectsNotInSource` "can **delete important objects and data**". Procs, views, security and seed data go in single-file `predeploy`/`postdeploy` scripts |
| T-SQL scripts from any TDS client | Warehouse | The endpoint is "a Tabular Data Stream (TDS) endpoint", TCP 1433; documented clients are SSMS 19+, ODBC 18+, OLE DB, JDBC, dbt, `%%tsql` | No SQL auth; MARS must be off; `InitialCatalog` required or you land in `master`; **`CREATE USER` is unsupported**, so a `GRANT` can only target principals that already exist |
| Notebook `%%tsql` | Warehouse | "`%%tsql -artifact <warehouse> -type Warehouse`", bindable to a dataframe | A notebook item, so it deploys through `fabric-cicd` — but it is a *runner*, not a schema model: no diff, no ordering, and a failure is just a failed cell |

`sqlcmd` specifically: the Warehouse docs name SSMS, ODBC, OLE DB, JDBC and dbt, and never name `sqlcmd`. **Could not establish** that `sqlcmd` is supported against the warehouse endpoint; the SQL database limitations page lists `sqlcmd` as "Yes" for that item only. Same gap for a Fabric Data Pipeline script activity targeting a warehouse: **could not establish**.

### 3. Transactions, `CREATE OR ALTER`, and whether a failed migration rolls back

Warehouse DDL is transactional, but only for an enumerated list. "If any statement in the transaction fails, all schema changes are automatically rolled back", and the supported-in-transaction list is: `CREATE TABLE`, `DROP TABLE`, `TRUNCATE TABLE`, `CTAS`, `sp_rename`, `ALTER TABLE` add nullable columns, `ALTER TABLE` drop columns, add/drop `PRIMARY KEY`/`UNIQUE`/`FOREIGN KEY` **with `NOT ENFORCED`**, multiple `ALTER TABLE`, `ALTER TABLE` on distributed temp tables, "Supported `ALTER COLUMN` operations".

Three consequences:

- **Views, procedures, functions and `CREATE SCHEMA` are not on that list.** A migration that mixes table DDL with programmable objects cannot claim atomicity for the whole script.
- Limitations: "`Save points` are not supported", "`Named transactions` are not supported", "`Distributed transactions` are not supported". DDL also takes `Sch-M` locks that "prevent all concurrent access to the table", and blocks `SELECT`s on `sys.tables`/`sys.objects` for the transaction's duration — so a migration during load hours blocks readers.
- Rolling back leaves residue: "If a transaction has data insertion into an empty table and issues a SELECT before rolling back, the automatically generated statistics can still reflect the uncommitted data".

`CREATE OR ALTER` exists for both programmable objects in the Fabric syntax blocks — `CREATE [ OR ALTER ] VIEW` and `CREATE [ OR ALTER ] { PROC | PROCEDURE }` — which is what makes a re-runnable script possible at all. But the prose under each contradicts it: the view page's `OR ALTER` argument says "**Applies to**: Azure SQL Database and SQL Server", while the procedure page says "Azure SQL Database, **SQL database in Microsoft Fabric**, SQL Server". Treat warehouse `CREATE OR ALTER` as *syntax-documented, behaviour-unverified* and test it before depending on it.

There is no `CREATE OR ALTER TABLE`. Tables move by `CREATE TABLE`, `ALTER TABLE` (nullable adds and drops only), or `CTAS` + rename via `sp_rename`.

### 4. Schema evolution

**Lakehouse / Delta.** "By default, Delta Lake enforces schema on write… Delta rejects the write instead of silently changing the table." Opt in with `mergeSchema` ("supports additive changes… It doesn't remove existing columns, and it doesn't change existing column types") or the session setting `spark.databricks.delta.schema.autoMerge.enabled`. Dropping or renaming needs column mapping enabled *before* the change: `ALTER TABLE … SET TBLPROPERTIES ('delta.columnMapping.mode' = 'name')`, otherwise you are left with `overwriteSchema`, which "is destructive to the schema contract". Widening (`int`→`bigint`) needs `delta.enableTypeWidening`, which "restricts which clients can access the table" by setting a table feature — irreversible for older readers. `MERGE WITH SCHEMA EVOLUTION INTO` adds source columns as part of the upsert. `dbt-fabricspark` exposes all of this as `merge_with_schema_evolution`, `on_schema_change: sync_all_columns | sync_remove_only`, and `enable_column_mapping_on_drop` (which "upgrades the table protocol to at least reader version 2 / writer version 5, so older Delta readers can no longer read the table").

**Warehouse.** `MERGE` "is supported and is a generally available feature", but it does not evolve anything: there is no schema-evolution equivalent, so a changed model shape must be an explicit `ALTER TABLE`. `ALTER TABLE` accepts only nullable `ADD`, `DROP COLUMN`, `NOT ENFORCED` constraints; "All other `ALTER TABLE` operations are blocked", and `ALTER COLUMN` "is in preview". Tables also refuse: computed columns, partitioned tables, sequences, unique indexes, user-defined types, external tables, triggers, synonyms, and cap at 1,024 columns — every one of which a SQL Server-shaped migration will eventually try.

### 5. Ordering and state

Three models, and only one of them uses a ledger:

- **State-based (DacFx / `.sqlproj`).** No migrations table. The project holds desired state; publish "automatically creat[es] a deployment plan that applies the necessary changes". Ordering comes from dependency analysis in the project, not from file names. Idempotence is free *for schema*, and only for schema: `PreDeploy`/`PostDeploy` "run on every warehouse deployment. The Transact-SQL scripts should be idempotent".
- **DAG-based (dbt).** No ledger either. `ref()` orders models; each model is reconciled to its definition on every run, with `--full-refresh` when the shape is incompatible. dbt's own docs describe `state:modified` plus `--defer` as comparing against a previous `manifest.json`, not against an applied-migrations record.
- **Ordered scripts (a migrations table).** Nothing in Fabric provides one; it is a table you create. A workable shape is `dbo.__schema_migrations(version, checksum, applied_at, applied_by)`, the row inserted in the *same* transaction as the DDL so a failed script leaves no row — which only holds for the statement list in §3. This is the pattern to pick when you want the order of operations to be reviewable in a diff.

Interaction with a redeploy-every-merge pipeline: `fabric-cicd` "deploys everything on every run and does not diff commits" (ADR 0003), and for these three item types it does not touch DDL at all. So the item stage neither applies migrations nor replays them; it is orthogonal, and its only ordering requirement is that the shell exists first.

### 6. Drift

**A DDL change made in the portal is invisible to the item pipeline, and is not reverted by it.** `fabric-cicd` re-posts the shell; the warehouse tables, views and procedures are left exactly as the portal left them. Two artefacts make this worse: Git sync's own caveats ("If you change a column that has `IDENTITY` defined, committing or updating from Git can fail until `IDENTITY_INSERT` is enabled"; "If the repository contains a `.sqlproj` file that pins an older `Microsoft.Build.Sql` SDK version, committing or updating from Git can fail"), and the SQL database rule that "Changes made to the `.sqlproj` file in the source control repository will not persist after deployment".

Cheapest detection, in order:

1. **`sqlpackage /Action:DeployReport`** — "Creates an XML report representing the changes that a publish action would take", plus `/Action:Script` to see the T-SQL. Build the `.dacpac` from the repo, diff it against the live endpoint, fail the build on a non-empty report. This is the only route that compares *intent* to *reality* without changing anything.
2. **Catalog query** — `sys.tables`, `sys.columns`, `sys.sql_modules` hashed into a committed manifest. Cheaper, but it detects only what you thought to hash.
3. **Lakehouse: nothing automatic.** Tables are untracked; `DESCRIBE TABLE` / the OneLake table APIs are the only read path, and a schema change there is legitimate data evolution unless you have a contract to compare against.

### 7. What a team should do

Treat the two layers as separate stages with separate failure modes:

- **Stage A — items (`fabric-cicd`).** Shells, notebooks, pipelines, semantic models. Fast, idempotent, and allowed to be "replace what is there".
- **Stage B — schema (same pipeline, later step, different command).** Warehouse: build the `.sqlproj`, `DeployReport` against the target, then `Publish` with `BlockOnPossibleDataLoss=true`; keep `DropObjectsNotInSource` off outside dev/test. Security, seed and one-off data fixes go in `predeploy.sql`/`postdeploy.sql`. Lakehouse: `dbt-fabricspark` for modelled tables, notebook DDL for everything else.
- **Why a separate step, not the same command.** The two have different blast radii and different identities: item deployment is a workspace-Contributor operation over the REST API, schema deployment is a TDS session with `ALTER` rights. Bundling them means a schema failure reports as a failed deployment of the whole item set, and there is no way to re-run just the DDL.
- **Why not a separate *pipeline*.** Stage B is meaningless before Stage A has created the shell, and a second pipeline reintroduces the ordering problem the runbook already solves. Keep it in the same run, after item deployment, gated on the environment.
- **If DacFx is too much.** Because it is preview and owns every object in scope, the fallback is ordered scripts plus `__schema_migrations`, run from a notebook item so the runner is itself versioned. Slower to write, far smaller blast radius, and it keeps security scripts (which DacFx does not model anyway) in the same mechanism as the tables.

## What this settles

- **A green item pipeline is not a deployed database.** For Warehouse, SQL database and Lakehouse, `fabric-cicd` ships a shell; DDL is a second step, always.
- **Recommendation: `.sqlproj` + `sqlpackage` for warehouse schema, `dbt-fabricspark` for lakehouse tables, notebook T-SQL for anything neither models — run as a distinct step after item deployment in the same pipeline.** `DeployReport` is the drift gate; there is no ledger to maintain because DacFx is state-based.
- **Fallback if DacFx preview is unacceptable: ordered `.sql` files + a `__schema_migrations` table**, one transaction per script, restricted to the statement list in §3.
- **DDL drift is real and silent.** Portal schema edits survive every merge; only a schema comparison finds them.
- **Never put schema in the same command as item deployment**, and never claim atomicity for a script containing views, procedures or `CREATE SCHEMA`.

## What this does not establish

- Whether `sqlcmd` or a Data Pipeline script activity can target the warehouse endpoint. Neither is documented; both are plausible because it is an ordinary TDS endpoint.
- Whether `CREATE OR ALTER` actually executes on Warehouse. The syntax blocks include it, the "Applies to" prose does not.
- Whether `sqlpackage Publish` wraps its generated script in a transaction on Warehouse, so whether a mid-publish failure leaves a half-applied schema. Assume not until tested.
- What database role a workspace Contributor (or the deploy service principal) receives inside a warehouse, and therefore whether Stage B can use the same identity as Stage A.
- Whether Fabric *deployment pipelines* apply warehouse schema through the same DacFx diff as Git sync. The deployment-scripts page shows script designations travelling with promotion, but the schema path is not stated.
- What `fabric-cicd` does when a warehouse definition folder contains a `.sqlproj` — ignored, error, or posted as an inert definition part.
- Whether `MERGE` in the warehouse can be made to tolerate new source columns at all; the docs describe no equivalent of Delta's schema evolution.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [cicd-types] | "Only the item shell is deployed" for Warehouse and SQL Database; "Schemas are not deployed" for Lakehouse | read 2026-11-12 |
| [wh-git] | database-project schema in Git, "DacFx-based incremental schema deployment", SQL security not in project, `.sqlproj` SDK and `IDENTITY` caveats | ms.date 2026-08-13, upd. 2026-09-22 |
| [wh-deploy] | IDE/deployment routes; "Supported via DacFx tasks, SQLPackage CLI, and REST APIs" | ms.date 2026-07-30, upd. 2026-09-22 |
| [wh-project] | SDK-style only, target platform, `Microsoft.SqlServer.Dacpacs.FabricDw`, `BlockOnPossibleDataLoss`, `DropObjectsNotInSource` | ms.date 2026-09-22, upd. 2026-10-01 |
| [wh-scripts] | `PreDeploy`/`PostDeploy`, single file, no `:r`, run on every deployment, idempotency requirement | ms.date 2026-09-30, upd. 2026-10-01 |
| [wh-tx] | transactional DDL statement list, rollback, no savepoints/named/distributed, `Sch-M` locking, statistics residue | ms.date 2026-06-03, upd. 2026-06-14 |
| [wh-tsql] | `ALTER TABLE` subset, `MERGE` GA, `CREATE USER` unsupported, unsupported-command list | ms.date 2026-09-16, upd. 2026-10-14 |
| [wh-tables] | `CREATE SCHEMA`, table limits, `NOT ENFORCED` keys, 1,024 columns | ms.date 2026-10-13, upd. 2026-10-14 |
| [wh-conn] | TDS endpoint, Entra-only auth, no MARS, `InitialCatalog` behaviour | ms.date 2026-09-09 |
| [wh-connect] | documented client tools; `%%tsql` magic; dbt adapter guidance | ms.date 2026-05-13, upd. 2026-09-29 |
| [create-view] / [create-proc] | `CREATE [ OR ALTER ]` in the Fabric syntax blocks, and the contradictory "Applies to" prose | upd. 2026-10-19 |
| [sqldb-limits] | source control "modify the database objects", `.sqlproj` reset on commit, collation not in ALM, `sqlcmd` = Yes | ms.date 2026-08-24, upd. 2026-10-03 |
| [sqlpackage-fabric] | SQL database import/export/extract/publish, `AllowIncompatiblePlatform`, `ExcludeObjectTypes=Logins;Users` | ms.date 2025-08-08, upd. 2026-07-08 |
| [sqlpackage] | `DeployReport`/`Script`/`DriftReport`; "SqlPackage and DacFx supports … Fabric Data Warehouse" | ms.date 2025-03-02, upd. 2026-10-19 |
| [lh-git] | tables and Spark views not tracked; metadata-only sync | ms.date 2026-10-13 |
| [lh-schemas] | schema-enabled lakehouse, `enableSchemas`, `dbo` default | ms.date 2026-02-24, upd. 2026-08-04 |
| [delta-evolve] | schema enforcement, `mergeSchema`, `columnMapping`, type widening, `MERGE WITH SCHEMA EVOLUTION` | ms.date 2026-05-18, upd. 2026-07-18 |
| [dbt-fabric] | `type: fabric`, `mssql-python`, `NOT ENFORCED` keys, catalog-lock guidance, rollback-on-close | read 2026-11-12 |
| [dbt-fabricspark] | Livy/session modes, schema detection, `merge_with_schema_evolution`, `on_schema_change`, column mapping, `OPTIMIZE` | read 2026-11-12 |
| [dbt-state] | `state:modified` / `--defer` compare a previous manifest, not an applied-migrations record | read 2026-11-12 |

[wh-git]: https://learn.microsoft.com/en-us/fabric/data-warehouse/git-integration
[wh-deploy]: https://learn.microsoft.com/en-us/fabric/data-warehouse/development-deployment
[wh-project]: https://learn.microsoft.com/en-us/fabric/data-warehouse/develop-warehouse-project
[wh-scripts]: https://learn.microsoft.com/en-us/fabric/data-warehouse/deployment-scripts
[wh-tx]: https://learn.microsoft.com/en-us/fabric/data-warehouse/transactions
[wh-tsql]: https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area
[wh-tables]: https://learn.microsoft.com/en-us/fabric/data-warehouse/tables
[wh-conn]: https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity
[wh-connect]: https://learn.microsoft.com/en-us/fabric/data-warehouse/how-to-connect
[create-view]: https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql?view=fabric&preserve-view=true
[create-proc]: https://learn.microsoft.com/en-us/sql/t-sql/statements/create-procedure-transact-sql?view=fabric&preserve-view=true
[sqldb-limits]: https://learn.microsoft.com/en-us/fabric/database/sql/limitations
[sqlpackage-fabric]: https://learn.microsoft.com/en-us/fabric/database/sql/sqlpackage
[sqlpackage]: https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage
[lh-git]: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-git-deployment-pipelines
[lh-schemas]: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-schemas
[delta-evolve]: https://learn.microsoft.com/en-us/fabric/data-engineering/delta-lake-schema-evolution
[cicd-types]: https://microsoft.github.io/fabric-cicd/latest/reference/item_types/
[dbt-fabric]: https://github.com/microsoft/dbt-fabric
[dbt-fabricspark]: https://github.com/microsoft/dbt-fabricspark
[dbt-state]: https://docs.getdbt.com/reference/node-selection/state-selection

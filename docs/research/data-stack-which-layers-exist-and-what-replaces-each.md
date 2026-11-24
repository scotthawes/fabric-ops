# What layers does a modern Microsoft-centric data platform actually have, what does Fabric and Azure Databricks provide at each, and what motion does moving from this estate require?

- **Status:** answered
- **Checked:** 2026-11-24
- **Blocks:** the destination decision (Fabric, Databricks, or a deliberate split), the work repo's migration plan, and the replacement of the shared rebuild-everything deployment pipeline.
- **Sibling notes:** [`platform-taxonomy.md`](platform-taxonomy.md) for Fabric's own vocabulary; [`schema-and-ddl-management.md`](schema-and-ddl-management.md) for DDL; [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md) for CU mechanics; [`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md) for mirroring; [`business-continuity-what-does-fabric-guarantee.md`](business-continuity-what-does-fabric-guarantee.md) for DR; [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) for what deploys; [`deployment-mechanism-comparison.md`](deployment-mechanism-comparison.md), [`terraform-operating-model.md`](terraform-operating-model.md) and [`terraform-provider-surface.md`](terraform-provider-surface.md) for the Fabric deployment mechanisms.

## Short answer

Ten capability layers carry the estate, and they do not move together. The on-premises SQL Server OLTP **does not move at all**; it is read, not replaced. The Azure SQL Database warehouse and the ADF estate are the two real migrations; `sqlproj` is a deployment artefact whose fate depends on the destination.

**Fabric is the lower-motion destination for this estate**, because three of the four layers that move have a documented Microsoft translation path: ADF has an official upgrade guide and a built-in assessment experience; Azure SQL Database is an explicitly supported source for the Fabric Migration Assistant; and `.sqlproj`/SqlPackage is the documented Fabric warehouse schema route. **Databricks is a rebuild**, not a refactor: T-SQL becomes Spark SQL, ADF becomes Lakeflow Jobs or Lakeflow Connect, and `sqlproj` disappears in favour of Unity Catalog objects plus dbt or migration SQL. It is the better destination only if the team intends to rewrite the compute model and make Unity Catalog the governance anchor.

For this team specifically — three delivery engineers whose strongest skills are ADF and T-SQL, two DBAs who stay on the on-premises source, and **least operational burden as the deciding priority** — Fabric is the answer on the stated intent. Databricks is a **strategic branch, not a skills gate**: legitimate if the team intends to become Python/Spark-first and names a platform owner (internal or hired), with the T-SQL rewrite as a one-time cost and the added planes as the recurring one. Section 11 carries the toil count and names the ADR assumptions it complicates.

One premise has moved under the question. **Microsoft Purview's data-governance capability — Unified Catalog and classic Data Map/catalog/lineage — is being retired, with new accounts blocked and maintenance through 2027-11-12, consolidated into Microsoft Fabric**; Purview data security and compliance, including sensitivity labels, are not part of that retirement. A new Microsoft-centric estate should therefore target **Fabric's own catalog**, not a new Purview account. For Databricks, the Microsoft-native governance bridge is Unity Catalog plus Fabric's metadata mirroring of it, not a Purview scan.

## Detail

### 0. The spine, and what "motion" means here

These are capability layers, not Microsoft product names. Fabric's own containment vocabulary stays **tenant → capacity → workspace → item**, and its storage layer stays **OneLake** ([`platform-taxonomy.md`](platform-taxonomy.md)). The spine is used only to compare destinations.

| Motion | Meaning in this note |
| --- | --- |
| **Rehost** | Move the component with configuration changes only; code and semantics survive. |
| **Refactor** | Change code, schema or deployment shape to fit the destination, but keep the model and most logic. |
| **Rebuild** | Redesign the component on a different execution model; the old code is evidence, not a deliverable. |
| **Retire** | Decommission it; the destination has no equivalent, or the function is no longer wanted. |

The estate as given, and the assumption stated once: the table names four layers, not a BI tool. Where Power BI or Purview is named below, it is because the constraint names them or because the layer cannot be discussed without one; the note does not assume the estate already runs them.

| Layer | Today | Fabric provides | Azure Databricks provides | Motion, and why |
| --- | --- | --- | --- | --- |
| **Source / ingestion** | SQL Server OLTP on-premises; ADF pipelines and dataflows | Mirroring (SQL Server GA), Copy job, pipeline Copy activity, Dataflow Gen2, dbt job, Apache Airflow job, mounted ADF item | Lakeflow Connect (SQL Server CDC/query), Auto Loader/`COPY INTO`, Lakehouse Federation (read-only) | **Fabric: refactor** — ADF has a documented upgrade path and ~90% activity continuity. **Databricks: rebuild** — no documented ADF converter; Lakeflow is a different programming model. **OLTP: stays.** |
| **Storage** | Azure SQL Database as the warehouse | OneLake; Warehouse and lakehouse tables in Delta; Iceberg metadata virtualisation; shortcuts | ADLS Gen2 + Delta Lake; Unity Catalog managed and external tables; managed Iceberg | **Fabric: refactor** — schema conversion plus a data copy into Delta. **Databricks: rebuild** — new storage layout and catalog. Neither rehosts Azure SQL Database. |
| **Compute / transformation** | Azure SQL Database T-SQL engine | Warehouse T-SQL engine; lakehouse SQL analytics endpoint (read-only); Spark notebooks and jobs | Databricks SQL warehouse (Spark SQL); Spark; Lakeflow pipelines | **Fabric: refactor** — T-SQL survives with a reduced surface. **Databricks: rebuild** — T-SQL is rewritten to Spark SQL. |
| **Orchestration** | ADF pipelines, triggers, integration runtimes | Data Factory pipelines, schedules and event triggers, Airflow jobs, Invoke pipeline | Lakeflow Jobs (jobs, tasks, triggers), bundles | **Fabric: refactor.** **Databricks: rebuild.** A mounted ADF factory is a transition view, not a destination: execution stays in Azure. |
| **Semantic / BI** | Not stated in the estate table; Power BI is assumed where a semantic layer exists | Semantic model, report, Direct Lake over OneLake, XMLA | AI/BI dashboards and Genie; Power BI through the Azure Databricks connector (Import/DirectQuery) | **Fabric: rehost/refactor** — Power BI stays native. **Databricks: refactor** — Power BI can stay, but as an external consumer; Direct Lake is not available over Databricks. |
| **Catalog / governance** | Purview catalog and lineage, per the stated constraint | OneLake catalog, domains, sensitivity labels, endorsement; Purview scan optional | Unity Catalog (native); Purview scan of Unity Catalog (one-way) | **Fabric: refactor** to Fabric's catalog. **Databricks: rebuild** into Unity Catalog. Purview data governance is retiring, so it is not a new-estate anchor. |
| **Identity / security** | Microsoft Entra ID | Entra-native; workspace roles; OneLake data-access roles; no SQL authentication on the T-SQL endpoint | Account-level identities synced from Entra; Unity Catalog privileges; no SQL-warehouse credential passthrough | **Fabric: rehost** — Entra is the identity system already. **Databricks: rehost plus sync** — Entra stays the source, but Databricks keeps account principals and UC grants. |
| **Deployment / CI** | One shared ADO YAML; ADF as a committed ARM export; Terraform for Azure; `.sqlproj` for schema; one run builds dev, test and prod in sequence | Git integration (authoring), deployment pipelines (promotion), `fabric-cicd` (item definitions), Terraform (containers), SqlPackage/dbt (schema) | Declarative Automation Bundles (`databricks.yml`, per-target deploy), Terraform (account, Azure, UC objects), dbt/migration SQL (tables) | **Fabric: refactor** the pipeline; **retire** the ARM export. **Databricks: rebuild** around bundle targets. Terraform keeps the container role in both. |
| **Observability** | ADF run history; Azure Monitor for Azure resources | Monitor hub, workspace monitoring, Capacity Metrics app; no Azure Monitor metrics for the capacity | System tables (`system.billing.usage`, `system.access.audit`, lineage), query history, job notifications; Azure Monitor diagnostic settings (partial) | **Both: rebuild.** Neither destination reads the ADF monitor or the existing Azure alerts. |
| **Cost** | Azure consumption: Azure SQL Database, ADF activity/data movement, storage | Capacity units (CU), smoothed; storage; overage; pause on F SKU | DBUs per SKU and usage; VM/disk for classic/pro; serverless DBUs; SQL warehouse cluster sizing | **Both: rebuild the cost model.** There is no CU-to-DBU conversion; the units and the commitment shape differ. |

Continuity is cross-cutting rather than a layer: Fabric's DR is an opt-in capacity setting plus a documented rebuild runbook, not a recovery guarantee ([`business-continuity-what-does-fabric-guarantee.md`](business-continuity-what-does-fabric-guarantee.md)). Databricks continuity is out of scope here and is not established.

### 1. Ingestion: what ADF maps to, and what has no equivalent

**Microsoft does publish an ADF-to-Fabric migration position.** The pages are [adf-upgrade] ("Upgrade Planning for Azure Data Factory to Fabric Data Factory", ms.date 2026-11-06) and [adf-compare] ("Differences between Data Factory in Fabric and Azure", ms.date 2026-11-06). The documented route is assessment-first, not a converter:

- **Mount the factory.** An "Azure Data Factory item" in Fabric gives a live view of an existing factory inside a workspace; "execution of pipelines, activities, and integration runtimes still occurs within your Azure resources" ([adf-upgrade]). This is a transition and discovery tool, not a migration.
- **Assess in ADF.** The built-in upgrade experience categorises each pipeline and activity as **Ready**, **Needs review**, **Coming soon** or **Not compatible**, then upgrades supported pipelines incrementally.
- **Manual upgrade** for low-parity or custom logic: recreate connections, activities, schedules and triggers.
- **Mapping Data Flows** are converted to **MDF transforms in Dataflow Gen2** when eligible; MDF transforms and the built-in MDF upgrade are GA ([adf-upgrade], [adf-mdf]).

| ADF artefact | Fabric destination | What changes |
| --- | --- | --- |
| Pipeline | Pipeline item (`pipeline-content.json`) | JSON shape differs; no publish step ("Save" or "Run") ([adf-compare]) |
| Copy activity | Copy activity; CDC work becomes a **Copy job** | CDC is not a separate ADF-style artefact in Fabric; Copy job owns incremental movement ([adf-compare]) |
| Mapping Data Flow | **MDF transforms in Dataflow Gen2** | Only eligible flows; flowlets, the Data Flow Library and UDFs are not supported; OPDG/VNet gateways are not supported for MDF transforms; direct execution is not supported, only via a pipeline Dataflow activity ([adf-mdf]) |
| Wrangling Data Flow / Power Query | Dataflow Gen2 | Power Query is fully integrated as dataflows ([adf-upgrade]) |
| Dataset | **No item** — properties are inline in the activity | Datasets disappear ([adf-compare]) |
| Linked service | **Connection** | Recreated; connections are not deployed by `fabric-cicd` ([item-definition-formats](item-definition-formats.md)) |
| Trigger | Schedule, event trigger, or tumbling-window-as-interval | "One schedule per pipeline … no schedule reuse or central hub"; Fabric has no ADF trigger-sharing equivalent ([adf-upgrade]) |
| Global parameters | **Variable Library** | Different implementation and data types; a conversion guide exists ([adf-upgrade]) |
| Execute pipeline | **Invoke pipeline** with a `FabricDataPipeline` connection | Activity name and connection requirements change ([adf-upgrade]) |
| Self-hosted integration runtime | **On-premises data gateway** | Windows-only, monthly manual updates, no Key Vault integration ([adf-compare]) |
| VNet integration runtime | **VNet data gateway** | Customer-managed VNet; node-based, not ADF's managed VNet ([adf-compare]) |
| Managed identity | **Workspace identity** | Different identity model; plan the shift ([adf-upgrade]) |
| Key Vault | Limited **Key Vault reference** | Compare supported connectors and auth types before assuming parity ([adf-upgrade]) |
| Custom activity | **Azure Batch activity** | Renamed; same functionality claimed ([adf-upgrade]) |
| Five HDInsight activities | **One HDInsight activity** | Consolidation ([adf-upgrade]) |
| Notebook / Jar / Python activity | **Databricks activity** | Replaced by one activity ([adf-upgrade]) |
| Validation activity | Get Metadata + If Condition | No direct activity ([adf-compare]) |
| SSIS | **No equivalent** | The comparison table says "To be determined"; SSIS is `N/A` in Fabric ([adf-compare]) |
| ADF managed VNet / private endpoints | **No equivalent yet** | "To be determined" ([adf-compare]) |
| Azure Synapse Link | **Mirroring** | Fabric replaces Synapse Link with mirroring ([adf-compare]) |

**What has no equivalent, stated plainly:** SSIS execution; ADF's managed virtual network and managed private endpoints; a shared trigger/schedule hub; dataset objects; the full Mapping Data Flow feature set (flowlets, Data Flow Library, UDFs); and gateway support for MDF transforms. Those are the items that turn "upgrade" into "rebuild" for a given pipeline.

**Databricks documents no ADF converter on the pages read here.** That is a documentation-search result, not proof of absence; Microsoft publishes the ADF-to-Fabric path, and Databricks publishes none. The Databricks-side ingestion primitives are:

- **Lakeflow Connect** managed connectors, including database CDC for SQL Server; on-premises sources connect through ExpressRoute or a gateway in a peered VNet ([dbx-lakeflow-connect]).
- **Auto Loader / `COPY INTO`** for file sources; **Lakehouse Federation** for read-only query of SQL Server, Azure SQL Database and Azure SQL Managed Instance through a Unity Catalog foreign catalog ([dbx-fed-sqlserver]).
- **Lakeflow Jobs** as the orchestrator; ADF can still *trigger* a Databricks job, but that keeps ADF in the estate ([dbx-jobs]).

**On-premises SQL Server, specifically.** Fabric's GA path is **mirroring** SQL Server 2016–2022 with CDC (2025 uses the Arc change feed); a gateway is required when the source is not reachable, and mirroring is copy-based, not metadata-only ([`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md)). The gateway constraint is the operational one: the on-premises data gateway runs on a Windows machine you own, is outbound-only, is updated monthly with no rollback, and **service-principal authentication for the SQL Server connector is documented only for SQL Server on Azure VMs** — an on-premises source falls back to a stored credential, cached for several hours ([`gateway-and-connectivity.md`](gateway-and-connectivity.md)). A pipeline or Copy job can read the same source through the same gateway when mirroring is not the right fit.

Databricks reads the same source two ways: **Lakehouse Federation** (read-only, no copy; SQL Server/Azure SQL Database/Azure SQL Managed Instance; SQL warehouses must be pro or serverless; window functions are not pushed down) ([dbx-fed-sqlserver]), or **Lakeflow Connect CDC** (copy, with its own ingestion gateway, and on-premises connectivity via ExpressRoute) ([dbx-lakeflow-connect]). Federation is the "least movement" option for a source that stays put; CDC is the option when the lake needs a copy.

### 2. Storage: OneLake versus ADLS and Unity Catalog

Fabric has one storage layer per tenant. OneLake "stores tables in Delta Parquet or Iceberg format"; Warehouse and lakehouse tables land in Delta; shortcuts reference data without copying; mirroring copies; metadata mirroring does not ([`platform-taxonomy.md`](platform-taxonomy.md), [onelake-overview]).

Databricks has no OneLake equivalent: tables are Delta (or managed Iceberg) in ADLS Gen2, registered in Unity Catalog as managed or external; volumes hold files. The storage layer is Azure either way, but it is not the same account, path model or catalog.

**Open formats, and which direction each supports.** This is asymmetric and easy to overstate.

| Direction | Fabric | Databricks |
| --- | --- | --- |
| **Delta written, Iceberg read** | Yes — Delta tables "include virtual Iceberg metadata, allowing compatibility with Iceberg readers"; metadata virtualisation produces Iceberg V2 metadata ([onelake-iceberg]) | Yes — **UniForm** generates Iceberg metadata alongside Delta without rewriting Parquet; Iceberg clients read Delta; Runtime 14.3+ ([dbx-uniform]) |
| **Iceberg written, Delta read** | Yes — writing or shortcutting an Iceberg table generates virtual Delta metadata, so Fabric engines read it as Delta; Iceberg V2 fully, V3 partially ([onelake-iceberg]) | Yes for **managed Iceberg** tables in Unity Catalog (read and write through the Iceberg REST catalog); **foreign Iceberg** is read-only ([dbx-iceberg-catalog]) |
| **Caveats** | Parquet data files only in both directions; only the latest metadata version is converted ([onelake-iceberg]) | Delta tables exposed to Iceberg clients are **read-only** for those clients; column mapping and deletion-vector constraints apply ([dbx-uniform]) |

So the honest statement is: Fabric virtualises **both** directions for Parquet-backed tables; Databricks supports **native managed Iceberg** plus **Delta-to-Iceberg read exposure**, but not Iceberg-client writes to a Delta table.

**Motion.** Azure SQL Database data does not rehost into either destination. Fabric's **Migration Assistant** is the documented route: it takes a DACPAC upload or a direct connection, converts tables, views, functions, stored procedures and most security objects, then copies data with a Copy job ([fabric-migrate]); the direct-connection how-to explicitly tells you to select **SQL Server database** for "SQL Server, Azure SQL Database, or Azure SQL Managed Instance" ([fabric-migrate-connect]). That makes the warehouse motion **refactor**, not rebuild: the schema is converted and the data copied, with the incompatible objects listed for repair. Databricks has no equivalent first-party schema converter; the table model is rebuilt in Delta, and T-SQL is translated or rewritten. Databricks Labs **Lakebridge** exists as a migration accelerator, but its own README says it is "provided for your exploration only and is not formally supported by Databricks with Service Level Agreements" ([dbx-lakebridge]) — useful, not a supported migration product.

### 3. Compute: three T-SQL destinations, and what each does not do

The compute layer is where "T-SQL user" expectations break, and the three candidates fail differently.

| Expectation | Fabric Warehouse | Lakehouse SQL analytics endpoint | Databricks SQL warehouse |
| --- | --- | --- | --- |
| **DML** (`INSERT`/`UPDATE`/`DELETE`) | Yes | **No** — read-only over Delta; modify through Spark ([lh-endpoint]) | Yes (`MERGE INTO`, `UPDATE`, `DELETE`) ([dbx-merge]) |
| **Multi-statement transactions** | DDL is transactional only for an enumerated list (`CREATE TABLE`, `DROP TABLE`, `TRUNCATE`, `CTAS`, `sp_rename`, some `ALTER TABLE`, `NOT ENFORCED` constraints); no savepoints, named or distributed transactions; views, procedures and `CREATE SCHEMA` are outside the list ([`schema-and-ddl-management.md`](schema-and-ddl-management.md)) | Not applicable — read-only | `BEGIN ATOMIC` on Unity Catalog **managed** tables with **catalog commits** enabled, on a SQL warehouse, serverless compute or Runtime 18.0+; no nesting ([dbx-atomic]) |
| **`MERGE`** | GA, but no documented schema-evolution equivalent; a changed source shape is an explicit `ALTER TABLE`, and whether `MERGE` tolerates new source columns is unverified ([`schema-and-ddl-management.md`](schema-and-ddl-management.md)) | Not applicable | `MERGE INTO` is supported for Delta tables, with `WITH SCHEMA EVOLUTION` from Runtime 15.2 ([dbx-merge]) |
| **Cross-database queries** | Same workspace only: three-part names work for warehouses/lakehouses added to Explorer in the **current workspace**; direct cross-workspace table access is not supported, and a shortcut is the workaround ([wh-query]) | Same engine and limits | Three-level `catalog.schema.table` across catalogs in the metastore ([dbx-sql-ref]) |
| **Cross-region** | Not supported: Warehouse and SQL analytics endpoint connections require source and target in the same region ([wh-limits]) | Same | Not established here |
| **SQL logins / `CREATE USER`** | `CREATE USER` is unsupported; T-SQL endpoint is Entra-only ([`schema-and-ddl-management.md`](schema-and-ddl-management.md)) | Same | No T-SQL SQL-login path; identities are account principals and UC grants ([dbx-aim]) |
| **Recursive queries** | Unsupported ([wh-tsql]) | Shared engine limits | Not checked |
| **Materialized views** | Unsupported ([wh-tsql]) | Unsupported | `CREATE MATERIALIZED VIEW` is in the SQL reference ([dbx-sql-ref]) |
| **Synonyms / triggers** | Unsupported ([wh-tsql]) | Unsupported | Not checked |
| **`ALTER TABLE` breadth** | Add nullable columns, drop columns, add/drop `NOT ENFORCED` constraints; other operations blocked; `ALTER COLUMN` in preview ([wh-tsql]) | Read-only | Broad Delta DDL ([dbx-sql-ref]) |
| **`sqlproj` / SqlPackage** | Supported via DacFx/SqlPackage, **preview**, SDK-style projects only ([`schema-and-ddl-management.md`](schema-and-ddl-management.md)) | No item to publish; schema is Delta | No DacFx equivalent |
| **Dialect** | T-SQL subset ([wh-tsql]) | T-SQL subset, read-only | Spark SQL / ANSI, not T-SQL ([dbx-sql-ref]) |

Two additional traps matter to a T-SQL team:

- **Cross-workspace is the boundary, not cross-database.** The common assumption "three-part names work everywhere" is wrong in Fabric: they work inside one workspace, and a shortcut is the documented workaround across workspaces ([wh-query]).
- **The lakehouse endpoint is not a warehouse.** It exposes only Delta tables in `/tables`; external Delta tables in `/files` are invisible; Delta column mapping by ID is unsupported; and a workspace supports at most **150 warehouse and SQL analytics endpoint items combined** ([lh-endpoint]).

`SQL database in Fabric` is not the warehouse answer: it is an OLTP item capped at 32 vCores and 4 TB, with an automatic SQL analytics endpoint ([fabric-sql-db-limits]). It is worth naming only to stop it being proposed as a like-for-like Azure SQL Database replacement.

**Recommendation from the evidence:** if the T-SQL code and the `sqlproj` are assets worth preserving, **Fabric Warehouse** is the only destination that keeps both, at the cost of the reduced surface above. If the model is Delta-first and SQL is for reading, **lakehouse + SQL analytics endpoint** is cheaper and simpler, but it cannot be the write surface. **Databricks SQL** is the right choice only when the team accepts rewriting T-SQL into Spark SQL and wants Spark/ML in the same engine.

### 4. Orchestration: pipelines, jobs and the schedule gap

Fabric's orchestrator is the **Data Factory pipeline** item: activities, control flow, schedules, event triggers, `Invoke pipeline`, and Apache Airflow jobs for code-first DAGs ([adf-overview]). The differences that bite are ADF's shared schedule/trigger model and its publish step: Fabric has "one schedule per pipeline … no schedule reuse or central hub", and saves/runs rather than publishing ([adf-upgrade], [adf-compare]).

Databricks' orchestrator is **Lakeflow Jobs**: jobs contain tasks with dependencies (a DAG), triggers, notifications, and system-table telemetry; a workspace is limited to 2,000 concurrent task runs, 12,000 saved jobs and 1,000 tasks per job ([dbx-jobs]). Bundles deploy jobs and pipelines as code ([dbx-bundles]).

The motion follows the destination: ADF pipelines are **refactored** into Fabric pipelines (or run through a mounted ADF item during transition), and **rebuilt** as Lakeflow Jobs on Databricks. In both cases, **ADF is retired at cutover**; mounting it is a way to see and assess, not a way to run the new estate.

### 5. Schema deployment: `sqlproj` survives in one destination only

The Fabric half is settled in [`schema-and-ddl-management.md`](schema-and-ddl-management.md): `fabric-cicd` ships the warehouse shell and no DDL; `.sqlproj` + `sqlpackage` is the documented warehouse route (preview, SDK-style only, `Microsoft.SqlServer.Dacpacs.FabricDw`); `dbt-fabric` is the alternative for modelled tables; lakehouse tables need `dbt-fabricspark` or notebook DDL; `DeployReport` is the drift gate.

The Fabric **dbt job** is a deployable item, GA, with a managed runtime: adapters include `dbt-fabric` 1.10.0, `dbt-fabricspark` 1.12.2, `dbt-sqlserver` 1.9.1, `dbt-postgres` 1.10.0 and `dbt-snowflake` 1.11.5; limitations include no build caching, a 5,000-file import limit, `dbt_project.yml` at the repository root, and GitHub PAT-only authentication ([adf-dbt]). It is a runner, not a schema model; the DDL still has to be ordered and drift-checked.

On Databricks:

- **Unity Catalog** is the schema namespace: catalog → schema → table/view/volume, with grants.
- **Declarative Automation Bundles** deploy catalogs, schemas, volumes, SQL warehouses, jobs, pipelines and dashboards; the supported-resource table does **not** list a table or view resource ([dbx-bundles-resources]). So a bundle can create the container and the job that creates tables, but not the table definition itself.
- **Terraform** can go further: the official `databricks_sql_table` resource represents a managed table, external table or view ([dbx-tf-table]). That is a resource definition, not a state-based diff of arbitrary DDL; it does not model stored procedures or a `.sqlproj`.
- **dbt, Lakeflow pipelines, or migration SQL executed by a job** are the practical routes for table and view definitions. **Liquibase and Flyway are third-party tools with no first-party Databricks documentation**; they are not an authority for "supported" and are not cited as one here.
- **Transactions** are newer than a T-SQL team expects: `BEGIN ATOMIC` is Runtime 18.0+/SQL warehouse, Unity Catalog managed tables, catalog commits enabled, and no nesting ([dbx-atomic]).

| Deployment question | Fabric | Databricks |
| --- | --- | --- |
| Declarative container | Terraform (`fabric_workspace`), deployment pipelines, item definitions | Bundles (`catalogs`, `schemas`, `volumes`), Terraform |
| Table DDL | `.sqlproj` + SqlPackage; `dbt-fabric`; notebook T-SQL | dbt / Lakeflow pipeline / migration SQL; `databricks_sql_table` in Terraform |
| Diff before apply | `sqlpackage /Action:DeployReport` | No DacFx equivalent; dbt compares to a previous manifest, Terraform to state |
| Drift detection | DeployReport, or catalog hash | dbt state, Terraform plan (for Terraform-managed objects only) |
| Atomic multi-statement DDL | Only the listed statements; views/procs outside it | `BEGIN ATOMIC` with the constraints above |

There is no documented route that turns a `.sqlproj` into Databricks DDL. That is a rewrite, not a conversion.

### 6. Deployment and CI: replacing the shared rebuild-everything pipeline

#### 6.1 The current model, stated

The deployment layer today is one **shared ADO YAML pipeline**. ADF is authored in the ADF UI, exported as an **ARM template** and committed; Terraform holds the Azure infrastructure; `.sqlproj` holds the warehouse schema; one run rebuilds the ADF ARM deployment and the Terraform IaC and deploys **dev, then test, then prod in sequence**. A new pipeline, a new table or a new Azure resource is a change to that repository followed by the same whole-estate run.

That model has three properties worth naming before comparing replacements:

1. **The artefact is whole-estate.** There is no per-item unit of change; the unit is "the factory plus the infrastructure plus the database".
2. **The run is one blast radius.** If the YAML has no approval gate, a change that succeeds technically in dev is promoted to test and prod in the same run.
3. **The ADF artefact is an ARM export, not an item definition.** Fabric cannot consume it; Databricks cannot consume it. Whatever the destination, that artefact is retired.

#### 6.2 Three control-plane shapes

| | (a) Fabric Git + deployment pipelines + `fabric-cicd` | (b) Databricks Declarative Automation Bundles | (c) Plain ADO YAML calling CLI/APIs |
| --- | --- | --- | --- |
| **What triggers a deploy** | Merge/commit or a pipeline step; deployment pipelines are a separate workspace-to-workspace action | `databricks bundle deploy -t <target>` | Your YAML |
| **What is deployed** | Items from repo definitions (`fabric-cicd`) **or** items copied between paired stages (deployment pipelines) | Bundle resources: jobs, pipelines, dashboards, schemas, volumes, SQL warehouses | Whatever the script calls |
| **State** | `fabric-cicd` has no applied-state ledger and "deploys everything on every run and does not diff commits" (ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md)); deployment pipelines keep item pairing | Bundle state per target; a bundle's identity is name + target + deployer, and identical identities interfere ([dbx-bundles-tasks]) | You own it |
| **Promotion** | Deployment pipeline stages are adjacent; full, selective, or backward only to an empty stage ([dp-deploy]) | One target per workspace; deploy dev, then test, then prod | You own it |
| **Approval** | Deployment pipeline permission is a single Admin role; ADO environment approvals are separate ([`deployment-mechanism-comparison.md`](deployment-mechanism-comparison.md), [`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md)) | ADO environment approval around the `bundle deploy -t prod` job | ADO environment approval |
| **Selective deploy** | Deployment pipelines: yes, per item, with "Select related" for dependencies ([dp-deploy]); `fabric-cicd`: no documented per-item selection | No documented selective deploy; the whole bundle is deployed | You own it |
| **Rollback** | No rollback operation documented; deployment history is a log of past deployments and failed items ([dp-history]). Revert by redeploying a previous commit | No rollback; `bundle destroy` permanently deletes the deployed jobs/pipelines/artifacts and "can't be undone" ([dbx-bundles-tasks]) | You own it |
| **Schema** | Separate SqlPackage/dbt step after item deployment (see §5) | Separate dbt/migration job or Terraform; not a bundle resource | You own it |

The important conclusion is that **there is no single product that replaces the shared YAML**. Fabric's native promotion is the deployment pipeline, but it never reads Git and cannot carry role assignments; the repo-as-source design therefore still uses `fabric-cicd`. Databricks' native unit is the bundle, but bundles have no approval or stage concept — ADO remains the orchestrator. The plain-YAML shape (c) is what the team already has; it is not wrong, it is under-specified.

Git integration and deployment pipelines are also not alternatives to each other: Git integration is an authoring sync bound to one workspace, and deployment pipelines are a workspace-to-workspace copy. `fabric-cicd` is the only one of the three that reads repository definitions and deploys them to an arbitrary workspace headlessly — and it is the one with no selective deploy and no applied-state ledger.

#### 6.3 Terraform's role when the artefact is an item

In Fabric, Terraform owns **containers and grants, not content**: capacity, workspaces, workspace role assignments, the Git connection (non-production), domains and tenant settings. It **cannot read an item definition back** — an item resource's `get` calls `GetItem` only — so it cannot see content drift, and an item resource beside `fabric-cicd` gives two writers with no arbiter (ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md); [`terraform-operating-model.md`](terraform-operating-model.md) §4 and §7). Keeping Terraform to containers is not a preference; it follows from the provider's read path.

In Databricks the line is **less clean**: Terraform can create the Azure resources (ADLS, Key Vault, workspace), account-level objects, and Unity Catalog objects including tables (`databricks_sql_table`) ([dbx-tf-table]). It is possible to put content in Terraform, but the same two-writer problem appears if dbt or a migration job also owns the table. The defensible boundary is: **Terraform for Azure and account/workspace containers; bundles for jobs/pipelines/dashboards; dbt or migration SQL for tables** — unless the team deliberately chooses Terraform as the single table owner and accepts that the SQL is then expressed as resource attributes.

#### 6.4 Blast radius: what one run can and cannot take down

This is the part the current model gets wrong, and it is a topology problem before it is a tool problem.

| Bad change | Can take down | Cannot take down | Basis |
| --- | --- | --- | --- |
| A bad item definition (pipeline, report, semantic model) promoted to every environment | Every **paired** item in each target stage is overwritten; dependent reports/pipelines can break; schedules can fire against the bad definition | OneLake table **data** — "git and deployment operations never overwrite data in tables or files"; workspace permissions, credentials, refresh schedules and semantic-model role assignments are not copied; target items not present in the source stage remain as-is | [dp-deploy], [`schema-and-ddl-management.md`](schema-and-ddl-management.md), [`deployment-mechanism-comparison.md`](deployment-mechanism-comparison.md) |
| A bad warehouse DDL publish | Objects and data can be dropped when `DropObjectsNotInSource` is on; a failure mid-script leaves the applied subset, because views/procedures/`CREATE SCHEMA` are outside the transactional list | Data in tables the script does not name; schemas outside the DACPAC's scope | [`schema-and-ddl-management.md`](schema-and-ddl-management.md) |
| A bad Terraform apply | A workspace and **all its items** can be deleted (workspace soft-delete default 7 days); a capacity cannot be restored; a tenant setting change is tenant-wide | Objects in another state; item data inside a workspace that is not destroyed | [`terraform-operating-model.md`](terraform-operating-model.md) §5 |
| A bad bundle deploy | Jobs, pipelines and artifacts in that **target** can be updated or removed; `bundle destroy` permanently deletes them | Data in Unity Catalog tables, unless a job or a Terraform resource drops it; other targets | [dbx-bundles-tasks] |
| A bad ADF ARM deployment | Pipelines/triggers in every environment the run reaches; a broken trigger can stop schedules | Warehouse data; Fabric items (there are none yet) | Inference from the ARM-export model; no Microsoft page describes this specific one-run topology |
| A job that runs and writes bad data | Every environment where it runs, including prod | Items it does not write; historical data unless overwritten | Inference: deployment is not execution |

Three concrete consequences:

- **"One run, all environments" removes the only place a mistake can be caught.** A change that deploys successfully but is semantically wrong passes dev, test and prod in one run; a failure at test leaves dev already changed and test/prod skipped, so the environments diverge.
- **Per-target deployment is the contrast that matters.** With one gated stage per environment, a bad dev deploy stops before test and cannot touch prod; a bad prod deploy is confined to prod. In the one-run model, the same bad item is promoted to every environment the run reaches, and there is no rollback in either Fabric deployment pipelines (the history is a log) or Databricks bundles (`destroy` is permanent). The product does not decide this; the pipeline topology does.
- **Per-environment stages are the control, not per-tool cleverness.** ADO environment approvals attach to a resource, not to YAML, so a stage with no `environment:` is never gated ([`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md)). Give each environment its own stage, its own service connection, and an approval on the production environment. This is the same shape ADR [0005](../adr/0005-authoring-and-promotion.md) already records.
- **Selective deployment is not a safety net by itself.** Fabric's selective deploy can fail or produce unexpected results if a dependent item is not present in the target; the docs say to use "Select related" and warn that deploying an item without its dependency can break it ([dp-deploy]). A per-item pipeline therefore needs dependency awareness, not just a checkbox.

#### 6.5 The three changes, step by step

**Today — add a pipeline.** Author it in ADF; export the ARM template (`ARMTemplateForFactory.json`) and its parameter file; commit both; run the shared YAML, which redeploys the factory to dev, test and prod in sequence; start the triggers. The change is not reviewable as a pipeline diff, only as an ARM JSON diff.

**Today — add a table.** Add `Tables/<name>.sql` to the `.sqlproj`; build the `.dacpac`; run `SqlPackage /Action:Publish` against each environment in the same run. If the publish uses `DropObjectsNotInSource`, a rename is a drop plus a create.

**Today — add an Azure resource.** Add the Terraform resource/module; run `terraform plan` and `apply` against each environment's state. A resource that is shared (capacity, storage, Key Vault) must be in a state that is not duplicated per environment, or the second apply fights the first.

**Fabric — add a pipeline.** Author it in the Git-bound `dev` workspace; commit `<name>.DataPipeline/pipeline-content.json` plus `.platform`; let `fabric-cicd` deploy the definition to test and prod — underneath, that is `Create Item with Definition` / `Update Item Definition` for the target workspace (or promote with a deployment pipeline). The item definition carries connection GUIDs; connections are **not** deployed by `fabric-cicd`, so the connection and its parameterisation are a separate step ([`item-definition-formats.md`](item-definition-formats.md)).

**Fabric — add a table.** Add the `CREATE TABLE` to the `.sqlproj`; build; run `sqlpackage /Action:DeployReport` against the target, then `/Action:Publish` with `BlockOnPossibleDataLoss=true`; or add a dbt model and run the Fabric dbt job. This is a distinct step after item deployment, not part of the item payload.

**Fabric — add an Azure resource.** Terraform, unchanged in role: capacity, storage, Key Vault, private endpoints. It is not an item and does not go through `fabric-cicd`.

**Databricks — add a pipeline.** Add `resources.jobs.<key>` (tasks, schedule, permissions) to `databricks.yml` or an included YAML; `databricks bundle validate -t dev`; `databricks bundle deploy -t dev`; run and test; then `-t test` and `-t prod` as separate gated stages ([dbx-bundles-settings], [dbx-bundles-tasks]).

**Databricks — add a table.** Add a dbt model or a migration SQL file executed by a job task; or add a `databricks_sql_table` resource to Terraform. A bundle cannot create the table itself — the supported-resource table has no table/view resource ([dbx-bundles-resources]). If the table is Terraform-owned, the job must not also create it.

**Databricks — add an Azure resource.** Terraform for ADLS, Key Vault, the workspace and network; separate from the bundle. The bundle deploys into the workspace, not the Azure subscription.

#### 6.6 ARM JSON to Fabric item definitions: what does not survive

Microsoft publishes an ADF-to-Fabric migration position, but it is **factory-based**, not file-based. The built-in experience assesses pipelines "directly in Azure Data Factory", mounts the factory into a Fabric workspace, and upgrades supported pipelines incrementally ([adf-upgrade]). **No documented converter takes an ARM template export and emits Fabric item definitions.** That is the gap the current repo-only model hits: to use the documented assessment, the ARM template has to be deployed to an ADF instance first. Treat anything else as a manual rebuild.

| ARM artefact | Fabric destination | What does not survive |
| --- | --- | --- |
| Factory / pipeline JSON | Pipeline item (`pipeline-content.json`) | ARM schema, resource IDs and deployment semantics; only the activity set and expressions have analogues |
| ARM parameters and parameter files | `parameter.yml` (`find_replace`, `$items.*`, `$workspaces.*`) | ARM parameter typing, parameter files and deployment-time expressions; `.platform` is intentionally excluded from parameterisation ([item-definition-formats](item-definition-formats.md)) |
| Linked services | Connections | The linked-service object; connection IDs are environment-specific and connections are recreated, not deployed by `fabric-cicd` |
| Datasets | Inline activity properties | The dataset object entirely |
| Triggers | Schedules and event triggers | Shared schedules, trigger reuse, trigger state/history; Fabric has one schedule per pipeline and no central hub ([adf-upgrade]) |
| Global parameters | Variable Library | ARM global-parameter semantics and types; converted to a different implementation ([adf-upgrade]) |
| Integration runtime / gateway bindings | On-premises data gateway or VNet data gateway | The IR object and its binding; the gateway binding is manual and not in the item definition ([`gateway-and-connectivity.md`](gateway-and-connectivity.md)) |
| SSIS packages | Nothing | No Fabric equivalent ("to be determined") ([adf-compare]) |
| Managed VNet / private endpoints | Nothing yet | "To be determined" ([adf-compare]) |
| Activity set | Fabric activities | SSIS, validation, five HDInsight activities, notebook/Jar/Python, custom activity and full MDF feature set all change or disappear (§1) |
| ARM deployment ordering | Deployment pipeline order or a deployment plan (preview) | `dependsOn`; Fabric's ordering primitive is a deployment plan, or the order you encode in the pipeline |

### 7. Governance: Fabric's catalog is the destination; Purview is not

Fabric emits governance metadata natively: a workspace lineage view, catalogue columns for owner/refresh/endorsement/sensitivity, domains, sensitivity labels and endorsement. The limits are documented in [`purview-and-lineage.md`](purview-and-lineage.md): lineage is item-level and one workspace plus one upstream hop; cross-workspace downstream edges need a Purview scan; labels are creation-only for most automation. That note remains the authority on what Fabric emits.

**The dated change is on the Purview side.** Microsoft Purview pages read on 2026-11-24 carry this banner: "Microsoft Purview Unified Catalog and classic Microsoft Purview data governance capabilities (formerly Azure Purview) are being retired … Microsoft is consolidating its data governance capabilities in Microsoft Fabric. New Microsoft Purview data governance accounts can no longer be created, and existing data governance capabilities will remain in maintenance mode through November 12, 2027." The same banner says Purview as a whole is not retiring and that data security and compliance, including sensitivity labels, are unaffected ([purview-retire]). So the constraint "Purview catalog/lineage" is no longer a stable destination for a new estate; the Microsoft-centric catalog destination is Fabric's own catalog, with Purview Information Protection still supplying labels.

Databricks governance is **Unity Catalog**: catalogs, schemas, tables, views, volumes and models; grants; row filters and column masks; column-level lineage; audit via system tables ([dbx-aim], [dbx-sql-ref]). Purview's Databricks integration is a **Purview-side scan**, not a Unity Catalog-side push:

- The source is registered in Purview as **Azure Databricks Unity Catalog**; Purview connects to a **SQL warehouse** using a PAT, service principal or managed identity, and reads Unity Catalog metadata ([dbx-purview]).
- Lineage is "passive": Purview "only ingests what Unity Catalog system table logs and makes accessible"; it requires `system.access.table_lineage` and `column_lineage`; external tables have no lineage; SQL warehouses do not generate column-level lineage ([dbx-purview]).
- It is one-way and scan-based. Nothing written in Purview becomes a Unity Catalog grant or tag.

**The Microsoft-native bridge that does work**: Fabric can **metadata-mirror an Azure Databricks Unity Catalog**, which "synchronizes an external catalog and uses shortcuts to access its open-format data in place without copying it" ([`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md)). That makes Databricks tables discoverable and queryable from Fabric without a Purview scan, while Unity Catalog remains the enforcement point. It is not a merged catalog: two catalogs, two permission models, one shortcut layer.

| Governance question | Fabric | Databricks |
| --- | --- | --- |
| Catalog | OneLake catalog, domains, endorsement, sensitivity labels | Unity Catalog |
| Lineage | Workspace lineage view (item-level, one hop upstream); Purview scan for cross-workspace | Unity Catalog column-level lineage; system tables |
| External catalog visibility | Metadata mirroring of Databricks UC (no copy) | Lakehouse Federation (read-only foreign catalogs) |
| Purview | Optional pull scan; data-governance product retiring into Fabric | Optional pull scan; one-way; retiring product |
| Labels | Purview Information Protection labels, displayed in Fabric | Unity Catalog tags; Purview classification via scan |

**Motion:** Fabric governance is a **refactor** onto Fabric's catalog, not a new Purview deployment. Databricks governance is a **rebuild** into Unity Catalog, with Fabric metadata mirroring as the Microsoft-side discovery bridge. Building a new estate on a Purview data-governance account is not defensible on the 2026-11-24 documentation.

### 8. Identity and security: Entra stays; what changes is where the authorization lives

Fabric uses **Microsoft Entra ID natively**. The T-SQL endpoint accepts Entra users and service principals and does not support SQL authentication; workspace roles are Admin/Member/Contributor/Viewer; OneLake data-access roles are the data-plane control ([`platform-taxonomy.md`](platform-taxonomy.md), [`onelake-security-model.md`](onelake-security-model.md)). There is no separate Fabric identity store and no SCIM sync to run.

Databricks also uses Entra as the source of record, but keeps its **own account principals**. Automatic identity management syncs users, service principals and groups from Entra, is enabled by default for accounts created after 2025-08-01, and is recommended over SCIM; SCIM remains available and requires the Cloud Application Administrator role and a separate Entra application ([dbx-aim]). The distinction that matters: **Entra group membership is synced, but Unity Catalog privileges are Databricks objects**, and a SQL warehouse does not support credential passthrough — access is enforced by UC grants, not by the user's Entra token alone ([dbx-warehouse-types], [dbx-aim]).

| Identity question | Fabric | Databricks |
| --- | --- | --- |
| Directory | Entra | Entra as source of record |
| Provisioning | None; Entra principals are used directly | Automatic identity management (default for new accounts) or SCIM |
| Authorization | Workspace roles + OneLake roles + item permissions | Unity Catalog grants + workspace assignment |
| Service principal | Entra app; Fabric scopes; tenant settings gate | Entra app; Databricks account service principal; OAuth M2M |
| SQL authentication | Not supported on the T-SQL endpoint | No T-SQL SQL-login path; account identity + UC |

**Motion:** Entra is a **rehost** in both. Fabric adds no identity tier; Databricks adds an account-level sync and a UC grant model, which is operational work even though the directory does not change.

### 9. Observability: both destinations require a rebuild

Fabric's observable surface is the **Monitor hub**, **workspace monitoring** (event data into an Eventhouse), and the **Capacity Metrics app**; there are **no Azure Monitor metrics for `Microsoft.Fabric/capacities`**, and the documented alerting is email capacity notifications, Real-Time hub events (`Microsoft.Fabric.Capacity.Summary`, `.State`) and Activator ([`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md), [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md)). It is portal-first and capacity-centric.

Databricks' observable surface is **system tables**: `system.billing.usage` for DBU consumption and cost, `system.access.audit` for audit events, lineage system tables, plus query history and SQL warehouse monitoring ([dbx-billing], [dbx-audit]). Azure Monitor diagnostic settings exist, but the audit-log reference says diagnostic settings do **not** log all services and do **not** include account-level events; the audit-log system table is the complete surface ([dbx-audit]). It is SQL-queryable and account-centric.

**Motion:** **rebuild** in both. ADF run history, Azure Monitor alerts and any Log Analytics queries over ADF do not carry over. Fabric's replacement is a Capacity Metrics/Monitor hub design; Databricks' is a set of system-table queries and job notifications. Neither is a like-for-like port of the current monitoring.

### 10. Cost: capacity units versus DBUs, shape only

No prices here. What differs is the **unit and the commitment shape**.

**Fabric** sells a provisioned capacity: an F SKU supplies a fixed number of **capacity units**, and operations are smoothed over 30-second timepoints — interactive over 5–64 minutes, background over 24 hours. Overage is on by default at a 25% threshold and billed at three times the pay-as-you-go rate; F SKUs can be paused, which stops future compute billing but bills accrued smoothed usage and makes content unavailable. Storage is metered separately. The full mechanics are in [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md). Mirroring is the outlier: replication consumes no CU and storage is free to 1 TB per CU ([`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md)).

**Databricks** sells **DBUs** per SKU, recorded in `system.billing.usage` as `usage_unit = DBU` and `usage_quantity` ([dbx-billing]). The shape depends on compute type:

- **Serverless SQL warehouse**: Databricks-managed; 2–6 second startup; intelligent workload management and autoscaling.
- **Pro / classic SQL warehouse**: compute runs in **your Azure subscription**, so VM and disk cost sits beside the DBU; startup is typically about 4 minutes; you choose a cluster size from 2X-Small to 5X-Large and set min/max clusters; the sizing guidance is one cluster per 10 concurrent queries ([dbx-warehouse-types], [dbx-warehouse-behavior]).
- **Jobs / all-purpose / Lakeflow**: DBU by SKU, plus VM/disk for classic compute; serverless is DBU-only.

The honest comparison is therefore **not a rate conversion**. Fabric's unit is a smoothed capacity budget with a pause switch; Databricks' is a per-SKU consumption meter with serverless or customer-subscription compute. A cost model has to be rebuilt from workload shape, not translated.

### 11. Operability for six people: the deciding constraint

The team facts below are user-supplied on **2026-11-24**, not read from a Microsoft page: **three data engineers, two DBAs who own the on-premises SQL Server, and one data lead who does DBA work and management** — six people, but only **three delivery engineers** for this transition; the on-premises estate stays with the DBAs. The strongest skills are **Azure Data Factory/orchestration and T-SQL**. There is no stated Spark or Python depth today, and the estate has no specialist tools beyond the existing ADF/T-SQL/Terraform/`sqlproj` stack. When trade-offs conflict, **least operational burden wins**: run cost, migration speed and future ML are all secondary to "fewer moving parts for six people".

That priority changes the answer more than any product comparison does. It is not a preference for "no new tools" — both destinations add tools. It is a preference for the **fewest new operating models** carried by the same three engineers, with the two DBAs kept on the source rather than counted as platform staff.

#### 11.1 What "least operational burden" rules out

- **It rules out a second platform that needs its own on-call, sizing and governance model.** Databricks is not just a different SQL engine; it is Spark, Unity Catalog, bundles, cluster/warehouse sizing, DBU cost attribution and a second grant model. Fabric is not free either — capacity, item CI, OneLake roles, a gateway and a schema stage — but it replaces ADF and T-SQL with close analogues rather than replacing the programming model.
- **It rules out counting the DBAs as delivery capacity.** They own the on-premises SQL Server and its backups, patching and access. A plan that assumes six people can build either destination over-estimates delivery capacity by 2×.
- **It rules out "future ML" as a tie-breaker.** ML is explicitly secondary. Databricks' ML advantage is real but cannot justify a second platform the team did not ask for.

Counted as distinct surfaces a named owner must log into and maintain, the two destinations are not close:

| Count | Fabric | Databricks |
| --- | --- | --- |
| **Platform planes** | **4** — Fabric product (tenant/capacity/workspace/item), ARM (the capacity resource), Entra, ADO | **6** — ARM, account console, workspace admin, Unity Catalog metastore, Entra/SCIM, cloud IAM (ADLS role assignments) |
| **Grant / protection surfaces** | **5** — workspace roles, item sharing, OneLake roles, SQL `GRANT`, labels/domains | **2** — Unity Catalog privileges and workspace ACLs — plus cluster policies as a compute control |
| **Skill sets to run it** | **6** — T-SQL, ADF/pipeline JSON, Terraform/REST, Power BI/XMLA, capacity FinOps, Entra/ADO | **8** — keeps SQL and Terraform, adds Spark/Python/Scala, Delta/Photon tuning, cluster-policy JSON, bundle YAML and cloud IAM |
| **Per-item surface** | **23 deployable, 7 manual-only, 5 API-only** item types — real toil, but inside the one product plane | Not comparable — bundles deploy a project, not an item catalogue |

The Fabric count is four planes, not "one portal": the capacity is an Azure resource, Entra owns the groups and service principals, and ADO owns the pipeline. The Databricks count is six before CI, and the docs separate **account admin, workspace admin and metastore admin** explicitly ([dbx-admin-concepts]); Unity Catalog setup adds storage credential → external location → catalog/schema → grant ([dbx-uc-setup], [dbx-cloud-storage]), and cloud storage access needs an Azure managed identity or service principal with ADLS role assignments ([dbx-cloud-storage]). Those are the surfaces being counted, and they are not optional add-ons. The plane and surface counts are a synthesis of the admin docs and this repo's inventories; the skill-set counts are a judgement on this team's starting point, not a certification framework. The item counts are from [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md).

#### 11.2 Skill-by-skill

| Skill | Today | Fabric | Databricks |
| --- | --- | --- | --- |
| **T-SQL** | Strong | Warehouse T-SQL, reduced surface (§3); transfers with retraining on the limitations | Spark SQL; a rewrite, not a transfer |
| **ADF orchestration** | Strong | Data Factory pipelines, ~90% activity continuity, official upgrade path (§1); close analogue | Lakeflow Jobs; new programming model and bundle deployment |
| **Dimensional modelling** | Strong | Same modelling, Delta storage | Same modelling, Delta + Unity Catalog |
| **Python / Spark** | Not stated today; a learnable transition, not a capability gate | Not required if the compute is Warehouse; notebooks optional | The docs and tooling are Python/YAML-first for notebooks, Lakeflow and bundles; Spark SQL is the SQL surface, and Python is the common engineering path |
| **Terraform / IaC** | Not stated | ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) and [0007](../adr/0007-terraform-layout-and-pinning.md) make it the control plane; a new skill for a T-SQL/ADF team | Terraform **plus** bundles; more IaC surface, not less |
| **Identity / governance** | Entra | Entra native; workspace and OneLake roles; low new skill | Entra sync plus Unity Catalog grants; a second authorization model |
| **Platform operations** | SQL Server + ADF | Capacity/throttling, gateway updates, schema drift, item deployment, 3N access groups | All of Fabric's list plus clusters/warehouses, UC grants, bundle state and DBU cost |
| **DBAs' role** | On-prem SQL Server | Can own Warehouse T-SQL and the schema stage; source stays theirs | T-SQL does not transfer to Spark; DBAs stay on the source, outside the main platform |

#### 11.3 Toil, counted against three delivery engineers

Only three people carry delivery. The other three are source custodianship and the decision seat, not additional build capacity:

| Role | Count | Role in this transition | Can own today | New skill required |
| --- | --- | --- | --- | --- |
| Data engineer (ADF/T-SQL) | 3 | Delivery | ADF orchestration, T-SQL modelling, schema review, pipeline testing | Fabric item CI, Terraform if the team owns it, capacity/gateway operations |
| DBA (on-prem SQL Server) | 2 | Source custodianship only | SQL Server, backups, patching, source access, T-SQL review | Not counted as platform staff; Fabric/Spark operations are outside their remit |
| Data lead (DBA + management) | 1 | Decision seat and DBA review | Prioritisation, approvals, source-side decisions | Same as above; not a fourth engineer |

Spec [0002](../specs/0002-platform-operations.md) defines the steady state as **four operations** — deploy on merge, nightly drift, weekly access, weekly capacity — plus four quarterly reviews, each with an owner. That is the baseline to count against. Neither destination reduces the number of recurring jobs: Fabric keeps the four and adds the schema stage and the per-item deployment gaps; Databricks removes the Fabric-specific capacity/overage/pause toil but adds account/UC administration, cluster-policy tuning, cloud IAM, Delta maintenance and DBU cost attribution — roughly five new recurring jobs. For three delivery engineers, that is the difference between one platform and two.

**Fabric, minimum-toil path.**

- *Build:* one Terraform root for capacity and one for workspaces/roles, Git/PR for the dev workspace, `fabric-cicd` for item definitions, a `.sqlproj`/SqlPackage stage, per-environment ADO approval gates, and a Capacity Metrics/Monitor hub view.
- *Run:* capacity utilisation and throttling, gateway patching if on-premises SQL Server is mirrored, `DeployReport` schema drift, item deployment, and 3N Entra groups. The group count is the quiet tax: three environments × N workspaces means 3N groups, each with an owner ([ADR 0006](../adr/0006-access-through-entra-groups.md), [ADR 0010](../adr/0010-delegation-and-administration-model.md)).
- *Deliberately avoid at the start:* lakehouse/Spark as the primary compute, Airflow, the dbt job, and the full event-sourced observability design. Each is a real capability with a real owner; none is required to replace the warehouse and ADF.
- *Named owners:* capacity admin plus deputy, workspace admins, group owners. With six people the same names repeat across all three environments — that is the operability cost, and it should be explicit rather than discovered.

**Databricks, minimum-toil path.**

- *Build:* Unity Catalog metastore, catalogs/schemas/grants, bundle targets for dev/test/prod, Terraform for Azure and the workspace, Spark notebooks/jobs or Lakeflow pipelines, SQL warehouse sizing, dbt or migration SQL, cost dashboards, and a Purview or Fabric-metadata-mirroring decision.
- *Run:* cluster and warehouse sizing/auto-stop, UC grants, bundle state and target promotion, Spark job failure triage, DBU cost attribution, and two compute planes (SQL warehouse and jobs/Spark).
- *Named owners:* account admin, metastore admin, workspace admin and cost owner. With three delivery engineers these are the same people, and none has stated Spark depth today — which is a ramp, not a gate.

#### 11.4 What changes if the team commits to Python/Spark?

The decision is a strategy branch, not a skills test. Three competent data engineers can learn Python, PySpark and Spark SQL; "not stated today" is a ramp, not a ceiling. The question is whether the team intends to become Python/Spark-first and will own the platform that comes with it.

**(a) Stay T-SQL/ADF-first, least toil.** Fabric is the lower-burden path: ADF maps to Data Factory, T-SQL maps to Warehouse, `.sqlproj` survives, and Python stays optional. The platform ownership is Fabric's four planes, which the team already has analogues for. This is the path the stated priority selects.

**(b) Become Python/Spark-first and own the platform.** Databricks is a legitimate destination for this team too. The skills are a planned ramp — Python/PySpark, Spark SQL, Unity Catalog grants, bundle deployment and job debugging — not a gate. What makes Databricks expensive is not writing Python; it is **owning the platform**: the Unity Catalog metastore, cluster policies, bundle state, cloud IAM, DBU cost attribution and incident triage. That cost stands even if the PySpark is excellent. Choosing this path means accepting the second platform as a deliberate cost, not arguing it away.

The real prerequisite is a **named platform owner** — someone internal who takes it on, or a hire/contract if no one does. Hiring is one route, not the only route; an internal owner changes the cost from salary to time. Without a named owner, the planes have no owner and the team learns in production. With one, Databricks is viable, and the ramp is months rather than a training day.

The T-SQL migration is a real cost on either path, and Python ability does not remove it: Fabric converts the T-SQL with a reduced surface; Databricks rewrites it to Spark SQL. Python ability changes who can do the rewrite, not whether it is needed.

So the decision test is: **does the team intend to become Python/Spark-first, and will it name a platform owner?** Yes to both makes Databricks a legitimate destination with a known transition cost. Staying T-SQL/ADF-first makes Fabric the lower-toil answer. Wanting Python without owning the platform still points to Fabric, or to a split with a separate engineering team — the highest-burden option for six people.

The schedule and training estimates here are judgement, not a measured plan; what the evidence establishes is the shape of the cost, not its duration.

#### 11.5 Which ADR assumptions this complicates

None of ADRs 0002–0010 is wrong on its evidence, but three areas carry assumptions that a three-engineer delivery team may not be able to honour:

| ADR | Assumption | What six people do to it |
| --- | --- | --- |
| [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) / [0007](../adr/0007-terraform-layout-and-pinning.md) | A platform engineer owns Terraform state, exact pinning, two roots, preview isolation and upgrade diffs | This is the largest new skill in the Fabric plan. Name the owner and the upgrade calendar, or reduce the Terraform surface to capacity/workspace/roles and accept more `fabric-cicd`/REST. Do not delete the ADRs; scope them. |
| [0006](../adr/0006-access-through-entra-groups.md) / [0010](../adr/0010-delegation-and-administration-model.md) | 3N groups have 3N owners, and delegation works because there are enough owners to delegate to | With six people, the same engineers own every group. Reduce N by reducing workspaces (one per environment per domain, not per project), or accept that group ownership is a standing task, not a one-off. |
| [0009](../adr/0009-observability-is-event-sourced.md) | An Eventhouse, KQL and Activator are operated as the monitoring path | This is real toil for three engineers. Start with Capacity Metrics and built-in notifications; add the Eventhouse when an alert cannot be expressed otherwise. The design is sound; it is not a day-one requirement. |

Two ADRs are helped by the constraint. [ADR 0004](../adr/0004-one-shared-capacity.md) (one shared capacity) is **less** operational burden than three SKUs, at the cost of shared throttling and a three-environment outage domain — for six people, the simplicity may be worth that trade, but it should be named. [ADR 0008](../adr/0008-schema-is-state-based.md) (`.sqlproj` + SqlPackage) is the **lowest-toil** schema route for a T-SQL team; the dbt/Spark half of that ADR is the part that needs a skill the team has not stated, so keep Warehouse as the primary compute and treat lakehouse tables as the exception.

Three corrections to the ADR framing, so the operability argument is not overstated:

- **ADR 0003's "two lifecycle models" is not a Fabric-specific penalty.** Databricks also recommends two tools: Terraform for cloud-level/admin resources, and bundles for jobs, pipelines and notebooks ([dbx-terraform]). The Fabric-specific cost is the **preview DacFx stage** and `fabric-cicd`'s coverage gaps, not the number of tools.
- **ADR 0004 and ADR 0009 are responses to Fabric-specific toil, not universal toil.** CU smoothing, capacity overage, pause/resume and the capacity review's lack of a machine-readable source are Fabric problems; ADR 0009's Eventhouse is a Fabric-specific remedy. Databricks removes them, but replaces them with DBU billing, cluster-policy cost control and a separate account-level cost model — it does not remove the category.
- **ADR 0006 is not portable to Databricks, and ADR 0008 is not either.** One Entra group per Fabric workspace does not map to account-level groups assigned to workspaces plus Unity Catalog grants; a Databricks choice would redesign ADR 0006 rather than reuse it. `.sqlproj`/DacFx is Fabric-only; Databricks needs dbt or ordered migration SQL. ADR 0010 is partially portable: Fabric domains do not affect item access, while Databricks catalogs do isolate data, but account admin remains central in both.

[ADR 0002](../adr/0002-two-service-principals-federated.md) (two federated service principals) adds a second pipeline and service connection. It is a security boundary worth keeping; the toil is setup, not steady state. [ADR 0005](../adr/0005-authoring-and-promotion.md) (Git-bound dev, PR, approval) is process toil but the only reviewable path; keep it, and use deployment pipelines only where native stage promotion or selective deploy is worth a second control plane — keep the approvals in ADO.

#### 11.6 Verdict

**On the stated priority — stay T-SQL/ADF-first, least operational burden — Fabric is the destination.** It keeps the team's two strongest skills, ADF orchestration and T-SQL, as the primary interface, and it is the only one where `sqlproj`, which the DBAs and engineers already understand, survives. The migration is still real work: item definitions and CI are new, the T-SQL surface is reduced, and capacity/gateway operations are new. But it is retraining on analogues, not a new platform discipline.

**Databricks is a legitimate destination for this team if the intent changes to Python/Spark-first and a platform owner is named** — internal or hired. That is a strategic choice, not a skills gate. The T-SQL rewrite is a one-time migration cost; the added planes are the recurring cost; hiring is one way to get the owner, not the only way. What would make Databricks the wrong answer is not the team's current SQL background; it is choosing it without an owner and without the intent to run a second platform.

**A split is worse, not better, for six people.** It is only defensible with separate BI and engineering teams. Databricks' own storage documentation marks OneLake as **not supported by Unity Catalog** ([dbx-cloud-storage]), so reading Fabric data from Databricks bypasses Unity Catalog; a split creates a second governance plane, not a shared one. For this team it is the highest-burden option.

The decision rule that falls out of the evidence:

- **Fabric is the better fit when most of these hold:** Power BI is the main consumption layer or Direct Lake/OneLake is wanted; the workload is batch warehouse plus orchestration over the existing SQL estate; the team intends to stay T-SQL/ADF-first and will not name a platform owner for a second platform; ML is ad hoc rather than a product, and streaming is not a requirement; one bill and one tenant outweigh a less mature CI surface.
- **Databricks is the better fit when at least two hold:** ML, streaming or large-scale Python/Spark is a named, funded goal; the team intends to become Python/Spark-first and will name a platform owner, internal or hired; Unity Catalog is wanted as the governance anchor, including multi-cloud or open-format sharing; BI is Databricks SQL/Tableau, or Power BI is a secondary consumer; the team accepts running account, workspace, metastore and cloud-IAM planes.

On the stated intent, the first list applies — with Power BI as the assumption stated at the top, not a confirmed fact. The second is a strategy the team has not chosen, not a capability it lacks. If the intent changes, the verdict changes with it.

The least-operational-burden scope inside Fabric is narrower than the full pack: **Warehouse first, Data Factory pipelines, `fabric-cicd` plus one schema stage, Terraform limited to containers, Capacity Metrics before Eventhouse**. That is a scope recommendation for the work repo, not a change to the ADRs.

### 12. What stays put

- **The on-premises SQL Server OLTP does not move.** Nothing in either destination requires it to; Fabric reads it through mirroring or a gateway, Databricks through federation or CDC. Moving it is a separate project with a separate business case, and this note does not recommend it.
- **Microsoft Entra stays.** Both destinations consume it; neither replaces it.
- **Azure billing stays.** Fabric capacity is an Azure resource; Databricks is an Azure-billed service. The subscription and cost-management boundary does not change, only the meters.
- **Power BI can stay**, if it is the BI layer. Under Fabric it stays native (Direct Lake over OneLake); under Databricks it becomes an external consumer over a SQL warehouse (Import/DirectQuery), and Direct Lake is lost ([pbi-dbx]).
- **ADF and the Azure SQL Database can stay during a parallel run.** Neither destination requires a hard cutover; the migration can read from the old estate while the new one is validated. The ARM export, however, is retired either way.
- **ADLS Gen2 stays under Databricks** (and is optional under Fabric via shortcuts); the storage account is not the thing being replaced, the table format and catalog are.

## Correction — 2026-11-24

An earlier draft of this note treated the team's T-SQL/ADF background as evidence that it could not adopt Python/Spark. That conflated two different things: **skill acquisition**, which is learnable with a real ramp, and **platform ownership**, which is the recurring toil — Unity Catalog metastore, cluster policies, bundle state, cloud IAM, DBU cost attribution and incident triage. §11.2, §11.4 and §11.6 are corrected: Python/Spark is a transition, not a capability ceiling, and the Databricks verdict is conditional on the team's intent and a named platform owner, not on its current SQL skills. The destination conclusion for the stated priority is unchanged: Fabric.

## What this settles

| Layer | Fabric destination and motion | Databricks destination and motion |
| --- | --- | --- |
| Ingestion | Mirroring / Copy job / Data Factory; **refactor** ADF, keep the OLTP source | Lakeflow Connect / Federation / Auto Loader; **rebuild** |
| Storage | OneLake, Warehouse or lakehouse, Delta; **refactor** via Migration Assistant + Copy job | ADLS + Delta + UC; **rebuild** |
| Compute | Warehouse T-SQL (surface-reduced) or read-only SQL endpoint; **refactor** | Databricks SQL / Spark SQL; **rebuild** |
| Orchestration | Data Factory pipelines; **refactor** | Lakeflow Jobs; **rebuild** |
| Semantic / BI | Power BI native, Direct Lake; **rehost/refactor** | Power BI external, or AI/BI dashboards; **refactor** |
| Governance | Fabric catalog; Purview data governance is retiring; **refactor** | Unity Catalog; **rebuild**; Fabric metadata mirroring as the bridge |
| Identity | Entra native; **rehost** | Entra + account sync + UC grants; **rehost plus sync** |
| Deployment / CI | Git + deployment pipelines + `fabric-cicd` + Terraform containers + SqlPackage/dbt; **refactor**; retire ARM export | Bundles + Terraform + dbt/migrations; **rebuild** |
| Observability | Monitor hub + Capacity Metrics + workspace monitoring; **rebuild** | System tables + query history + audit logs; **rebuild** |
| Cost | CU capacity, smoothing, overage, pause; **rebuild the model** | DBU + serverless or subscription compute; **rebuild the model** |

- **Fabric is the lower-motion destination for this estate, and the verdict on the stated priority: stay T-SQL/ADF-first and minimise recurring operational burden.** It is the only destination that keeps T-SQL, `.sqlproj` and an ADF upgrade path, and the only one that keeps the team's strongest skills — ADF orchestration and T-SQL — as the primary interface. The cost is the reduced T-SQL surface and a catalog transition while Purview data governance retires.
- **Databricks is a rebuild, not a lift, and a strategic choice for this team, not a skills gate.** It is the right destination if the team intends to become Python/Spark-first and names a platform owner, internal or hired; the T-SQL rewrite is a one-time migration cost and the added planes are the recurring one. It is not the least-toil answer for a team that stays T-SQL/ADF-first.
- **The shared rebuild-everything pipeline should be replaced by per-environment deployment with an approval gate, in either destination.** Fabric deployment pipelines provide the only native promotion surface with documented selective deployment; `fabric-cicd` and Databricks bundles are whole-set deployers. ADO remains the orchestrator and the approval point.
- **The ARM export is a dead end.** Microsoft's ADF migration position is factory-based assessment, not ARM-to-item conversion. Budget for manual or assessment-led conversion, not an automated transform.
- **Purview data governance is not a new-estate anchor.** Fabric's catalog is; Unity Catalog plus Fabric metadata mirroring is the Databricks-side equivalent.
- **The on-premises OLTP stays.** Say it in the plan so nobody scopes it by accident.
- **Least operational burden narrows the Fabric scope.** Warehouse before lakehouse, Data Factory pipelines before Airflow/dbt jobs, Capacity Metrics before the event-sourced observability build, and Terraform limited to the container role. The ADRs that carry the most operability risk are 0003/0007 (Terraform), 0006/0010 (3N groups) and 0009 (Eventhouse); each needs a named owner, not a redesign.
- **Counted as surfaces, Fabric is four platform planes and five grant surfaces; Databricks is six platform planes and two grant surfaces plus cluster policies.** Spec 0002's four-operation steady state fits the Fabric count; Databricks adds roughly five recurring jobs, which is why it is a platform-team decision, not a tool swap.

## What this does not establish

- **Volume, concurrency, latency SLO or residency.** No table sizes, query rates, concurrency targets, region pair or data-residency constraints were supplied, and none of the recommendations is sized. The Fabric capacity note's sizing method and the Databricks warehouse sizing guidance are inputs, not answers.
- **Cost.** No prices, no SKU recommendation, no CU or DBU estimate. The units and the shape are established; the bill is not.
- **The actual ADF inventory.** How many pipelines, which activities, which connectors, how many Mapping Data Flows, whether SSIS is in use, and how many are "Ready" versus "Not compatible" are unknown. The migration effort cannot be read off the documentation.
- **Whether an ARM-file-only conversion exists.** No Microsoft page found describes converting a committed ARM export into Fabric item definitions without a live factory; the documented assessment runs in ADF. Treat this as undocumented, not as impossible.
- **Whether Fabric deployment pipelines can deploy every item type in the estate.** `Dataflow` has a documented API contradiction, seven item types are manual-only, and the SQL analytics endpoint is not deployable at all ([`item-type-deployment-coverage.md`](item-type-deployment-coverage.md)).
- **Whether a Fabric deployment or a Databricks bundle deploy is atomic.** Neither page states what happens to already-updated items when a later item fails. The blast-radius table therefore describes what is documented, and marks the rest as inference.
- **What a Databricks bundle deploy does to a job or pipeline edited in the UI between deploys.** The bundle lifecycle implies the bundle definition wins, but the pages read do not state it; treat drift under bundles as inferred, not measured. The same caveat applies to the claim that no ADF-to-Databricks converter exists — that is a documentation-search result, not proof that no partner or undocumented tool exists.
- **Whether `sqlpackage Publish` is transactional on Fabric Warehouse, whether `CREATE OR ALTER` executes there, and whether `MERGE` tolerates new source columns.** The schema note already records these as open; this note does not close them.
- **Whether Fabric's catalog will absorb the retiring Purview capabilities** (cross-workspace lineage, classifications) by 2027, and on what schedule. The retirement banner names Fabric as the destination; it does not map features.
- **Databricks disaster recovery, RTO/RPO and cross-region behaviour.** Fabric's continuity is covered by [`business-continuity-what-does-fabric-guarantee.md`](business-continuity-what-does-fabric-guarantee.md); Databricks continuity was not researched here.
- **Whether Power BI is the BI layer, or Purview is already deployed.** The estate table names neither; the note treats them as constraints/assumptions, not facts.
- **The on-premises SQL Server version.** Mirroring's path differs between 2016–2022 (CDC) and 2025 (Arc change feed), and the version decides whether the GA mirroring route applies.
- **The team's starting skills beyond the stated strongest skills.** The composition (three delivery engineers, two DBAs, one data lead) and the priority (least operational burden) are user-supplied on 2026-11-24; no skills matrix, training budget or hiring plan was supplied. The operability conclusion is a judgement on those facts, not a measured capability assessment.
- **Whether the team wants to become Python/Spark-first, and what training time or budget exists.** Python/Spark is treated here as a learnable transition, not a capability ceiling; the note does not establish intent, ramp duration, training budget, or whether an internal platform owner is available.
- **Licensing and commitment.** Whether the team has an F SKU, a Databricks commitment, or an existing Power BI Premium capacity is not established; the F64 licence cliff and the Databricks SKU choice are commercial decisions, not documentation facts.

## Sources

All primary sources below were read on **2026-11-24**; the date column is the page's own `ms.date` where one is published, otherwise the read date. Fabric and Databricks both rename and retire surfaces monthly, so treat a page more than a few months old as a question.

| Ref | Source | Used for | Dated |
| --- | --- | --- | --- |
| [adf-overview] | [What is Data Factory](https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-overview) | item surface: Copy job, Copy activity, mirroring, Dataflow Gen2, dbt job, Airflow, pipelines | ms.date 2026-08-05 |
| [adf-upgrade] | [Upgrade Planning for Azure Data Factory to Fabric Data Factory](https://learn.microsoft.com/en-us/fabric/data-factory/upgrade-planning-azure-data-factory) | official migration position; mounted ADF; assessment categories; mappings for datasets, triggers, global parameters, identity, IR; SSIS/managed VNet gaps | ms.date 2026-11-06 |
| [adf-compare] | [Differences between Data Factory in Fabric and Azure](https://learn.microsoft.com/en-us/fabric/data-factory/compare-fabric-data-factory-and-azure-data-factory) | ~90% activities; SSIS N/A; managed VNet TBD; SHIR vs OPDG; publish removed; CDC → Copy job; Synapse Link → mirroring | ms.date 2026-11-06 |
| [adf-mdf] | [Mapping Data Flow Transforms in Dataflow Gen2](https://learn.microsoft.com/en-us/fabric/data-factory/dataflow-gen2-mapping-data-flows-transforms) | GA MDF transforms; flowlets/Data Flow Library/UDF/gateway limitations; pipeline-only execution | ms.date 2026-11-06 |
| [adf-dbt] | [dbt Job in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/data-factory/dbt-job-overview) | GA; managed runtime; adapters and versions; no build caching, 5,000 files, GitHub PAT | ms.date 2026-08-19 |
| [fabric-migrate] | [Migration Assistant for Fabric Data Warehouse](https://learn.microsoft.com/en-us/fabric/data-warehouse/migration-assistant) | DACPAC/connection source; migrated objects; Copy job for data; T-SQL and security limitations | ms.date 2025-08-19 |
| [fabric-migrate-connect] | [Migrate with a direct connection to the source system](https://learn.microsoft.com/en-us/fabric/data-warehouse/migrate-using-connection-to-source-system) | "For SQL Server, Azure SQL Database, or Azure SQL Managed Instance, select SQL Server database" | read 2026-11-24 |
| [wh-tsql] | [T-SQL Surface Area in Fabric Data Warehouse](https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area) | unsupported commands: `CREATE USER`, recursive queries, materialized views, synonyms, triggers, `SET TRANSACTION ISOLATION LEVEL`; `ALTER TABLE` subset; `MERGE` GA | ms.date 2026-09-16 |
| [wh-limits] | [Limitations of Fabric Data Warehouse](https://learn.microsoft.com/en-us/fabric/data-warehouse/limitations) | cross-region connections unsupported; feature-specific limits | ms.date 2026-07-29 |
| [wh-query] | [Query the Warehouse or SQL analytics endpoint](https://learn.microsoft.com/en-us/fabric/data-warehouse/query-warehouse) | cross-database queries are current-workspace only; three-part names | ms.date 2026-01-06 |
| [lh-endpoint] | [What is the SQL analytics endpoint for a lakehouse?](https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint) | read-only; `/tables` only; column mapping by ID unsupported; 150 items per workspace | ms.date 2026-11-10 |
| [onelake-overview] | [OneLake overview](https://learn.microsoft.com/en-us/fabric/onelake/onelake-overview) | one OneLake per tenant; Delta/Iceberg; shortcuts; mirroring copies vs metadata mirroring | ms.date 2026-03-09 |
| [onelake-iceberg] | [Use Iceberg tables with OneLake](https://learn.microsoft.com/en-us/fabric/onelake/onelake-iceberg-tables) | metadata virtualisation both directions; Parquet only; Iceberg V2/V3; latest metadata version | read 2026-11-24 |
| [fabric-sql-db-limits] | [Limitations for SQL database in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/database/sql/limitations) | 32 vCores, 4 TB; SQL analytics endpoint is read-only and the same experience | read 2026-11-24 |
| [dp-deploy] | [Deployment pipelines deploy content](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/deploy-content) | full/selective/backward deploy; adjacent stages; select related; dependency failure; deployment plan preview | ms.date 2026-09-24 |
| [dp-history] | [Deployment pipelines history](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/deployment-history) | history is a log; failed items; no rollback operation documented | read 2026-11-24 |
| [dbx-warehouse-types] | [SQL warehouse types](https://learn.microsoft.com/en-us/azure/databricks/compute/sql-warehouse/warehouse-types) | serverless/pro/classic; startup; credential passthrough not supported; use pro for custom networking | ms.date 2026-11-18 |
| [dbx-warehouse-behavior] | [SQL warehouse sizing, scaling, and queuing behavior](https://learn.microsoft.com/en-us/azure/databricks/compute/sql-warehouse/warehouse-behavior) | cluster sizes 2X-Small–5X-Large; one cluster per 10 concurrent queries; min/max clusters | ms.date 2026-11-20 |
| [dbx-merge] | [MERGE INTO](https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/delta-merge-into) | Delta-only; `WITH SCHEMA EVOLUTION` from Runtime 15.2; multiple-match error | ms.date 2026-09-11 |
| [dbx-atomic] | [ATOMIC compound statement](https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/sql-ref-syntax-txn-begin-atomic) | multi-statement transactions; UC managed; catalog commits; SQL warehouse/Runtime 18+; no nesting | ms.date 2026-10-07 |
| [dbx-sql-ref] | [SQL language reference](https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/) | Spark SQL/ANSI dialect; DDL/DML surface; materialized views; three-level names | ms.date 2026-11-18 |
| [dbx-federation] | [Connect to external databases and catalogs](https://learn.microsoft.com/en-us/azure/databricks/query-federation/) | Lakehouse Federation is read-only; query vs catalog federation; supported sources | ms.date 2026-11-12 |
| [dbx-fed-sqlserver] | [Run federated queries on Microsoft SQL Server](https://learn.microsoft.com/en-us/azure/databricks/query-federation/sql-server) | SQL Server/Azure SQL DB/MI; pro or serverless SQL warehouse; no window pushdown; Entra OAuth option | ms.date 2026-10-09 |
| [dbx-lakeflow-connect] | [Lakeflow Connect connector concepts](https://learn.microsoft.com/en-us/azure/databricks/ingestion/lakeflow-connect/) | database CDC incl. SQL Server; ingestion gateway; on-prem via ExpressRoute; deployment via bundles | ms.date 2026-11-18 |
| [dbx-jobs] | [Lakeflow Jobs](https://learn.microsoft.com/en-us/azure/databricks/jobs/) | jobs/tasks/triggers; system tables; 2,000 concurrent tasks, 12,000 jobs, 1,000 tasks; ADF can trigger | ms.date 2026-11-05 |
| [dbx-bundles] | [What are Declarative Automation Bundles?](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/) | bundle definition; CLI deploy; targets; source-control model | ms.date 2026-11-05 |
| [dbx-bundles-tasks] | [Develop Declarative Automation Bundles](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/work-tasks) | validate/deploy/run/destroy lifecycle; unique identity; destroy is permanent | ms.date 2026-09-11 |
| [dbx-bundles-resources] | [Declarative Automation Bundles resources](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/resources) | supported resources: catalogs, schemas, volumes, SQL warehouses, jobs, pipelines, dashboards; no table/view resource | ms.date 2026-11-20 |
| [dbx-bundles-settings] | [Declarative Automation Bundles configuration](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/settings) | `databricks.yml`, targets, variables, resource mapping | ms.date 2026-09-11 |
| [dbx-tf-table] | [databricks_sql_table](https://github.com/databricks/terraform-provider-databricks/blob/master/docs/resources/sql_table.md) | official Terraform resource for managed/external tables and views | read 2026-11-24 |
| [dbx-uniform] | [Read Delta Lake tables with Iceberg clients](https://learn.microsoft.com/en-us/azure/databricks/delta/iceberg-reads) | UniForm; Delta → Iceberg read; Runtime 14.3+; read-only for Iceberg clients | read 2026-11-24 |
| [dbx-iceberg-catalog] | [Access Azure Databricks tables from Apache Iceberg clients](https://learn.microsoft.com/en-us/azure/databricks/external-access/iceberg) | managed Iceberg read/write; foreign Iceberg read-only; Delta with Iceberg reads read-only | read 2026-11-24 |
| [dbx-aim] | [Automatic identity management](https://learn.microsoft.com/en-us/azure/databricks/admin/users-groups/automatic-identity-management) | Entra source of record; default after 2025-08-01; SCIM comparison; nested groups; service principals on first use | ms.date 2026-11-19 |
| [dbx-admin-concepts] | [Azure Databricks administration overview](https://learn.microsoft.com/en-us/azure/databricks/admin/admin-concepts) | account, workspace and metastore admin split; first account admin needs Entra Global Administrator; workspace admins manage cluster policies | ms.date 2026-11-19 |
| [dbx-uc-setup] | [Unity Catalog setup guide](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/setup-uc) | metastore → catalog → schema → grant; account/workspace/metastore admin roles; UC-compliant compute | ms.date 2026-10-06 |
| [dbx-cloud-storage] | [Connect to cloud object storage using Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/) | storage credential → external location → managed/external tables; ADLS managed identity; OneLake not supported by Unity Catalog | ms.date 2026-11-20 |
| [dbx-terraform] | [Databricks Terraform provider](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/terraform/) | Terraform for cloud/admin, bundles for jobs/pipelines/notebooks — two tools, not Fabric-specific | ms.date 2026-11-04 |
| [dbx-billing] | [Billable usage system table reference](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/billing) | `system.billing.usage`; `usage_unit = DBU`; SKU and metadata | ms.date 2026-11-20 |
| [dbx-audit] | [Diagnostic log reference](https://learn.microsoft.com/en-us/azure/databricks/admin/account-settings/audit-logs) | audit-log system table vs Azure Monitor diagnostic settings; account-level events absent from diagnostics | ms.date 2026-11-19 |
| [dbx-dashboards] | [Dashboards](https://learn.microsoft.com/en-us/azure/databricks/dashboards/) | AI/BI dashboards; bundles and Git support; Genie | ms.date 2026-11-05 |
| [dbx-purview] | [Connect to and manage Azure Databricks Unity Catalog in Microsoft Purview](https://learn.microsoft.com/en-us/purview/register-scan-azure-databricks-unity-catalog) | Purview-side scan; SQL warehouse + PAT/SP/MI; system.access lineage; external tables no lineage; SQL warehouse no column lineage | ms.date 2026-10-13 |
| [purview-retire] | Same Purview page, retirement banner; [retirement announcement](https://aka.ms/DG-Deprecation) | Purview data governance retiring; new accounts blocked; maintenance to 2027-11-12; security/compliance unaffected | read 2026-11-24 |
| [pbi-dbx] | [Databricks Power Query Connector](https://learn.microsoft.com/en-us/power-query/connectors/databricks) | Power BI connection to Databricks SQL warehouse; Import/DirectQuery; Azure uses the Azure Databricks connector | ms.date 2026-10-15 |
| [dbx-lakebridge] | [databrickslabs/lakebridge](https://github.com/databrickslabs/lakebridge) | migration accelerator; explicitly not SLA-supported | read 2026-11-24 |

[adf-overview]: https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-overview
[adf-upgrade]: https://learn.microsoft.com/en-us/fabric/data-factory/upgrade-planning-azure-data-factory
[adf-compare]: https://learn.microsoft.com/en-us/fabric/data-factory/compare-fabric-data-factory-and-azure-data-factory
[adf-mdf]: https://learn.microsoft.com/en-us/fabric/data-factory/dataflow-gen2-mapping-data-flows-transforms
[adf-dbt]: https://learn.microsoft.com/en-us/fabric/data-factory/dbt-job-overview
[fabric-migrate]: https://learn.microsoft.com/en-us/fabric/data-warehouse/migration-assistant
[fabric-migrate-connect]: https://learn.microsoft.com/en-us/fabric/data-warehouse/migrate-using-connection-to-source-system
[wh-tsql]: https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area
[wh-limits]: https://learn.microsoft.com/en-us/fabric/data-warehouse/limitations
[wh-query]: https://learn.microsoft.com/en-us/fabric/data-warehouse/query-warehouse
[lh-endpoint]: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint
[onelake-overview]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-overview
[onelake-iceberg]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-iceberg-tables
[fabric-sql-db-limits]: https://learn.microsoft.com/en-us/fabric/database/sql/limitations
[dp-deploy]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/deploy-content
[dp-history]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/deployment-history
[dbx-warehouse-types]: https://learn.microsoft.com/en-us/azure/databricks/compute/sql-warehouse/warehouse-types
[dbx-warehouse-behavior]: https://learn.microsoft.com/en-us/azure/databricks/compute/sql-warehouse/warehouse-behavior
[dbx-merge]: https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/delta-merge-into
[dbx-atomic]: https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/sql-ref-syntax-txn-begin-atomic
[dbx-sql-ref]: https://learn.microsoft.com/en-us/azure/databricks/sql/language-manual/
[dbx-federation]: https://learn.microsoft.com/en-us/azure/databricks/query-federation/
[dbx-fed-sqlserver]: https://learn.microsoft.com/en-us/azure/databricks/query-federation/sql-server
[dbx-lakeflow-connect]: https://learn.microsoft.com/en-us/azure/databricks/ingestion/lakeflow-connect/
[dbx-jobs]: https://learn.microsoft.com/en-us/azure/databricks/jobs/
[dbx-bundles]: https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/
[dbx-bundles-tasks]: https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/work-tasks
[dbx-bundles-resources]: https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/resources
[dbx-bundles-settings]: https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/settings
[dbx-tf-table]: https://github.com/databricks/terraform-provider-databricks/blob/master/docs/resources/sql_table.md
[dbx-uniform]: https://learn.microsoft.com/en-us/azure/databricks/delta/iceberg-reads
[dbx-iceberg-catalog]: https://learn.microsoft.com/en-us/azure/databricks/external-access/iceberg
[dbx-aim]: https://learn.microsoft.com/en-us/azure/databricks/admin/users-groups/automatic-identity-management
[dbx-admin-concepts]: https://learn.microsoft.com/en-us/azure/databricks/admin/admin-concepts
[dbx-uc-setup]: https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/setup-uc
[dbx-cloud-storage]: https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/
[dbx-terraform]: https://learn.microsoft.com/en-us/azure/databricks/dev-tools/terraform/
[dbx-billing]: https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/billing
[dbx-audit]: https://learn.microsoft.com/en-us/azure/databricks/admin/account-settings/audit-logs
[dbx-dashboards]: https://learn.microsoft.com/en-us/azure/databricks/dashboards/
[dbx-purview]: https://learn.microsoft.com/en-us/purview/register-scan-azure-databricks-unity-catalog
[purview-retire]: https://aka.ms/DG-Deprecation
[pbi-dbx]: https://learn.microsoft.com/en-us/power-query/connectors/databricks
[dbx-lakebridge]: https://github.com/databrickslabs/lakebridge

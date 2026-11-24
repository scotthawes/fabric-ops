# Which specialist tools earn their place beside Fabric for a six-person team?

- **Status:** answered
- **Checked:** 2026-11-24
- **Blocks:** the work repo's tooling annex (what to buy none of, and what to revisit), and the scope of the schema stage. It does not overturn ADR [0008](../adr/0008-schema-is-state-based.md); it records why that ADR survives a serious look at dbt.
- **Sibling notes:** [`data-stack-which-layers-exist-and-what-replaces-each.md`](data-stack-which-layers-exist-and-what-replaces-each.md) for the layer map and the Fabric-versus-Databricks comparison — this note does not repeat it; [`schema-and-ddl-management.md`](schema-and-ddl-management.md) for DDL mechanics; [`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md) for the mirroring source list; [`gateway-and-connectivity.md`](gateway-and-connectivity.md) for gateways; [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) for what deploys; [`purview-and-lineage.md`](purview-and-lineage.md) and [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) for the native governance and observability surfaces; [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md) for CU vocabulary.

## Short answer

**Native is enough at every layer, and the one layer that is genuinely contested — the schema language — still resolves to native.** The Fabric dbt job is real, GA and well built, but it runs dbt Core 1.11 through `dbt-fabric` 1.10.0 on a managed runtime that trails the adapter, while the dbt products that supply docs, lineage and a semantic layer are not documented as supporting Fabric at all; for a T-SQL team whose `.sqlproj` already works, dbt is a second modelling language bought for tests and documentation, not a deployment mechanism.

The recurring cost of every candidate is the same: **a second metadata, permission or alerting plane** that three engineers must own. That is why the answer is not "which tool is better" but "which gap is large enough to justify a new plane", and the measured gaps in this estate are small: SQL Server is mirrored, ADF is the orchestrator, Power BI is the semantic layer, and Fabric's catalog is the catalog.

Two vendor categories survive contact with the evidence: a **CDC connector** only if a source appears that neither mirroring nor Copy job can reach, and **data-quality checks** only if they are written in T-SQL or dbt tests rather than a new Python platform. Everything else on the list is a later purchase with a named trigger, not a migration decision.

## Detail

### 0. The frame: three tests, and the plane tax

Every candidate below is judged on the same three questions, in this order.

| Test | Question | Why it decides |
| --- | --- | --- |
| **Coverage gap** | Is there a thing the estate must do that Fabric cannot do *at all*? | "Worse than a specialist" is not a gap; three engineers can absorb "less polished". |
| **Plane tax** | Does it add an identity, metadata or alerting plane we must operate and reconcile? | Fabric already spans Entra, a workspace model, OneLake roles, the OneLake catalog, Monitor hub and Capacity Metrics. Each vendor adds one more place where "who can see what" and "what ran" is answered differently. |
| **Skill fit** | Can the people who are here today run it? | Strongest skills are T-SQL and Azure Data Factory; no stated Spark or Python depth. A tool that requires an owner the team does not have is a hiring decision wearing a licence. |

The estate today has **no specialist tools** — ADF, Terraform, `.sqlproj`, Azure SQL Database. So the default is native, and a candidate has to displace something, not merely improve on it.

Four planes are worth naming once and reusing:

| Plane | Fabric's answer | What a vendor typically does to it |
| --- | --- | --- |
| Identity and authorisation | Entra ID; workspace roles Admin/Member/Contributor/Viewer; OneLake data-access roles; no SQL auth on the T-SQL endpoint ([`onelake-security-model.md`](onelake-security-model.md)) | Adds its own RBAC, service accounts and permission model that must be mapped onto Entra groups |
| Metadata | OneLake catalog (Explore / Govern / Secure), endorsement, sensitivity labels, item-level lineage ([`purview-and-lineage.md`](purview-and-lineage.md)) | Adds a second catalog that is only as current as its scan or push |
| Execution | Pipelines, Copy job, notebooks, dbt job, warehouse | Adds a control plane that schedules and retries outside Fabric |
| Alerting | Monitor hub, workspace monitoring, Capacity Metrics, Activator ([`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md)) | Adds a second alerting surface with its own on-call expectations |

### 1. One table across every layer

Legend: **native** = use Fabric's own surface; **later** = defensible, but only on the named trigger; **no** = does not earn its place for this team.

| Layer | Native Fabric surface | Specialist contenders | Verdict for this team |
| --- | --- | --- | --- |
| **Transformation / schema** | Warehouse T-SQL; `.sqlproj` + SqlPackage (DacFx, preview); lakehouse tables via notebook DDL or `dbt-fabricspark` | dbt (Core, platform, or the Fabric dbt job); Liquibase/Flyway (no first-party Fabric support) | **Native — keep `.sqlproj`.** dbt is the only serious contender and loses on toolchain position (§2.5), not on merit |
| **Ingestion** | Mirroring (12 GA sources), Copy job (full/incremental/CDC), Copy activity, Dataflow Gen2, gateways | Fivetran, Airbyte, Qlik Replicate, Matillion | **Native**, unless a source has no native path — then one CDC vendor, chosen for landing natively in OneLake (§3) |
| **BI** | Power BI, Direct Lake over OneLake, XMLA | Sigma, Tableau, Looker | **Native.** Power BI stays; external BI is a reporting-estate decision, not a Fabric one (§4.2) |
| **Semantic layer** | The Power BI semantic model (TMDL, RLS/OLS, DAX) | dbt Semantic Layer, AtScale, Cube | **No second layer.** Two metric definitions for one business is a governance cost with no matching saving (§4.3) |
| **Catalog** | OneLake catalog: Explore, Govern, Secure; endorsement; domains; labels | Collibra, Atlan, Alation, DataHub | **Native.** Do not propose Purview data governance as an anchor; it is retiring into Fabric (§4.4) |
| **Data quality** | No data-quality item type; validation is T-SQL assertions, notebook code or dbt tests | Great Expectations, Soda, dbt tests | **Native first**: assertions written in T-SQL. dbt tests only if dbt is adopted. GX only with a Python owner (§4.5) |
| **Observability** | Monitor hub (preview), workspace monitoring (Eventhouse, 30-day default), Capacity Metrics (14/30 days) | Monte Carlo, Datafold, Sifflet, DataHub Cloud | **Native.** The gaps are alert routing and retention, both fixable inside Fabric (§4.6) |
| **Streaming** | Eventstream (Kafka endpoint, Eventhouse, Activator), Eventhouse/KQL | Confluent, self-managed Kafka | **Native.** Eventstream exposes a Kafka endpoint and runs on Event Hubs; no cluster to operate (§5.1) |
| **Orchestration** | Data Factory pipelines and schedules; Apache Airflow job item | Dagster, Prefect, managed Airflow | **Native.** Airflow only for a Python DAG someone already owns (§5.2) |
| **ML** | Fabric Data Science: notebooks, MLflow experiments, ML model items | Azure Machine Learning, Databricks | **Later.** No stated ML use case; ML experiments are also not deployable items (§5.3) |
| **Reverse ETL** | None native | Hightouch, Census | **No.** Category has folded into marketing platforms; buy it from marketing, not from the platform budget (§5.4) |
| **Data sharing** | OneLake shortcuts; Delta Sharing (`share` API group) | External data-sharing platforms | **Native.** Shortcuts first; Delta Sharing only for an external organisation (§5.5) |
| **Cost tooling** | Capacity Metrics app; capacity overage and surge protection; Azure Cost Management | Third-party FinOps | **Native.** One capacity, one bill, one app (§5.6) |

### 2. Deep: dbt versus `.sqlproj` + T-SQL

This is the fork that decides whether schema stays DACPAC-first or becomes model-first, and it changes the pipeline: a DACPAC is a deploy artefact with a diff, a dbt project is a program with a DAG.

#### 2.1 What the Fabric dbt job actually is

| Property | Documented state |
| --- | --- |
| Status | "dbt Job in Microsoft Fabric is generally available (GA)" (ms.date 2026-08-19) |
| What it runs | dbt Core, through a "managed execution environment … dbt job runtime V1.0", created by default |
| Adapters | `dbt-fabric` **1.10.0**, `dbt-fabricspark` **1.12.2**, `dbt-sqlserver` **1.9.1**, `dbt-postgres` **1.10.0**, `dbt-snowflake` **1.11.5** — all on **dbt Core 1.11**, Python **3.12** |
| Authentication per adapter | Warehouse and Lakehouse: **Microsoft Entra (OAuth)**. Azure SQL: Basic or SPN. PostgreSQL: Basic. Snowflake: Snowflake auth |
| Permissions | Workspace **Contributor** or higher; read/write on the target warehouse; "build and read/write access to linked datasets and connections" |
| Project source | Authored in the item (Explorer: `models/`, `seeds/`, `schema.yml`, `dbt_project.yml`) **or** connected from a GitHub repository |
| Where the source may live | "you must place the `dbt_project.yml` file in the root directory of the repository" |
| GitHub authentication | "a classic personal access token (PAT) only" |
| Limitations | **No build caching** — "dbt artifacts from previous runs aren't available for recompilation"; no import above **5,000 files**; "some partner adapters aren't yet supported" |
| Execution settings | Threads, fail fast, full refresh; run selected models or advanced selectors |
| Lineage and docs claim | "Visual insights into dbt runs, tests, and lineage — all within the same workspace" |
| Deployability | A `DataBuildToolJob` item: Git-supported, definition API, `fabric-cicd` handler; **no Terraform resource** ([`item-type-deployment-coverage.md`](item-type-deployment-coverage.md)) |

Two things the page does **not** say, and they matter:

- **Whose identity executes the models.** It says the *user* needs read/write on the warehouse, not what principal the scheduled run uses. RLS, audit attribution and `ALTER` rights therefore cannot be predicted from this page.
- **Whether a GitHub-connected project is versioned twice.** The item is Git-supported; the project may also live in GitHub. Which copy is authoritative is unstated.

#### 2.2 What `dbt-fabric` supports, and where it stops

The adapter is Microsoft-maintained and its repository is candid about the Warehouse's limits:

| Area | Documented behaviour | Consequence |
| --- | --- | --- |
| Driver | `mssql-python`, which "bundles its own driver" | No ODBC driver to install or patch |
| Keys | Primary/unique keys are `NONCLUSTERED NOT ENFORCED`, foreign keys `NOT ENFORCED`, same-database only; "Warehouse does not enforce those keys during subsequent DML" | dbt tests, not constraints, are the integrity mechanism |
| `NOT NULL` | "Declare `NOT NULL` in an enforced model contract and rebuild the table" | Physical nullability is a rebuild, not an `ALTER` |
| Concurrency | Warehouse DDL "hold[s] catalog locks that can block `sys.tables`/`sys.views` reads"; guidance is `threads: 4`–`8`, `query_timeout: 30`, `flags: cache_selected_only: true` for "500+ models or concurrent dbt runs" | Parallelism is capped by the engine, not by dbt |
| Version position | Adapter repository documents a 1.12 series requiring dbt Core 1.12; the Fabric runtime pins **1.10.0 on Core 1.11** | The managed runtime trails the adapter; features arrive in the job later |
| Packages | Reviewed list includes `dbt_utils`, `dbt_expectations`, `dbt_date`, `elementary`, `dbt_project_evaluator`, `dbt_artifacts`, `dbt_constraints`, `audit_helper`, `dbt_profiler`, `dbt_external_tables` | A supportable package set exists, with caveats |
| Package caveats | "regex tests are not covered by this update, Elementary 0.26.1 explicitly rejects regex tests on Fabric"; `dbt_artifacts` 2.11.1 needs an unsubmitted upstream patch | The edges are unpolished, and some are upstream's |
| Known Core 1.12 defect | `run-operation --sql` "starts a transaction but does not commit it" — inline writes can be rolled back despite success | Do not run data fixes through a dbt operation |

Lakehouse modelling is a separate adapter with separate semantics: `dbt-fabricspark` runs through Livy or an in-process session, needs a schema-enabled lakehouse for four-part naming, and cannot create a remote schema in `method: session` ([`schema-and-ddl-management.md`](schema-and-ddl-management.md) §4).

#### 2.3 What dbt adds that a DACPAC cannot — and the reverse

| Capability | dbt | `.sqlproj` + SqlPackage |
| --- | --- | --- |
| **Data tests** | First-class: four built-ins (`unique`, `not_null`, `accepted_values`, `relationships`), singular tests as SQL files, `severity`, `error_if`/`warn_if`, `store_failures` in a `dbt_test__audit` schema | None. DacFx compares structure, never data |
| **Unit tests** | `data_tests:` vs `unit_tests:` are distinct features as of the tests rename | None |
| **Documentation** | `description:` on models, columns, sources and seeds; `docs` blocks in Markdown; generated docs site | Extended properties in the project, not a generated site |
| **Lineage** | The project DAG from `ref()`; dbt Catalog adds column-level lineage on paid hosted plans; `exposures` declare downstream BI consumption | Dependency order inside the project; no graph artefact, no downstream consumers |
| **State-based diff** | `state:modified` and `--defer` compare against a previous `manifest.json`, not a live catalog | **`/Action:DeployReport`** — "the changes that a publish action would take", plus `/Action:Script` |
| **Drift detection** | No live-schema comparison; `dbt source freshness` checks data recency | `DeployReport` compares intent to reality without changing anything |
| **Programmable objects** | None — a model is one `SELECT` (or a materialisation); procedures, scalar/table functions have no model form | Procedures and views are project objects (with DacFx caveats); `PreDeploy`/`PostDeploy` scripts carry the rest |
| **Security objects** | Nothing; dbt has no grant model | Nothing: "roles, users, and `GRANT`/`DENY` permissions aren't included in the SQL database project" |
| **Seed/reference data** | `seeds/`, loadable on `dbt seed`/`dbt build` | Post-deploy script, hand-written and idempotent |
| **Ordering** | `ref()` DAG; each model reconciled every run | Dependency analysis inside the project; publish is a diff |

The honest summary: **dbt owns data assertions and documentation; DacFx owns schema intent and drift.** Neither is a superset, and the estate currently has no tool that does either job, so adopting dbt buys two capabilities the DACPAC lacks, at the price of a second modelling language.

#### 2.4 What a `.sqlproj` → dbt migration actually looks like

Object by object, for a warehouse project:

| `.sqlproj` artefact | dbt form | What does not translate |
| --- | --- | --- |
| `Tables/*.sql` (`CREATE TABLE`) | Model with `materialized='table'` | Declared keys become `NOT ENFORCED` at best; computed columns and partitioned tables are refused by Warehouse regardless of tool |
| `Views/*.sql` | Model with `materialized='view'` | Nothing structural, but the replace semantics are unverified: `CREATE [ OR ALTER ] VIEW` is in the Fabric syntax block while its "Applies to" prose omits Fabric ([`schema-and-ddl-management.md`](schema-and-ddl-management.md) §3) |
| Stored procedures | **No equivalent.** Remains a T-SQL script invoked by a pipeline activity or notebook | Control flow, temp tables, `TRY/CATCH`, dynamic SQL: dbt models are single `SELECT`s |
| Scalar / table-valued functions | **No equivalent** | Same reason |
| Indexes, constraints | `dbt_constraints` package, creating `NOT ENFORCED` keys | Enforcement; Warehouse has no enforced PK/FK and no unique indexes |
| `GRANT`/`DENY`, roles, users | Nothing in either tool | A separate security script, in both worlds; `CREATE USER` is unsupported on the T-SQL endpoint anyway |
| `Scripts/PreDeploy.sql`, `PostDeploy.sql` | `on-run-start` / `on-run-end` hooks | Single-file, no `:r`, must be idempotent — same constraint, different syntax |
| `/Action:DeployReport` gate | No equivalent | dbt tests check data; nothing compares schema intent to the live warehouse |
| Seed data | `seeds/*.csv` | — |

Two operational rules follow, and they are the part a team gets wrong:

1. **One writer per object.** A model and a `.sqlproj` table entry that both claim `dbo.dim_customer` is the two-writer problem in schema form: whichever runs last wins, and `DropObjectsNotInSource` can delete what dbt created. Run both tools only on disjoint schemas (for example, DACPAC owns `dbo`, dbt owns `mart`).
2. **The DAG does not replace the migration order.** dbt has no migrations ledger; a rename is a new model plus a dropped relation, and `--full-refresh` is the blunt instrument. A team that needs reviewable ordering keeps the ordered-script pattern in [`schema-and-ddl-management.md`](schema-and-ddl-management.md) §5 whether or not dbt is present.

#### 2.5 The ownership and metadata plane — and the finding that decides it

Three ways to run dbt, and only two of them reach Fabric:

| | dbt Core in the team's own pipeline | Fabric dbt job (item) | dbt platform (hosted) |
| --- | --- | --- | --- |
| Where it runs | ADO agent or notebook, calling `dbt build` | Fabric-managed runtime, scheduled by the item | dbt Labs-hosted |
| Version pinned by | Team (`pip install dbt-fabric`, or a container) | Fabric: `dbt-fabric` 1.10.0 / Core 1.11 | dbt Labs |
| Metadata plane | None beyond `target/manifest.json` artefacts in the pipeline | Fabric item + Fabric Git + job history; "lineage … within the same workspace" | **A second SaaS**: PostgreSQL backend, S3-compatible artefact storage, its own RBAC and SSO, hosted docs |
| Cost shape | Compute only | Capacity consumption plus item overhead | Subscription per seat plus compute |
| Documented Fabric support | Yes — `dbt-fabric` is the adapter | Yes — it is the Fabric product | **No.** The dbt v2 adapter list is Snowflake, BigQuery, Databricks, Redshift, Apache Spark, DuckDB, ClickHouse; the hosted "set up in the dbt platform" pages exist for BigQuery, ClickHouse, Databricks, Redshift and Snowflake only. Fabric and SQL Server are absent |

That last row is the finding that settles the question for this team: **the dbt products that make dbt attractive — hosted docs, dbt Catalog, the Semantic Layer — are not documented as supporting a Fabric warehouse.** The Fabric dbt job gives back scheduling, logs and a workspace-scoped lineage view, and stops there: no build caching, no dbt Catalog, no Semantic Layer, no hosted docs. So "adopt dbt" for this estate means "adopt dbt Core's modelling language and test framework", not "adopt the dbt platform".

The usual objection to dbt's hosted product — that it is a second metadata plane — therefore does not arise: it is not a documented option for a Fabric warehouse, and the real choice is between a Fabric item and a pipeline step, both of which keep metadata inside the tenant.

#### 2.6 The decision rule

| Condition | Decision |
| --- | --- |
| Warehouse schema, T-SQL team, `.sqlproj` already works, no Python owner | **Keep `.sqlproj` + SqlPackage.** Non-negotiable on least-operational-burden |
| Lakehouse tables must be modelled (not just landed) | **dbt via `dbt-fabricspark`**, scoped to a lakehouse schema. This is already ADR [0008](../adr/0008-schema-is-state-based.md)'s position and this note does not change it |
| Model-level tests and generated documentation become a deliverable *for a business audience* | Revisit dbt for the warehouse mart layer, run it in the **Fabric dbt job**, and freeze the DACPAC to `dbo` (staging) so there is exactly one writer per schema |
| Someone asks for dbt Cloud / dbt Semantic Layer | Not available for Fabric as documented; the request is really for tests and docs, and the Fabric dbt job covers the run |
| Someone asks to migrate the whole warehouse to dbt | Refuse on evidence: it discards procedures and functions, buys no drift check, and replaces a state-based publish with a program that has no applied-state record |

**Verdict: keep `.sqlproj`.** dbt is a reasonable second language for a lakehouse mart layer and a poor replacement for a DACPAC-first warehouse. The trigger to reconsider is a documentation or testing obligation aimed at non-engineers — not a preference for dbt's ergonomics.

### 3. Deep: connector strategy

#### 3.1 What the native stack covers

| Surface | What it does | Documented limits that matter |
| --- | --- | --- |
| **Mirroring** | Continuous CDC replica into OneLake for **12 GA sources** (Azure SQL Database, SQL Managed Instance, PostgreSQL flexible server, Cosmos DB NoSQL, SQL Server 2016–2025, Oracle, Snowflake, BigQuery, SAP via Datasphere, Fabric SQL database, open mirroring, Databricks metadata) | No pause (stop disables, start reseeds), 1,000 tables, 1 TB change data/day, DDL behaviour differs per source ([`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md)) |
| **Copy job** | Full copy, watermark incremental, CDC replication, append/overwrite/merge/SCD Type 2, automatic table creation, audit columns, multiple schedules, gateway or VNet gateway | CDC sources are narrower than the connector list: Azure SQL DB, SQL MI, Fabric Lakehouse table, BigQuery, on-premises SQL Server, Oracle, Snowflake and SAP Datasphere outbound (three storage forms). SCD Type 2 is **preview** and unsupported for Oracle CDC and pre-created schemas |
| **Copy activity (pipeline)** | Same connector list, full control, user-defined queries, metadata-driven patterns; **no native watermark state** — the pipeline owns it | You build and maintain the state |
| **Dataflow Gen2** | Power Query: hundreds of connectors, "300+ transformations", multiple destinations (Lakehouse tables/files, Warehouse, SQL database, KQL database, Azure SQL, ADLS, S3 preview, BigQuery preview, Snowflake, PostgreSQL) | Low-code; row-by-row transforms run on Fabric SQL compute; Power Query semantics, not T-SQL |
| **Gateways** | On-premises data gateway (Windows, outbound only, monthly update, no rollback) or VNet data gateway | Binding is manual and not in the item definition ([`gateway-and-connectivity.md`](gateway-and-connectivity.md)) |

The decision guide is explicit about the split: mirroring for curated/reporting data because it "is free, requires minimal setup"; Copy job for raw ingestion because "you'll quickly need transformations, schema mapping, scheduling control, and incremental loading"; Eventstreams for real-time; pipelines for orchestration.

#### 3.2 Where the native stack stops

Four gaps, in the order they are likely to be hit:

1. **A source with no connector at all.** Fabric's own pages claim "more than 170 data sources". Outside that list are mainframe and midrange systems, several SaaS APIs, and anything bespoke. The escape routes are open mirroring (a landing-zone format you write) and a REST/ODBC connector — both of which mean you built the extractor.
2. **CDC on a source the Copy job does not list.** The CDC table is narrower than the connector table: MySQL, PostgreSQL, IBM Db2, Teradata and the file stores are full-load/watermark only. Mirroring covers PostgreSQL (GA) and MySQL (preview), so MySQL CDC has no GA native path, and PostgreSQL CDC is available only through mirroring.
3. **Schema drift on an existing destination.** Copy job creates tables that do not exist and maps columns; whether it **alters** an existing destination table when a source column is added is not stated on the pages read. Treat drift as the pipeline's problem until tested.
4. **Semantics beyond copy.** Soft deletes, history tables, inferred deletes, per-table type locking: Copy job has SCD Type 2 (preview) and merge; the rest is modelling work.

#### 3.3 The vendors, as their own documentation describes them

| Vendor | What its docs say it is | Documented Fabric destination | What it would add here | Verdict |
| --- | --- | --- | --- | --- |
| **Fivetran** | SaaS or Hybrid Deployment; "schema migrations" detect new tables, new columns, widening type changes, renames and PK changes, and push them automatically; delete capture with `_fivetran_deleted`; history mode as SCD2; sync frequency 1 minute to 24 hours; "data models" are dbt-compatible | **None documented.** The destination list is Apache Kafka, Azure Synapse, BigQuery, ClickHouse, Convex, Databricks, Managed Data Lake Service, Materialize, Milvus, MotherDuck, MySQL, Oracle, PostgreSQL, Redshift, SingleStore, Snowflake, SurrealDB, SQL Server, Teradata. Hybrid Deployment's supported destinations are a subset of those, also without Fabric | Automated schema drift and connector breadth | **Later, and only via a hop.** No Fabric destination means landing in SQL Server/Synapse/Databricks and copying again — a second plane plus a second move |
| **Airbyte** | Self-managed (Core, free/OSS), Cloud, hybrid ("Enterprise Flex"); "over 600 pre-built connectors", a no-code Connector Builder, Terraform provider, PyAirbyte | **Not verified.** The platform page read does not list destinations | Long-tail connector coverage, custom connectors | **Later.** Its differentiator is the long tail; this estate's sources are SQL Server and Azure SQL |
| **Qlik Replicate** | Log-based replication engine with endpoints; a **Microsoft Fabric target** exists and is documented as writing "data files to the Fabric landing zone" — i.e. through open mirroring, not into a warehouse table | **Yes**, via open mirroring | CDC from sources with no native path, using log-based replication | **Later.** Documented limits: UPDATE/DELETE need a primary key and full before-images; only `CREATE TABLE`, `ADD COLUMN`, `DROP TABLE` DDL; `TRUNCATE` unsupported; Transactional apply only; "no indication of whether the last file was processed" |
| **Matillion** | Push-down ELT for cloud data platforms, browser UI; its product site claims "over 250 pre-built connectors" plus custom connectors | **Not verified.** The documentation root returned 404 on 2026-11-24 | Visual ELT with push-down to the warehouse | **No, on the evidence read.** An ELT tool earns its place by writing to the warehouse; a Fabric target could not be confirmed |

Two observations that matter more than the comparison:

- **The destination question precedes the connector question.** A tool with 600 connectors and no Fabric destination requires an intermediate store. Fivetran's documented destination list is the clearest example: excellent connectors, one extra hop.
- **Mirroring has already removed the main use case.** The on-premises SQL Server is a GA mirroring source with CDC, and SQL Server is also a Copy job CDC source. The vendors' strongest pitch — log-based CDC from SQL Server — is the thing Fabric already does for free.

#### 3.4 The decision rule

```
Is the source in the mirroring GA list?
  yes → mirror it. Stop.
  no  → Is it a Copy job source with CDC or a usable watermark column?
          yes → Copy job. Stop.
          no  → Is it a Power Query connector in Dataflow Gen2?
                  yes → Gen2 (accepting low-code transforms). Stop.
                  no  → Build it (open mirroring / REST), or buy one CDC vendor —
                        and require that it lands natively in OneLake.
```

**Verdict: native.** No connector vendor is justified today. The trigger is a named source, owned by the business, that cannot be reached by mirroring, Copy job or Gen2 — at which point the tie-breaker is not connector count but whether the vendor can write to OneLake without an intermediate warehouse.

### 4. Moderate: BI, the semantic layer, catalog, quality, observability

#### 4.1 Power BI stays; Direct Lake changes the freshness and cost story

Direct Lake is not "Import with a shorter refresh". The documented differences that matter to this team:

| Property | Direct Lake on OneLake | Direct Lake on SQL (analytics endpoint) | Import |
| --- | --- | --- | --- |
| Refresh | "copies only metadata (known as framing), which can take a few seconds" | framing; falls back to DirectQuery when it cannot read Delta directly | full data copy; long, capacity-heavy |
| Latency | "quickly and automatically synchronizing a semantic model with its sources, making new data available … without refresh schedules" | same, with fallback | bounded by the refresh schedule |
| Licensing | **Fabric capacity (F SKU) only** | same | "Any Fabric or Power BI license (including Microsoft Fabric Free licenses)" |
| Gateways | "supports only cloud connections and cannot operate through any gateway" | same | gateway allowed |
| Region | semantic model and data source must be in the same region | same | n/a |
| RLS | semantic-model RLS works, but "strongly recommended to use a fixed identity cloud connection"; SQL-based RLS is **not** applied on OneLake | SQL RLS works but falls back to DirectQuery | duplicated in the model |
| Guardrails | per-SKU: parquet files, row groups, rows per table, model size on disk, max memory (F64: 5,000 / 5,000 / 1,500M rows / unlimited / 25 GB) | falls back instead of failing | memory-bound |

Three consequences a T-SQL team should hear plainly:

- **Direct Lake is a capacity decision.** Import and DirectQuery run on any Power BI licence; Direct Lake requires an F SKU. On a shared F capacity, a large Direct Lake model's memory paging competes with everything else.
- **The refresh disappears, the failure mode does not.** Framing is cheap, but a guardrail breach fails the refresh and the model "cannot be queried until the Delta tables are optimized" — so table maintenance (V-Order, row-group sizing) becomes a platform task, not a report-owner task.
- **Direct Lake on SQL is the bridge, and it is lossy.** It buys SQL-endpoint RLS/OLS and views, at the cost of DirectQuery fallbacks and no composite-model support on that path.

**Verdict: Power BI + Direct Lake, with the mart layer in the Warehouse.** That is the same answer as [`data-stack-which-layers-exist-and-what-replaces-each.md`](data-stack-which-layers-exist-and-what-replaces-each.md) §12; this note adds only the mechanism.

#### 4.2 When an external BI tool is justified

The criteria are about the reporting estate, not the platform:

| Trigger | Why it argues for an external tool | Why it might still lose |
| --- | --- | --- |
| A business unit already runs Tableau/Looker/Sigma and will not migrate | Forcing a migration is a change-management project, not a licence | The tool consumes Fabric through the SQL endpoint or XMLA; **Direct Lake is a Power BI-only storage mode**, so freshness and query cost revert to Import/DirectQuery behaviour |
| Embedded analytics inside a product | The tool may already fit the application's stack | Power BI Embedded supports Direct Lake, but "requires a V2 embed token" and a fixed identity for service principals |
| Very large semantic models across regions | External tools query the warehouse directly | The same region constraint applies to the model and its source |

No external BI tool was evaluated for its own Fabric connector in this note; that is a gap, not a recommendation (see "What this does not establish"). The platform-side statement is the one that holds: **Direct Lake does not travel**, so any external tool pays for the convenience of not being Power BI.

**Verdict: Power BI.** Revisit only when a reporting estate already exists elsewhere.

#### 4.3 A second semantic layer is a second definition of "revenue"

Fabric already ships a semantic layer: the Power BI semantic model — TMDL, relationships, DAX measures, RLS/OLS, XMLA endpoints. A specialist semantic layer (dbt Semantic Layer, AtScale, Cube) exists to serve *many* BI tools from *one* metric definition, and it is worth its toil only when there are many tools.

The dbt Semantic Layer is gated twice over for this estate:

- It requires "a dbt Starter or Enterprise-tier account", i.e. the hosted platform.
- The hosted platform's documented adapters do not include Fabric (§2.5), so a dbt Semantic Layer over a Fabric warehouse is not a documented configuration.

AtScale and Cube were not read for this note. The structural argument does not depend on them: with one BI tool, a second semantic layer means two places where a metric is defined, two permission models over the same tables, and a query path that bypasses the Power BI model that already enforces RLS.

**Verdict: no second semantic layer.** Trigger: two or more BI tools in production with conflicting metric definitions, which is a symptom of a governance problem, not a tooling gap.

#### 4.4 Catalog: Fabric's catalog is the anchor; Purview data governance is not

The native surface, as established in [`purview-and-lineage.md`](purview-and-lineage.md):

- **OneLake catalog** has three tabs: **Explore** (item list plus item details, the columns Owner / Refreshed / Endorsement / Sensitivity), **Govern** (Governance Insights, Recommended Actions, and — increasingly — administrative settings moved out of the admin portal), and **Secure** (workspace roles and OneLake security roles in one view).
- **Lineage** is item-level, per workspace, one hop upstream, no downstream cross-workspace edges, and no operation in the REST census returns an edge.
- **Endorsement** (Promoted / Certified / Master data) and ownership are human-set and have no write API.
- **Retention and coverage**: Govern's insights read Admin Monitoring Storage, refreshed daily; the tab is unavailable under Private Link.

What a catalog vendor adds is a **cross-platform** metadata plane: DataHub, for example, describes itself as a catalog for "metadata management, data discovery, and data governance" with lineage, profiling, data contracts, and (in the Cloud product) "automated anomaly detection and assertions". For an estate that is one tenant, one capacity and one storage layer, that plane duplicates what the OneLake catalog already shows and goes stale between scans.

**The dated constraint that overrides any catalog discussion:** Microsoft Purview's Unified Catalog and classic data-governance capabilities "are being retired … Microsoft is consolidating its data governance capabilities in Microsoft Fabric. New Microsoft Purview data governance accounts can no longer be created, and existing … capabilities will remain in maintenance mode through November 12, 2027." Purview data security and compliance, including sensitivity labels, are not affected. **Do not propose a new Purview account as the governance anchor**, and do not propose a third-party catalog as a substitute for the Fabric catalog either — it would be a third plane, not a second.

**Verdict: Fabric's OneLake catalog.** Revisit when a second platform (Databricks, Snowflake) makes cross-platform lineage a real requirement — and then as a metadata-mirroring or scanning design, not a "buy a catalog" decision.

#### 4.5 Data quality: assertions, not platforms

Fabric has **no data-quality item type** in the deployable list, and Delta's schema enforcement is a write-time type check, not a business rule. Quality therefore has to live somewhere the team already writes code:

| Option | What it gives | What it costs | Fit |
| --- | --- | --- | --- |
| **T-SQL assertions** written by the pipeline into a `dq.results` table | Thresholds, referential checks, row-count deltas, all in the language the team is strongest in; runs as a pipeline activity or a notebook cell | You write the framework and own the alerting | **Best fit.** No new plane, no new language |
| **dbt tests** | `unique`/`not_null`/`accepted_values`/`relationships`, singular SQL tests, severity, `store_failures` | Only exists if dbt is adopted (§2.6), and only covers dbt-built models | Good, conditional |
| **Great Expectations (GX Core)** | A Python framework: Data Context → Data Source → Expectation Suite → Validation Definition → **Checkpoint** (the production runner) → **Actions** (email/Teams) → **Data Docs** | A Python library, a deployment, and an owner; validation code is Python, not T-SQL | **Later**, only with a Python owner |
| **Soda** | Not read for this note | — | Unverified |

The category's real product is **routing**: who is told, when, and with what evidence. Fabric already has the delivery mechanism (Activator, pipeline failure notifications, workspace monitoring), so a quality platform mostly adds a second place to configure it.

**Verdict: T-SQL assertions first; dbt tests if dbt arrives.** GX is a hiring decision disguised as a library.

#### 4.6 Observability: the native surface is thin but sufficient at this size

What exists, from [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md):

| Need | Native answer | Documented limit |
| --- | --- | --- |
| Did it run, did it fail | Monitor hub Job runs, "the last five runs for each item" | Preview; retention undocumented |
| Queryable job history | Workspace monitoring: `ItemJobEventLogs` (`JobStatus`, `JobType`, `DurationMs`, start/end), plus workload logs | 30-day default retention; collection off until enabled; no backfill |
| Capacity cost and throttling | Capacity Metrics app; Real-Time hub `Microsoft.Fabric.Capacity.Summary` / `.State`; Activator rules | App "doesn't support alerts or notifications"; no Azure Monitor metric for `Microsoft.Fabric/capacities` |
| Row-level audit trail of ingestion | Copy job **audit columns** (extraction time, source path, workspace/item/run IDs, window bounds) | Copy job only |
| Freshness | Per-table "Last completed"; `ReplicatorBatchLatency` in `MirroredDatabaseTableExecution` | Mirroring and refresh only |

The vendors sell anomaly detection over volume, freshness, schema and distribution, plus routing. That is genuinely more than the above — but the above is queryable with KQL and already paid for, and the gap that actually bites this team is **retention** (30 days of job history, 14 days of compute), which is solved by writing to an Eventhouse, not by buying a monitor.

Two cautions recorded during this research and worth carrying into any purchase:

- **Datafold's documentation no longer leads with data diff.** Read on 2026-11-24, its docs describe a migration service ("Datafold helps you migrate and modernize your data stack… validated … as pull requests in your own repository"), with a note distinguishing "Datafold Classic". A product's front page moves; verify the specific capability at contract time.
- **Monte Carlo's documentation was unreachable** during this session (transport error), and Sifflet's was not read. Any claim about either would be unsourced here.

**Verdict: native, with an Eventhouse sink for retention.** Trigger for a vendor: more pipelines than one person can enumerate, or an SLO that requires per-model anomaly detection with routing.

### 5. Shallow sweep: one paragraph each, with the trigger

**5.1 Streaming — Eventstream and Eventhouse versus Confluent or self-managed Kafka.** Eventstream exposes an **Apache Kafka endpoint** and is "associated with Azure Event Hubs, a fully managed cloud-native service"; sources include Kafka, Confluent Cloud, Amazon MSK, Event Hubs, IoT Hub, MQTT (preview), CDC from SQL Server/Azure SQL/PostgreSQL/MySQL/MongoDB/Oracle (preview), plus Fabric's own job, capacity and OneLake events; destinations are Eventhouse, Lakehouse, Activator, a derived stream or a custom endpoint. Documented limits: 1 MB message, 90-day retention, at-least-once delivery, minimum F4. A Kafka estate therefore has a native home, and a team with no streaming requirement should not build one. **Trigger to revisit:** an existing Kafka cluster with topics the business already depends on, or a requirement for event-time processing (windowing, stream joins, per-event transforms) rather than table replication — mirroring copies tables, it does not process events.

**5.2 Orchestration — Data Factory pipelines versus Airflow, Dagster, Prefect.** The pipeline item is the same programming model the team already knows from ADF, scheduled per pipeline, with event triggers, `Invoke pipeline`, and an **Apache Airflow job** item for code-first Python DAGs (Airflow UI included, Git-supported, `fabric_apache_airflow_job` in Terraform). Fabric has "one schedule per pipeline … no schedule reuse or central hub", so the orchestrator's shape is per-pipeline, not a scheduler of schedulers. Adding Dagster or Prefect means a second scheduler, a second retry model and a second place where a run either happened or did not. **Trigger to revisit:** a genuinely code-first Python DAG with cross-system dependencies that pipelines express badly — and then use the Airflow job item, not a managed Airflow service.

**5.3 ML — Fabric Data Science and MLflow versus Azure ML or Databricks.** Fabric ships MLflow-backed **experiments** (runs, parameters, metrics, tags, run comparison, "Save as a ML model", MLflow 3 Logged Models and Traces) and **ML model** items. Both are marked preview in the Git supported-items list, and neither has a create-with-definition API — the model and experiment are **manual-only** items ([`item-type-deployment-coverage.md`](item-type-deployment-coverage.md)), which is disqualifying for anything that must be promoted through a pipeline. **Trigger to revisit:** a funded model with a serving requirement; then decide between Fabric (data-adjacent, weaker MLOps), Azure ML (managed MLOps) and Databricks (Spark-native), as a capability programme rather than a tool purchase.

**5.4 Reverse ETL — Hightouch, Census.** Hightouch describes itself as "a marketing platform that runs on your data warehouse", with audiences, journeys, native email/SMS/push delivery, identity resolution and syncs to ad platforms and CRMs. Hightouch's documentation is enough to show the category has folded into marketing tooling, which means it is bought by marketing against marketing outcomes, not by the data platform against platform outcomes; Census's documentation was not read. **Trigger to revisit:** a marketing or CRM team asks for warehouse-to-SaaS activation; route the request, do not own the tool.

**5.5 Data sharing — OneLake shortcuts and Delta Sharing.** Shortcuts are the native mechanism for referencing data in place: inside a lakehouse they are part of the item definition (`shortcuts.metadata.json`) and therefore deployable, and mirroring's metadata mode ("references source data through OneLake shortcuts instead of replicating it") shows how far they reach. Delta Sharing is the open protocol for sharing outside the tenant, and Fabric's REST census carries a `share` group with definition operations — but the sharing UX, recipient model and governance were not researched here. **Trigger to revisit:** a named external organisation needs governed access to a table or schema; until then, shortcuts cover internal cross-workspace reads.

**5.6 Cost tooling — Capacity Metrics and Azure Cost Management.** The capacity is an Azure resource with one bill, one SKU and one overage meter; the Capacity Metrics app reports utilisation, throttling, overage and carryforward on 30-second windows with 10–15 minutes of latency and 14-day compute history ([`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md)). A third-party FinOps tool would report the same CU from the same events, and would not be able to change the only three levers that matter (SKU size, overage threshold, surge protection). **Trigger to revisit:** multiple capacities across subscriptions or tenants, where allocation becomes a finance question rather than an operational one.

## What this settles

### Verdicts

| Layer | Verdict | One-line reason |
| --- | --- | --- |
| Schema / transformation | **Keep `.sqlproj` + SqlPackage** | dbt buys tests and docs, not deployment; it loses procedures, drift checking and the team's language |
| Ingestion | **Native: mirroring → Copy job → Dataflow Gen2** | 12 GA mirroring sources plus Copy job CDC cover this estate; no vendor has a documented Fabric destination advantage |
| BI | **Power BI + Direct Lake** | Direct Lake is capacity-only, gateway-free and Power BI-only; an external tool pays for leaving |
| Semantic layer | **One (Power BI)** | A second metric definition is a governance cost; the dbt Semantic Layer is not documented over Fabric |
| Catalog | **OneLake catalog** | One tenant, one catalog; Purview data governance is retiring into Fabric |
| Data quality | **T-SQL assertions** (dbt tests if dbt arrives) | Quality needs a runner you already operate, not a Python platform |
| Observability | **Native + Eventhouse for retention** | Monitor hub, workspace monitoring and Capacity Metrics cover the need; the gap is retention, not detection |
| Streaming | **Native if needed** | Eventstream is Kafka-compatible and runs on Event Hubs |
| Orchestration | **Pipelines; Airflow job only for owned Python DAGs** | ADF skills transfer; a second scheduler is a second failure mode |
| ML | **Later** | No use case; model and experiment items are manual-only |
| Reverse ETL | **No** | Owned by marketing, not the platform |
| Data sharing | **Shortcuts; Delta Sharing for externals** | Already native and deployable |
| Cost tooling | **Native** | One capacity, one bill, three levers |

### Now versus later

**Decide now (and stop discussing):** `.sqlproj` stays the warehouse schema mechanism; Power BI is the BI and semantic layer; mirroring is the ingestion default for SQL Server and Azure SQL; the OneLake catalog is the catalog; no third-party connector, catalog, quality or observability vendor is procured.

**Decide later, on a named trigger:** dbt for a lakehouse mart layer (trigger: a modelling or testing obligation aimed at non-engineers); a CDC connector vendor (trigger: a source with no native path); an external BI tool (trigger: an existing non-Microsoft reporting estate); GX (trigger: a Python owner); an observability vendor (trigger: more pipelines than one person can enumerate); ML (trigger: a funded use case).

**Do not decide at all:** Purview data governance as a new anchor; a second semantic layer; a third-party capacity-cost tool for a single capacity.

### What this does to the existing ADRs

- **ADR [0008](../adr/0008-schema-is-state-based.md) is reinforced, not challenged.** The best evidence against dbt is not preference: the hosted dbt products do not document Fabric support, the managed runtime pins an older adapter than the adapter repository, and the adapter itself documents that integrity comes from tests rather than keys.
- **ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) is unaffected but gains a footnote:** the dbt job is `fabric-cicd`-deployable and has **no Terraform resource**, so a team that standardises on Terraform for items cannot own it there.
- **ADR [0009](../adr/0009-observability-is-event-sourced.md) gains a cheaper first step:** the same Eventhouse can hold `ItemJobEventLogs` and the quality-assertion results, which is the retention fix this note identifies.

## What this does not establish

- **No pricing.** Nothing here is costed. The only pricing *shapes* used are structural: Fabric capacity (CU, smoothing, overage, pause), dbt platform subscription tiers, Fivetran's monthly-active-rows usage meter, and per-seat licences. No rate, discount or SKU recommendation is made or implied.
- **No source inventory.** The connector verdict is conditional on the estate's sources being SQL Server, Azure SQL Database and ADF-adjacent stores. How many sources exist, which SaaS APIs, whether any are mainframe or SAP, and what volumes move are unknown; a single unlisted CDC source would change §3.
- **No volume, concurrency or retention figures.** No table sizes, query rates, concurrent users, RPO/RTO or retention requirements were supplied. Direct Lake guardrails are quoted per SKU, not sized against a workload; the dbt thread guidance is the adapter's recommendation, not a measured result.
- **Vendor pages not verified.** Monte Carlo's docs were unreachable (transport error) and Sifflet's, Collibra's, Atlan's, Alation's, AtScale's, Cube's, Census's and Soda's documentation were not read for this note. Claims about them are limited to category behaviour, and are flagged where made. Matillion's documentation root returned 404; only its product page was read.
- **Whether Fabric supports specific external BI connectors.** Tableau's, Sigma's and Looker's own Fabric connectors were not checked. §4.2 argues from the platform side (Direct Lake does not travel), not from each tool's connector list.
- **Whether Airbyte can write to OneLake or a Fabric Warehouse.** Its platform page was read; its destination list was not.
- **Whether Copy job alters an existing destination table when a source column is added.** The pages read describe automatic table creation and column mapping, not `ALTER`. Schema drift on an existing table is the one native gap that could justify a connector vendor, and it is untested here.
- **Whose identity runs a Fabric dbt job, and whether a GitHub-connected project is also versioned through Fabric Git.** Both are undocumented on the pages read, and both affect RLS and audit.
- **Whether `dbt-fabric` has a dbt v2 adapter.** The adapter repository documents 1.12-era support; the v2 adapter list has no Fabric entry. Treat "dbt v2 on Fabric" as unsupported until a vendor page says otherwise.
- **Whether the Fabric dbt job's lineage view is the dbt DAG or the workspace item graph.** The overview claims "lineage … within the same workspace"; no page read distinguishes the two.
- **Whether Delta Sharing in Fabric is GA, and under what recipient model.** Only the existence of a `share` API group with definition operations was established.

## Sources

All pages below were read on **2026-11-24**; the date column is the page's own `ms.date` / "last updated" where published. Fabric ships monthly, so a page older than a few months is a question, not an answer. Vendor sources are each vendor's own documentation for its own product; no vendor's claim about a competitor is used as evidence.

| Ref | Source | Used for | Dated |
| --- | --- | --- | --- |
| `fabric-dbt` | [dbt Job in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/data-factory/dbt-job-overview) | GA status; managed runtime V1.0; adapter/version matrix; permissions; no build caching; 5,000-file limit; `dbt_project.yml` at repo root; GitHub PAT only; lineage claim | ms.date 2026-08-19, upd. 2026-11-05 |
| `fabric-dbt-config` | [Configure dbt jobs in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/data-factory/dbt-job-configure) | per-adapter authentication; threads/fail-fast/full-refresh; selectors; project layout | ms.date 2025-06-11, upd. 2026-09-29 |
| `dbt-fabric` | [microsoft/dbt-fabric README](https://github.com/microsoft/dbt-fabric) | `mssql-python`; `NOT ENFORCED` keys; `NOT NULL` rebuild; catalog-lock guidance; package compatibility and caveats; 1.12 series vs Core 1.12; `run-operation --sql` defect | read 2026-11-24 |
| `dbt-tests` | [Add data tests to your DAG](https://docs.getdbt.com/docs/build/data-tests) | four built-in tests; singular tests; `data_tests` rename; severity; `store_failures`; `dbt_test__audit` | last updated 2026-09-16 |
| `dbt-docs` | [About documentation](https://docs.getdbt.com/docs/build/documentation) | descriptions, docs blocks, generated docs, dbt Catalog vs dbt Docs, column-level lineage | last updated 2026-10-01 |
| `dbt-platform` | [The dbt platform features](https://docs.getdbt.com/docs/platform/about-platform/dbt-platform-features) | hosted product surface: scheduling, CI, hosted docs, Semantic Layer, Discovery API, Catalog | last updated 2026-11-10 |
| `dbt-arch` | [dbt Architecture](https://docs.getdbt.com/docs/platform/about-platform/architecture) | PostgreSQL backend, S3-compatible artefact storage, own RBAC/SSO — the second metadata plane | last updated 2026-11-18 |
| `dbt-sl` | [dbt Semantic Layer](https://docs.getdbt.com/docs/use-dbt-semantic-layer/dbt-sl) | Starter/Enterprise requirement; MetricFlow; metric definitions in the modelling layer | last updated 2026-09-29 |
| `dbt-platforms` | [Supported data platforms](https://docs.getdbt.com/docs/supported-data-platforms) | dbt v2 adapter lifecycle: Snowflake, BigQuery, Databricks, Redshift, Spark, DuckDB, ClickHouse — no Fabric | last updated 2026-11-14 |
| `dbt-adapters` | [Available adapters](https://docs.getdbt.com/docs/community-adapters) | first-party vs community-maintained; "set up in the dbt platform" pages exist for five platforms only | last updated 2026-11-16 |
| `df-overview` | [What is Data Factory](https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-overview) | "more than 170 data sources"; Copy job / Copy activity / mirroring / Gen2 / dbt job / Airflow; SLA | ms.date 2026-08-05 |
| `copy-job` | [What is Copy job](https://learn.microsoft.com/en-us/fabric/data-factory/what-is-copy-job) | full/incremental/CDC modes; watermark types; append/overwrite/merge/SCD2; auto table creation; audit columns; CDF on destination; gateways; CI/CD | ms.date 2026-09-17, upd. 2026-11-09 |
| `copy-job-conn` | [Connectors for Copy job](https://learn.microsoft.com/en-us/fabric/data-factory/copy-job-connectors) | source/destination matrix; the CDC source/destination table; SCD2 preview caveats; automatic table creation list | ms.date 2026-11-09 |
| `conn-overview` | [Connector overview](https://learn.microsoft.com/en-us/fabric/data-factory/connector-overview) | the three surfaces per connector (Gen2 / pipeline / Copy job); TLS 1.3 list | ms.date 2026-10-30, upd. 2026-11-18 |
| `move-guide` | [Comparing Copy job, mirroring, Copy activity and Eventstreams](https://learn.microsoft.com/en-us/fabric/data-factory/decision-guide-data-movement) | the documented recommendation per medallion layer; "free of cost" for mirroring; streaming destinations | ms.date 2026-04-13 |
| `gen2` | [Differences between Dataflow Gen1 and Gen2](https://learn.microsoft.com/en-us/fabric/data-factory/dataflows-gen2-overview) | "300+ transformations"; output destination list; CI/CD default since April 2026 | ms.date 2026-08-13 |
| `direct-lake` | [Direct Lake overview](https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-overview) | framing vs import refresh; automatic updates; per-SKU guardrail table; licensing; no-gateway and same-region limits; RLS behaviour; V2 embed token | ms.date 2026-09-02, upd. 2026-11-02 |
| `catalog` | [OneLake catalog overview](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-overview) | Explore / Govern / Secure; Governance Insights and Recommended Actions; admin surfaces moving into Govern | ms.date 2026-08-26 |
| `eventstream` | [Fabric Eventstreams overview](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/overview) | Kafka endpoint; Event Hubs backing; source and destination lists; 1 MB / 90-day / at-least-once; F4 minimum | ms.date 2026-09-02, upd. 2026-11-17 |
| `airflow` | [Create an Apache Airflow Job project](https://learn.microsoft.com/en-us/fabric/data-factory/create-apache-airflow-jobs) | Airflow job item, DAG authoring, Airflow UI | ms.date 2026-03-23 |
| `ml-exp` | [Machine learning experiment](https://learn.microsoft.com/en-us/fabric/data-science/machine-learning-experiment) | MLflow experiments and runs; run comparison; save as model; MLflow 3 Logged Models and Traces | ms.date 2026-05-15, upd. 2026-09-02 |
| `fivetran-dest` | [Fivetran Destinations](https://fivetran.com/docs/destinations) | documented destination list — no Microsoft Fabric/OneLake; schema migrations; type inference | read 2026-11-24 |
| `fivetran-feat` | [Fivetran Features](https://fivetran.com/docs/core-concepts/features) | delete capture; history mode; schema migration types; re-sync; priority-first sync | read 2026-11-24 |
| `fivetran-hybrid` | [Fivetran Hybrid Deployment](https://fivetran.com/docs/core-concepts/deployment-models/hybrid-deployment) | agent model; outbound mTLS; supported destinations subset — no Fabric | read 2026-11-24 |
| `fivetran-sync` | [Fivetran Syncs](https://fivetran.com/docs/core-concepts/syncoverview) | sync types; 1-minute to 24-hour frequencies; retry and auto-pause behaviour | read 2026-11-24 |
| `airbyte` | [Airbyte Platform](https://docs.airbyte.com/platform) | self-managed/Cloud/hybrid; "over 600 pre-built connectors"; Connector Builder; Terraform provider; PyAirbyte | read 2026-11-24 |
| `qlik-fabric` | [Using Microsoft Fabric as a target](https://help.qlik.com/en-US/replicate/May2026/Content/Replicate/Main/MicrosoftFabricDW/fabric-landing.htm) and [Limitations](https://help.qlik.com/en-US/replicate/May2026/Content/Replicate/Main/MicrosoftFabricDW/fabric-limitations.htm) | landing-zone (open mirroring) target; PK requirement; DDL subset; no TRUNCATE; transactional apply; no processing confirmation | last updated 2026-11-19 |
| `matillion` | [Matillion Connect](https://www.matillion.com/data-productivity-cloud/connect) | "over 250 pre-built connectors"; custom/Flex connectors (product page only; docs root 404 on 2026-11-24) | read 2026-11-24 |
| `gx` | [GX Core overview](https://docs.greatexpectations.io/docs/core/introduction/gx_overview) | Data Context, Data Source, Expectation Suite, Validation Definition, Checkpoint, Actions, Data Docs | v1.25.0, read 2026-11-24 |
| `datahub` | [What is DataHub?](https://docs.datahub.com/docs/features) | catalog/lineage/governance scope; Cloud anomaly detection and assertions; OSS self-hosting | v1.9.0, read 2026-11-24 |
| `datafold` | [Datafold documentation](https://docs.datafold.com/) | current positioning as a migration service; "Datafold Classic" distinction | read 2026-11-24 |
| `hightouch` | [What is Hightouch?](https://docs.hightouch.com/) | positioning as a marketing platform on the warehouse; audiences, journeys, delivery, syncs | read 2026-11-24 |
| `purview-retire` | Purview retirement banner, cited in [`data-stack-…md`](data-stack-which-layers-exist-and-what-replaces-each.md) from [aka.ms/DG-Deprecation](https://aka.ms/DG-Deprecation) | retirement of Unified Catalog / classic data governance; consolidation into Fabric; maintenance to 2027-11-12 | read 2026-11-24 |

Local notes relied on rather than re-derived: [`schema-and-ddl-management.md`](schema-and-ddl-management.md) (DacFx/`DeployReport`, transactional DDL subset, `CREATE USER` unsupported), [`mirroring-which-sources-latency-and-cost.md`](mirroring-which-sources-latency-and-cost.md) (GA/preview source list, reseed behaviour), [`gateway-and-connectivity.md`](gateway-and-connectivity.md) (gateway types and their operational cost), [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) (which items deploy; ML model/experiment manual-only; dbt job has no Terraform resource), [`purview-and-lineage.md`](purview-and-lineage.md) (lineage bounds, endorsement, catalog automation surface), [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) (Monitor hub, workspace monitoring, retention), [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md) (CU, overage, surge protection).

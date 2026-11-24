# What other technologies make up a modern data stack, and which of them outlive the platform choice?

- **Status:** answered
- **Checked:** 2026-11-24
- **Blocks:** nothing yet — commissioned by issue #38 as the market map behind ADR [0011](../adr/0011-fabric-now-databricks-at-a-gate.md). The gate review reads it; no decision depends on it.
- **Sibling notes:** [`data-stack-which-layers-exist-and-what-replaces-each.md`](data-stack-which-layers-exist-and-what-replaces-each.md) for the Fabric-versus-Databricks comparison and the ten capability layers — this note does **not** repeat that comparison; [`tooling-which-specialists-earn-their-place-beside-fabric.md`](tooling-which-specialists-earn-their-place-beside-fabric.md) for the team's per-tool verdicts — this note links to those verdicts, it does not re-derive them.

## Short answer

The market has two shapes, not one. **Composable** assembles a different product at each layer over shared storage and open formats; **suite** sells one vendor's answer at several layers under one contract. The difference is where the integration cost sits, not what is possible: composable pushes it into connectors, contracts and a catalog you operate; suite pushes it into one vendor's roadmap and one migration boundary.

Only the artefacts in §3 are portable across either shape: Parquet files, the Delta and Iceberg table specifications, SQL, the Kafka wire protocol, OpenLineage, and the Iceberg REST catalog API. Products are substitutable; those specifications are what an exit path is actually made of.

For this estate, **ADR 0011 already answers storage, warehouse, orchestration, catalog and BI**. What remains genuinely independent of it is narrow: the table format you commit data to, the schema/transformation method, data-quality assertions, and the layers the ADR gated rather than decided — streaming and ML, plus the ones nobody has asked for yet.

## Detail

### 0. The two architectures, stated plainly

| | Composable / best-of-breed | Suite |
| --- | --- | --- |
| **Shape** | One product per layer: e.g. Fivetran → Snowflake → dbt → Looker, orchestrated by Airflow, described by a catalog | One vendor spans several layers: Fabric (OneLake, Warehouse, Data Factory, Power BI, its catalog), Databricks (Delta, Spark, Unity Catalog, SQL warehouses), Snowflake (warehouse, Marketplace, its own SQL surface) |
| **What it optimises for** | Substituting any one layer without re-platforming the rest; each layer's own release cadence | One identity, one bill, one support contract, one place where "what ran and who can see it" is answered |
| **What it costs** | Integration you own: every boundary is a contract, every vendor is a permission model and a metadata copy | Coupling: the layers move together, and leaving means leaving all of them |
| **Failure mode** | A layer is upgraded or acquired and the seam breaks; the catalog is only as current as its last sync | A gap in one layer is not fixable by buying elsewhere without creating a second plane |

Neither shape is a capability claim. Fabric, Databricks and Snowflake all sell suites; the composable stack is assembled from vendors who sell a single layer. The choice is which integration cost the organisation is willing to staff.

Two dated observations from the pages read, because they show the boundary moving:

- **Fivetran's own product page describes "Fivetran + dbt Labs"** as one offering that "moves, manages, transforms, and activates all data" ([fivetran]), while dbt's documentation remains a separate product surface ([dbt]). Connector and transformation vendors are consolidating, so "one product per layer" is a shape, not a stable vendor list.
- **Fivetran's documentation site now serves what was Census** at the Census documentation URL, under the name **Fivetran Activations** ([census]). The reverse-ETL layer's Census product is now a feature of a connector vendor.

### 1. One table across the layers

Each technology name carries the reference for the page read. The purpose sentence in each row is a synthesis of those pages, not a separate claim; the "depends on" column names the structural dependency read off those pages, not a comparison.

| Layer | Purpose in one sentence | Representative technologies | What the choice actually depends on |
| --- | --- | --- | --- |
| **Connectors / CDC** | Move data from operational sources into a landing zone, in bulk or by reading the source's change log. | Fivetran [fivetran]; Airbyte [airbyte]; Debezium [debezium]; Kafka Connect [kafka-connect]; Qlik Replicate [qlik-replicate]; Matillion [matillion] | Which sources must be reached and whether each exposes a transaction log; where the data must land; whether you run the connector runtime or buy it. |
| **Object storage** | Hold the files that tables are built from, independent of any query engine. | Amazon S3 [s3]; ADLS Gen2 [adls]; Google Cloud Storage [gcs]; MinIO [minio] | Which cloud is already billed; whether the engine reads the store natively; whether an S3-compatible API is enough. |
| **Open table formats** | Add a table abstraction — schema, snapshots, transactions — over files in object storage. | Delta Lake [delta]; Apache Iceberg [iceberg]; Apache Hudi [hudi] | Which engines must read **and write**; whether the format, not the engine, is the contract you keep when the engine changes. |
| **Catalogs / metastores** | Name tables and answer "where is this table and who may read it" for one or more engines. | Unity Catalog [unity-catalog]; AWS Glue Data Catalog [glue-catalog]; Apache Polaris [polaris]; Project Nessie [nessie]; Hive Metastore [hms] | How many engines must share one namespace; whether catalog operations need branching or versioning; where the catalog's own identity model lives. |
| **Warehouses and query engines** | Execute SQL over stored data. | Snowflake [snowflake]; BigQuery [bigquery]; Redshift [redshift]; Synapse [synapse]; ClickHouse [clickhouse]; DuckDB [duckdb]; Trino [trino]; Athena [athena] | Workload shape and concurrency; where the data already sits; which SQL dialect the team writes; whether compute is provisioned, per-query or in-process. |
| **Transformation** | Turn landed data into modelled tables, with tests and dependency order expressed in code. | dbt [dbt]; SQLMesh [sqlmesh]; Dataform [dataform] | Whether you want a state-based diff of schema or a dependency graph of models; which warehouse adapter exists; where the code executes. |
| **Orchestration** | Schedule and sequence work across systems, with retries, dependencies and visibility. | Apache Airflow [airflow]; Dagster [dagster]; Prefect [prefect]; Temporal [temporal]; Argo Workflows [argo] | Whether the unit being scheduled is a task, an asset, a container or a durable workflow; where the scheduler runs; what the platform already provides. |
| **BI and semantic layers** | Present governed metrics to people, either by querying a warehouse (BI) or by defining metrics once for many consumers (semantic layer). | Tableau [tableau]; Looker [looker]; Sigma [sigma]; Metabase [metabase]; Apache Superset [superset]; Cube [cube]; AtScale [atscale]; dbt Semantic Layer [dbt-sl] | Whether metric definitions live in the BI tool or the warehouse; who authors content; whether the tool must be embedded in another product. |
| **Catalog / lineage / governance** | Record what data exists, where it came from and who owns it, across systems. | DataHub [datahub]; OpenMetadata [openmetadata]; Atlan [atlan]; Collibra [collibra]; Alation [alation]; Amundsen [amundsen]; OpenLineage [openlineage]; Marquez [marquez] | How many sources must be scanned; whether lineage is emitted by the tools or inferred afterwards; whether governance is a compliance function or an engineering one. |
| **Data quality** | Assert what correct data looks like and fail a run when the assertion breaks. | Great Expectations [gx]; Soda [soda]; dbt tests [dbt-tests]; Elementary [elementary]; Deequ [deequ] | Where the assertions execute (warehouse SQL, Python, Spark) and whether tests ship with the transformation tool you already chose. |
| **Observability** | Detect data that is late, wrong or anomalous without a human writing every check. | Monte Carlo [montecarlo]; Datafold [datafold]; Sifflet [sifflet]; Metaplane [metaplane] | Whether the estate wants rule-based checks or monitoring over metrics; what the tool can see of the pipeline that produced the data. |
| **Streaming** | Carry events continuously between producers and consumers, with ordering and replay. | Apache Kafka [kafka]; Confluent Platform [confluent]; Redpanda [redpanda]; Apache Flink [flink]; Kinesis Data Streams [kinesis]; Event Hubs [eventhubs]; Apache Pulsar [pulsar]; Spark Structured Streaming [spark-ss] | Throughput and latency requirements; whether clients must speak the Kafka protocol; whether the broker is managed or self-run. |
| **Reverse ETL** | Push modelled data from the warehouse back into operational tools. | Hightouch [hightouch]; Census / Fivetran Activations [census]; Segment [segment] | Whether the destination is a business SaaS tool or an event pipeline; who owns the customer record; whether the sync is a platform concern at all. |
| **ML and feature stores** | Train, track and serve models, and compute features consistently for training and inference. | MLflow [mlflow]; Feast [feast]; Tecton [tecton]; SageMaker AI [sagemaker]; Vertex AI [vertex] | Whether ML is a product with an owner or an experiment; whether online serving is needed; which cloud and identity the training data already uses. |
| **Notebooks / dev surfaces** | An interactive place to write SQL or Python against the platform and share the result. | Jupyter [jupyter]; Hex [hex]; Deepnote [deepnote] | Who the audience is — engineer, analyst, data scientist; whether notebooks must be scheduled, versioned and promoted. |
| **Data sharing** | Give another organisation or account access to data without copying it. | Delta Sharing [delta-sharing]; Snowflake Marketplace [snowflake-marketplace]; Iceberg REST catalog [iceberg-rest] | Whether both sides speak the same format or catalog protocol; whether the sharing is commercial (a marketplace listing) or bilateral. |

**Rows where the only readable page was a product page, a documentation landing page without a purpose statement, or repository metadata:** Matillion, Qlik Replicate, Tableau, AtScale, Collibra, Alation, Elementary, Sifflet, Monte Carlo, and Amundsen. Those cells describe what the vendor's own page says on 2026-11-24 and nothing more.

Page-level states recorded on the read date, because several changed under the note:

| Product | State observed 2026-11-24 |
| --- | --- |
| **Amundsen** | The `amundsen-io/amundsen` repository reports `"archived": true`, last push 2026-09-10 ([amundsen]); `amundsen.io` served unrelated content, not the project's documentation. Describe Amundsen from its repository metadata, or not at all. |
| **Census** | The documentation URL now serves **Fivetran Activations**, which describes "managed, automated reverse ETL pipelines" ([census]). |
| **Tecton** | `tecton.ai/product` resolved to the **Databricks Data + AI Platform** page on this date; the Tecton documentation still serves a feature-store introduction, version 1.2 ([tecton]). Only the documentation is cited here. |
| **Vertex AI** | The documentation page under the Vertex AI URL is titled **Gemini Enterprise Agent Platform** and describes building, training and managing models there ([vertex]). |
| **Datafold** | The documentation now opens with **migration delivery** — "migrate and modernize your data stack" as pull requests — and refers to the older product as **Datafold Classic** ([datafold]). The data-diff framing is not what the page says today. |
| **Monte Carlo** | The product page describes **data observability** and data-quality monitoring ([montecarlo]); the documentation index fronts agent monitoring. |
| **Matillion** | The product page is **Maia by Matillion**, an agentic data-automation platform ([matillion]); the Matillion ETL documentation tree still exists but the paths tried returned 404. |
| **MinIO** | The documentation is branded **MinIO AIStor**, "natively supporting the S3 API for objects, Iceberg for tables, and SFTP for files" ([minio]). |

### 2. The layers, read as a chain

The composable reference stack is usually drawn as five boxes and two satellites:

```
sources → connector/CDC → object storage + table format → warehouse/engine → transformation → BI
                                    │                                        │
                                 catalog                                  orchestration
```

Read left to right, each arrow is a contract someone has to own:

| Boundary | What crosses it | Who specifies the crossing |
| --- | --- | --- |
| Source → connector | A log position or a query; a schema | The source database's own replication interface, or the connector's query dialect |
| Connector → storage | Files plus a commit | The connector's writer; the table format for Delta or Iceberg ([delta], [iceberg]) |
| Storage → engine | Table metadata and data file reads | The table format's specification, not the engine ([delta-protocol], [iceberg]) |
| Engine → transformation | A SQL dialect and a set of relations | The engine's SQL surface; the transformation tool's adapter |
| Transformation → BI | Modelled tables or a semantic model | The BI tool's connection mode, or the semantic layer's own definition ([dbt-sl], [cube]) |
| Anything → catalog | Metadata, lineage, ownership | The catalog's ingestion path — a scan, a push, or an emitted event ([openlineage]) |

The suite collapses these arrows to one vendor's internal interfaces. That is the whole trade: fewer contracts to write, one contract you cannot renegotiate.

### 3. Durable versus substitutable

"Durable" here means **specified independently of any one vendor's product** — not permanent, and not bug-free. A specification is what lets a second engine read the same bytes without asking the first vendor.

| Artefact | Specified by | Role in a stack | What survives an exit |
| --- | --- | --- | --- |
| **Parquet file format** | The `apache/parquet-format` specification; "an open source, column-oriented data file format" ([parquet-spec]) | The bytes tables are made of | The files themselves. Any engine with a Parquet reader can read them. |
| **Delta table protocol** | The Delta transaction-log protocol, which defines serialisable ACID writes and snapshot isolation over those files ([delta-protocol]) | The table abstraction over Parquet | The table, if the next engine implements the protocol. A reader alone gets bytes, not a table. |
| **Iceberg table specification** | The Iceberg spec, "designed to manage a large, slow-changing collection of files … as a table" ([iceberg]) | The alternative table abstraction | The table, for engines implementing Iceberg. |
| **Iceberg REST catalog API** | The Iceberg REST catalog specification, "a common API … for interacting with any Iceberg catalog", analogous to Hive's Thrift protocol for HMS ([iceberg-rest]) | The boundary between a table and the catalog that names it | Catalog portability: a client can point at a different catalog implementation without a new client library. |
| **SQL** | ISO/IEC 9075, most recently SQL:2023, as named in PostgreSQL's conformance appendix ([sql-standard]) | The query language of every warehouse row in §1 | The queries, minus vendor extensions. Conformance is graded — SQL-92 defined Entry, Intermediate and Full — and PostgreSQL's appendix exists to record which features it does not support. |
| **Kafka wire protocol** | The Kafka protocol document: a binary protocol over TCP, request/response pairs ([kafka-protocol]) | The boundary between producers, brokers and consumers | Clients and connectors, against any broker that implements the protocol — Redpanda states Kafka API compatibility ([redpanda]). |
| **OpenLineage** | An "open framework for data lineage collection and analysis" with a generic model of dataset, job and run ([openlineage]); object model at [openlineage-spec] | The lineage event format emitted by jobs | Lineage history that a later catalog can ingest, if the emitters keep emitting. |

Three consequences for an exit path:

1. **The format is the exit, the catalog is not.** Delta or Iceberg metadata is readable by another engine *that implements the corresponding protocol*; the catalog that named the table, its grants and its lineages are vendor objects. Fabric's metadata virtualisation is the concrete case already recorded in this repo: OneLake writes Delta and exposes Iceberg metadata, in both directions, for Parquet-backed tables ([`data-stack-…`](data-stack-which-layers-exist-and-what-replaces-each.md) §2).
2. **Parquet alone is not a table.** A directory of Parquet files has no snapshot, no schema evolution and no transaction log. Leaving a platform with only the files is a data copy plus a re-registration, not a read.
3. **A protocol is only durable where a second implementation exists.** Each of the artefacts above has at least one: Redpanda and Event Hubs both implement Kafka's API ([redpanda], [eventhubs]); Polaris and Nessie implement the Iceberg REST API ([polaris], [nessie]); Marquez is the OpenLineage reference implementation ([marquez]). That is the test, not the specification's existence.

### 4. What this means for us

ADR [0011](../adr/0011-fabric-now-databricks-at-a-gate.md) decides Fabric for "the warehouse, orchestration, storage, catalog and BI", scopes the first phase to Warehouse, Data Factory pipelines, OneLake/Delta, `fabric-cicd` and Terraform-for-containers, and defers Databricks on named triggers. This note does not re-argue any of that. It only says which layers that decision covers and which it does not.

| Layer | Answered by the Fabric decision? | Why |
| --- | --- | --- |
| **Object storage** | **Yes** — OneLake. | The storage layer is part of the platform decision; ADLS Gen2 stays optional behind shortcuts. |
| **Warehouses and query engines** | **Yes** — Fabric Warehouse first. | ADR 0011 chooses the T-SQL surface and accepts its documented reductions. |
| **Orchestration** | **Yes** — Data Factory pipelines. | ADF is refactored, not replaced by a third-party scheduler. |
| **Catalog / governance** | **Yes** — Fabric's catalog. | Purview data governance is retiring into Fabric ([`data-stack-…`](data-stack-which-layers-exist-and-what-replaces-each.md) §7); no external catalog is bought. |
| **BI and semantic layer** | **Yes** — Power BI and its semantic model. | ADR 0011 treats native BI as decisive and rules out a second semantic layer. |
| **Connectors / CDC (current sources)** | **Yes, for the sources named** — mirroring or Copy job. | The ingestion route from the application database is recorded separately; a new source with no native path reopens this row only. |
| **Open table formats** | **Partly** — Delta is chosen; Iceberg is a read path. | The commitment "data lands in Delta in OneLake" is what makes the rest of this section portable. The format outlives the decision even though the decision names it. |
| **Transformation** | **No** — ADR [0008](../adr/0008-schema-is-state-based.md) answers it, not 0011. | `.sqlproj` + SqlPackage versus dbt is a schema-deployment decision with its own ADR and its own note. |
| **Data quality** | **No** — answered by convention, not by a product. | Validation is T-SQL assertions until dbt tests exist; no data-quality product is in scope. |
| **Observability** | **No** — Monitor hub and Capacity Metrics are Fabric-specific. | ADR [0009](../adr/0009-observability-is-event-sourced.md) builds inside Fabric; a third-party observability product would be a second alerting plane. |
| **Streaming** | **No** — gated, not decided. | Eventstream and Eventhouse exist inside Fabric; a funded streaming use case is one of ADR 0011's triggers. |
| **ML and feature stores** | **No** — gated, not decided. | Fabric Data Science items exist; a funded ML product is the other ML-side trigger. |
| **Reverse ETL** | **No** — not in scope. | No stated requirement; the named products now present as a marketing platform ([hightouch]) and as a feature of a connector vendor ([census]). |
| **Notebooks / dev surfaces** | **No, and low stakes.** | Fabric notebooks satisfy the requirement; Hex and Deepnote describe themselves as analytics workspaces, not as platform decisions. |
| **Data sharing** | **No** — one option is already inside Fabric. | OneLake shortcuts and Delta Sharing are available; a marketplace listing would be a commercial decision. |
| **Multi-engine catalog access** | **No — and not an ADR 0011 trigger.** | Nothing in the ADR requires a second engine to share the catalog. It becomes live only if a second engine must read the same tables under the same grants. |
| **Code-first orchestration** | **No — and not an ADR 0011 trigger.** | Fabric offers an Apache Airflow job item ([`data-stack-…`](data-stack-which-layers-exist-and-what-replaces-each.md) §1); the ADR scopes orchestration to Data Factory pipelines. A Python DAG someone already owns is the condition that would change this row. |

ADR 0011's trigger table has **five** rows, and they map onto this map rather than onto the whole market:

| ADR 0011 trigger | Layers it would pull in |
| --- | --- |
| A funded ML or streaming use case | Streaming brokers and processors; ML tracking, feature store, serving |
| Power BI replaced or decommissioned | BI and semantic layer; the native-BI asymmetry that decided the ADR |
| Fabric capacity cannot serve the workload at agreed cost | Warehouses and query engines; the cost model |
| Fabric's CI causes a recurring release failure | Deployment surface — not a row in §1, but the layer ADR 0011 names as Fabric's weakest |
| Data volume or concurrency outgrows the warehouse | Warehouses and query engines; the table format's scan behaviour |

**Multi-engine catalog access** and **code-first orchestration** are not among those triggers. They are layers this note shows to be independent of the decision, so if either becomes a requirement it is new evidence, not a re-run of the same gate.

## What this settles

- **The market has two architectures, and the difference is where integration cost sits.** Composable: a contract at every layer boundary. Suite: one contract you cannot renegotiate.
- **A layer map with the substitution point named.** Sixteen layers, 3–8 representative technologies each, and the structural dependency that decides each row — sources reachable, log available, engines that must write, namespace shared, dialect written, adapter exists, scheduler location, definition location, scan or emit, execution engine, checks or monitoring, protocol compatibility, destination type, product-or-experiment, audience, format on both sides.
- **The durable artefacts are specifications, not products.** Parquet, the Delta protocol, the Iceberg table spec, the Iceberg REST catalog API, SQL (ISO/IEC 9075), the Kafka wire protocol, OpenLineage. Each has at least one implementation beyond the product that introduced it — the test applied in §3.
- **The exit path is the table format plus the files, not the catalog.** Leaving with Parquet files only is a copy and a re-registration; leaving with Delta or Iceberg metadata is a read, if the next engine implements the spec.
- **ADR 0011 answers storage, warehouse, orchestration, catalog, BI, and ingestion for the named sources.** It does not answer transformation (ADR 0008 does), data quality, streaming, ML, reverse ETL, or a second semantic layer.
- **Two layers people assume are triggers are not in ADR 0011.** Multi-engine catalog access and code-first orchestration would be new requirements, not a re-evaluation of the recorded decision.
- **Dated project states are recorded** so a later reader does not cite them from memory: Amundsen archived and its domain no longer serving the project, Census documentation now Fivetran Activations, Tecton's product URL resolving to Databricks, Vertex AI's page retitled Gemini Enterprise Agent Platform, Datafold's documentation now describing migration delivery, Monte Carlo and Matillion both repositioned around agents.

## What this does not establish

- **Nothing here is evaluated for fit.** No product in §1 was tested against this estate's volume, concurrency, latency, residency, identity model or budget. The "depends on" column names structural dependencies from each vendor's own page, not a judgement about which product suits six people.
- **Several vendors' documentation was not read.** For Matillion, Qlik Replicate, Tableau, AtScale, Collibra, Alation, Elementary, Sifflet, Monte Carlo and Amundsen, only a product page, a landing page without a purpose statement, or repository metadata could be read; those rows say no more than the page said. `docs.atscale.com` returned HTTP 503, `help.qlik.com` versioned Replicate paths returned 404, Tableau's product site returned HTTP 403, and `amundsen.io` no longer serves the project.
- **No prices, rankings, performance claims or maturity claims.** Nothing here says one product is faster, cheaper, more scalable or more mature than another. Where a vendor page used such language, it was not carried into the note.
- **Release states change.** Every row is a snapshot of 2026-11-24. Products in this list ship weekly and rename themselves; several of the weakest rows had already changed positioning or status before this note was written.
- **Inclusion is not endorsement.** Listing a product means its own documentation describes that layer's function, not that it belongs in this estate or in any other.
- **Compatibility with Fabric and OneLake was not tested.** Nothing here establishes that any listed engine reads or writes OneLake data, that any catalog can govern it, or that any connector can land in it. Fabric's own Delta/Iceberg behaviour is cited from the sibling note, not re-tested.
- **The layering itself is a convention.** Products cross layers — Fivetran sells transformation, Snowflake sells a marketplace, dbt sells a semantic layer, Databricks sells storage, catalog and ML. A row assignment is a reading aid, not a claim about product boundaries.
- **Licensing, support terms and open-source governance were not assessed**, including whether "open source" in a vendor's description corresponds to a licence this estate can accept.
- **This note does not re-open ADR 0011.** It records the market around the decision, and the decision stands on its own evidence.

## Sources

All pages read on **2026-11-24**. Where a page states a version or a last-updated date, it is recorded; otherwise the read date is the only date.

| Ref | Page | Layer | Version or date on page |
| --- | --- | --- | --- |
| [fivetran] | Fivetran documentation, getting started; Fivetran product overview | Connectors | read 2026-11-24 |
| [airbyte] | Airbyte Docs | Connectors | read 2026-11-24 |
| [debezium] | Debezium Reference Documentation | Connectors | read 2026-11-24 |
| [kafka-connect] | Apache Kafka, Kafka Connect overview (`docs/kafka-connect/overview.md`) | Connectors | Kafka docs 4.4.x |
| [qlik-replicate] | Qlik Replicate product page | Connectors | read 2026-11-24 |
| [matillion] | Maia by Matillion, product page | Connectors | read 2026-11-24 |
| [s3] | What is Amazon S3? | Storage | read 2026-11-24 |
| [adls] | Introduction to Azure Data Lake Storage | Storage | read 2026-11-24 |
| [gcs] | Cloud Storage overview | Storage | read 2026-11-24 |
| [minio] | MinIO AIStor Documentation | Storage | read 2026-11-24 |
| [delta] | Welcome to the Delta Lake documentation | Table format | read 2026-11-24 |
| [iceberg] | Apache Iceberg specification | Table format | Iceberg 1.10.2 docs tree |
| [hudi] | Apache Hudi overview | Table format | Hudi 1.2.1 |
| [unity-catalog] | What is Unity Catalog? | Catalog | last updated 2026-09-11 |
| [glue-catalog] | Data discovery and cataloging in AWS Glue | Catalog | read 2026-11-24 |
| [polaris] | Apache Polaris (site and README) | Catalog | Polaris 1.9.0 docs tree |
| [nessie] | About Nessie | Catalog | read 2026-11-24 |
| [hms] | AdminManual Metastore Administration (Hive wiki) | Catalog | Hive 2.x page; points to 3.0 page |
| [snowflake] | Snowflake key concepts and architecture | Warehouse | read 2026-11-24 |
| [bigquery] | BigQuery overview | Warehouse | read 2026-11-24 |
| [redshift] | What is Amazon Redshift? | Warehouse | read 2026-11-24 |
| [synapse] | What is Azure Synapse Analytics? | Warehouse | read 2026-11-24 |
| [clickhouse] | What is ClickHouse? | Warehouse | read 2026-11-24 |
| [duckdb] | DuckDB documentation and site | Warehouse | DuckDB 2.0 docs |
| [trino] | Trino overview | Warehouse | Trino 484 |
| [athena] | What is Amazon Athena? | Warehouse | read 2026-11-24 |
| [dbt] | What is dbt? | Transformation | read 2026-11-24 |
| [sqlmesh] | SQLMesh documentation | Transformation | read 2026-11-24 |
| [dataform] | Dataform overview | Transformation | read 2026-11-24 |
| [airflow] | What is Airflow? | Orchestration | Airflow 3.4.0 |
| [dagster] | Dagster documentation overview | Orchestration | read 2026-11-24 |
| [prefect] | Prefect documentation introduction | Orchestration | read 2026-11-24 |
| [temporal] | Temporal Platform documentation | Orchestration | read 2026-11-24 |
| [argo] | Argo Workflows documentation | Orchestration | read 2026-11-24 |
| [tableau] | Tableau Desktop and Web Authoring Help; Get Started tutorial | BI | read 2026-11-24 |
| [looker] | Looker documentation introduction | BI | read 2026-11-24 |
| [sigma] | About Sigma | BI | read 2026-11-24 |
| [metabase] | Metabase documentation | BI | version 65 |
| [superset] | Superset introduction (user docs) | BI | read 2026-11-24 |
| [cube] | Cube documentation introduction | Semantic layer | read 2026-11-24 |
| [atscale] | AtScale platform overview | Semantic layer | read 2026-11-24 |
| [dbt-sl] | dbt semantic models | Semantic layer | read 2026-11-24 |
| [datahub] | What is DataHub? | Governance | read 2026-11-24 |
| [openmetadata] | OpenMetadata documentation | Governance | read 2026-11-24 |
| [atlan] | Atlan documentation | Governance | read 2026-11-24 |
| [collibra] | Collibra data catalog product page | Governance | read 2026-11-24 |
| [alation] | Alation Data Catalog product page | Governance | read 2026-11-24 |
| [amundsen] | `amundsen-io/amundsen` repository metadata | Governance | archived; last push 2026-09-10 |
| [openlineage] | About OpenLineage | Lineage | docs 1.55.0 |
| [marquez] | Marquez Project site | Lineage | read 2026-11-24 |
| [gx] | Great Expectations / GX Core | Data quality | read 2026-11-24 |
| [soda] | What is Soda? | Data quality | read 2026-11-24 |
| [dbt-tests] | Add data tests to your DAG | Data quality | read 2026-11-24 |
| [elementary] | Elementary Data | Data quality | read 2026-11-24 |
| [deequ] | `awslabs/deequ` README | Data quality | Deequ 2.1.0 |
| [montecarlo] | Monte Carlo data observability product page | Observability | read 2026-11-24 |
| [datafold] | Datafold documentation, welcome | Observability | read 2026-11-24 |
| [sifflet] | Sifflet site | Observability | read 2026-11-24 |
| [metaplane] | Welcome to Metaplane | Observability | read 2026-11-24 |
| [kafka] | Apache Kafka, introduction | Streaming | read 2026-11-24 |
| [confluent] | Confluent Platform overview | Streaming | read 2026-11-24 |
| [redpanda] | Redpanda documentation index | Streaming | v26.3.1, console v3.15.0 |
| [flink] | Apache Flink architecture ("What is Apache Flink?") | Streaming | read 2026-11-24 |
| [kinesis] | What is Amazon Kinesis Data Streams? | Streaming | read 2026-11-24 |
| [eventhubs] | What is Azure Event Hubs | Streaming | read 2026-11-24 |
| [pulsar] | Apache Pulsar concepts overview | Streaming | Pulsar 5.0.x |
| [spark-ss] | Spark Structured Streaming | Streaming | read 2026-11-24 |
| [hightouch] | What is Hightouch? | Reverse ETL | read 2026-11-24 |
| [census] | Fivetran Activations (Census documentation URL) | Reverse ETL | read 2026-11-24 |
| [segment] | Twilio Segment documentation | Reverse ETL | read 2026-11-24 |
| [mlflow] | MLflow documentation; repository README | ML | read 2026-11-24 |
| [feast] | Feast introduction | ML | v0.68 |
| [tecton] | Tecton introduction | ML | Tecton 1.2 |
| [sagemaker] | What is Amazon SageMaker AI? | ML | read 2026-11-24 |
| [vertex] | Vertex AI introduction (page titled Gemini Enterprise Agent Platform) | ML | read 2026-11-24 |
| [jupyter] | Project Jupyter documentation | Notebooks | docs 4.1.1 alpha |
| [hex] | What is Hex? | Notebooks | read 2026-11-24 |
| [deepnote] | Deepnote documentation | Notebooks | read 2026-11-24 |
| [delta-sharing] | Read Delta Sharing tables | Sharing | read 2026-11-24 |
| [snowflake-marketplace] | Snowflake Marketplace and listings | Sharing | read 2026-11-24 |
| [iceberg-rest] | Iceberg REST catalog specification | Sharing / catalog | Iceberg 1.10.2 docs tree |
| [parquet-spec] | `apache/parquet-format` specification README | Specification | read 2026-11-24 |
| [delta-protocol] | Delta transaction log protocol (`PROTOCOL.md`) | Specification | read 2026-11-24 |
| [sql-standard] | PostgreSQL Appendix D, SQL Conformance (names ISO/IEC 9075:2023) | Specification | PostgreSQL 19 docs |
| [kafka-protocol] | Apache Kafka protocol | Specification | Kafka 4.4 |
| [openlineage-spec] | OpenLineage object model | Specification | 1.55.0 |

[fivetran]: https://fivetran.com/docs/getting-started
[airbyte]: https://docs.airbyte.com/
[debezium]: https://debezium.io/documentation/
[kafka-connect]: https://github.com/apache/kafka/blob/trunk/docs/kafka-connect/overview.md
[qlik-replicate]: https://www.qlik.com/us/products/qlik-replicate
[matillion]: https://www.matillion.com/product/
[s3]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html
[adls]: https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction
[gcs]: https://cloud.google.com/storage/docs/introduction
[minio]: https://min.io/docs/minio/linux/index.html
[delta]: https://docs.delta.io/latest/index.html
[iceberg]: https://iceberg.apache.org/spec/
[hudi]: https://hudi.apache.org/docs/overview
[unity-catalog]: https://docs.databricks.com/aws/en/data-governance/unity-catalog/
[glue-catalog]: https://docs.aws.amazon.com/glue/latest/dg/catalog-and-crawler.html
[polaris]: https://polaris.apache.org/
[nessie]: https://projectnessie.org/guides/about/
[hms]: https://cwiki.apache.org/confluence/display/Hive/AdminManual+Metastore+Administration
[snowflake]: https://docs.snowflake.com/en/user-guide/intro-key-concepts
[bigquery]: https://cloud.google.com/bigquery/docs/introduction
[redshift]: https://docs.aws.amazon.com/redshift/latest/mgmt/welcome.html
[synapse]: https://learn.microsoft.com/en-us/azure/synapse-analytics/overview-what-is
[clickhouse]: https://clickhouse.com/docs/en/intro
[duckdb]: https://duckdb.org/
[trino]: https://trino.io/docs/current/overview.html
[athena]: https://docs.aws.amazon.com/athena/latest/ug/what-is.html
[dbt]: https://docs.getdbt.com/docs/introduction
[sqlmesh]: https://sqlmesh.readthedocs.io/en/stable/
[dataform]: https://cloud.google.com/dataform/docs/overview
[airflow]: https://airflow.apache.org/docs/apache-airflow/stable/index.html
[dagster]: https://docs.dagster.io/
[prefect]: https://docs.prefect.io/
[temporal]: https://docs.temporal.io/
[argo]: https://argo-workflows.readthedocs.io/en/latest/
[tableau]: https://help.tableau.com/current/pro/desktop/en-us/default.htm
[looker]: https://cloud.google.com/looker/docs/intro
[sigma]: https://help.sigmacomputing.com/docs
[metabase]: https://www.metabase.com/docs/latest/
[superset]: https://superset.apache.org/user-docs/intro
[cube]: https://cube.dev/docs/product/introduction
[atscale]: https://www.atscale.com/product/
[dbt-sl]: https://docs.getdbt.com/docs/build/semantic-models
[datahub]: https://docs.datahub.com/docs/features
[openmetadata]: https://docs.open-metadata.org/
[atlan]: https://docs.atlan.com/
[collibra]: https://www.collibra.com/products/data-catalog
[alation]: https://www.alation.com/product/data-catalog/
[amundsen]: https://github.com/amundsen-io/amundsen
[openlineage]: https://openlineage.io/docs/
[marquez]: https://marquezproject.ai/
[gx]: https://greatexpectations.io/
[soda]: https://docs.soda.io/soda-documentation/get-started/readme.md
[dbt-tests]: https://docs.getdbt.com/docs/build/data-tests
[elementary]: https://www.elementary-data.com/
[deequ]: https://github.com/awslabs/deequ
[montecarlo]: https://www.montecarlodata.com/product/
[datafold]: https://docs.datafold.com/welcome.md
[sifflet]: https://www.siffletdata.com/
[metaplane]: https://docs.metaplane.dev/
[kafka]: https://kafka.apache.org/intro
[confluent]: https://docs.confluent.io/platform/current/overview.html
[redpanda]: https://docs.redpanda.com/current/
[flink]: https://flink.apache.org/what-is-flink/flink-architecture/
[kinesis]: https://docs.aws.amazon.com/streams/latest/dev/introduction.html
[eventhubs]: https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-about
[pulsar]: https://pulsar.apache.org/docs/next/concepts-overview/
[spark-ss]: https://spark.apache.org/streaming/
[hightouch]: https://docs.hightouch.com/
[census]: https://docs.getcensus.com/
[segment]: https://segment.com/docs/
[mlflow]: https://mlflow.org/docs/latest/index.html
[feast]: https://docs.feast.dev/
[tecton]: https://docs.tecton.ai/docs/introduction
[sagemaker]: https://docs.aws.amazon.com/sagemaker/latest/dg/whatis.html
[vertex]: https://cloud.google.com/vertex-ai/docs/start/introduction-unified-platform
[jupyter]: https://docs.jupyter.org/en/latest/
[hex]: https://learn.hex.tech/docs
[deepnote]: https://docs.deepnote.com/
[delta-sharing]: https://docs.delta.io/latest/delta-sharing.html
[snowflake-marketplace]: https://docs.snowflake.com/en/user-guide/data-marketplace
[iceberg-rest]: https://iceberg.apache.org/rest-catalog-spec/
[parquet-spec]: https://github.com/apache/parquet-format
[delta-protocol]: https://github.com/delta-io/delta/blob/master/PROTOCOL.md
[sql-standard]: https://www.postgresql.org/docs/current/features.html
[kafka-protocol]: https://kafka.apache.org/44/design/protocol
[openlineage-spec]: https://openlineage.io/docs/spec/object-model

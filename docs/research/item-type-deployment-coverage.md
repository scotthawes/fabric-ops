# Which Fabric item types can actually be deployed through our pipeline, and which must be created by hand?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the ADR that picks the deployment mechanism, and any delivery plan that promises an item type through CI/CD. Closes the "per-item-type parity … not diffed" gap in `deployment-mechanism-comparison.md`.

## Short answer

Twenty-three item types survive all three gates — Git source-control support, a public create/update definition API, and a `fabric-cicd` handler — and are safe to promise. Seven are manual-only because no public definition API exists at all (the **SQL analytics endpoint**, **Dashboard**, **Scorecard**, **Datamart**, **MirroredWarehouse**, **ML model**, **ML experiment**), and five more are API-only, so they can be created headlessly but can never be committed out of a Git-bound dev workspace. Terraform's item resources overlap the definition-API list without being either a superset or a subset of it.

## Detail

Legend: ✅ supported · ⚠️ supported with a documented limitation · ❌ not supported · —*preview* as marked by the page. Item names in the first column are the REST `ItemType` value where one exists, because that is the only spelling that is unambiguous across the three surfaces.

| Item type | Git integration | Definition API (create/update) | Terraform (`microsoft/fabric`) | `fabric-cicd` |
| --- | --- | --- | --- | --- |
| Notebook | ✅ | ✅ | ✅ `fabric_notebook` | ✅ |
| Lakehouse | ✅ | ✅ | ✅ `fabric_lakehouse` | ⚠️ schemas only if a shortcut exists; tables never |
| Warehouse | ✅ (but its own page says *preview*) | ✅ | ✅ `fabric_warehouse` | ⚠️ item shell only, DDL separate |
| SQL analytics endpoint (`SQLEndpoint`) | ❌ | ❌ (`List` only) | ❌ | ❌ |
| SemanticModel | ✅ *preview* | ✅ | ✅ `fabric_semantic_model` | ✅ |
| Report | ✅ *preview* | ✅ | ✅ `fabric_report` | ✅ |
| PaginatedReport | ✅ *preview* | ✅ (definition only) | ✅ `fabric_paginated_report` | ✅ |
| DataPipeline | ✅ | ✅ | ✅ `fabric_data_pipeline` | ✅ |
| Dataflow Gen2 (`Dataflow`) | ✅ ("Dataflow gen2") | ✅ (definition only) — but see contradiction below | ✅ `fabric_dataflow` | ⚠️ manual publish + refresh after deploy |
| Eventstream | ✅ | ✅ | ✅ `fabric_eventstream` | ✅ |
| Eventhouse | ✅ | ✅ | ✅ `fabric_eventhouse` | ✅ |
| KQLDatabase | ✅ | ✅ | ✅ `fabric_kql_database` | ✅ ("not a standalone item", deployed as one) |
| KQLQueryset | ✅ | ✅ | ✅ `fabric_kql_queryset` | ✅ |
| KQLDashboard (Real-Time Dashboard) | ✅ | ✅ | ✅ `fabric_kql_dashboard` | ✅ |
| Environment | ✅ | ✅ | ✅ `fabric_environment` | ⚠️ resources not deployed |
| SparkJobDefinition | ✅ | ✅ | ✅ `fabric_spark_job_definition` | ⚠️ `.py`/`.scala` only, no `.jar` |
| MountedDataFactory | ✅ ("Mount ADF") | ✅ (definition only) | ✅ `fabric_mounted_data_factory` | ✅ |
| MirroredDatabase | ✅ | ✅ — **service principal ❌** | ✅ `fabric_mirrored_database` | ✅ |
| Ontology | ✅ *preview* | ✅ (no preview marker) | ✅ `fabric_ontology` | ✅ |
| DataAgent | ✅ | ✅ | ✅ `fabric_data_agent` | ✅ |
| UserDataFunction | ✅ | ✅ | ✅ `fabric_user_data_function` | ✅ |
| GraphQLApi | ✅ ("GraphQL") | ✅ (definition only) | ✅ `fabric_graphql_api` | ⚠️ query changes not source controlled |
| CopyJob | ✅ | ✅ | ✅ `fabric_copy_job` | ✅ (connection configured manually) |
| Reflex (Activator) | ✅ | ✅ — service principal ❌ | ✅ `fabric_activator` | ✅ |
| DataBuildToolJob (dbt Job) | ✅ | ✅ | ❌ no resource | ✅ |
| ApacheAirflowJob | ✅ *preview* | not in the API support table | ✅ `fabric_apache_airflow_job` | ✅ |
| GraphModel | ✅ | ✅ | ❌ no resource | ✅ |
| OrgApp | ✅ (unmarked) | ✅ (definition only; create ❌) | ✅ `fabric_org_app` | ❌ not in README list |
| MLModel / MLExperiment | ✅ *preview* | ❌ no create-with-definition — service principal ❌ | ✅ `fabric_ml_model`, `fabric_ml_experiment` | ⚠️ MLExperiment shell only |
| Dashboard | ❌ | ❌ (`List` only) | ❌ | ❌ |
| Scorecard | ❌ | ❌ ("not supported for any API") | ❌ | ❌ |
| Datamart / MirroredWarehouse | ❌ | ❌ (`List` only) | ❌ | ❌ |
| Shortcut (not an item) | ✅ inside the lakehouse (`shortcuts.metadata.json`) | ❌ no item create | ✅ `fabric_shortcut` (child, needs `item_id`) | ⚠️ behind `enable_shortcut_publish` |
| Lakehouse table / schema (not items) | ❌ Tables and Files folders not tracked | ❌ | ❌ | ❌ |
| Workspace-level settings | ❌ settings are not items | ❌ | ✅ partial (`fabric_spark_workspace_settings` et al.) | ❌ |

### 1. The two Learn pages, and how their lists differ

- **Git integration:** `fabric/cicd/git-integration/intro-to-git-integration` → "Supported items" (ms.date 2026-09-01, updated 2026-11-10).
- **Deployment pipelines:** `fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines` → "Supported items" (ms.date 2026-09-24, updated 2026-11-06).

The lists are near-identical, and the differences are precise: deployment pipelines add **`Dashboard`** *(preview)* and **`Dataflow`** *(preview)* — the legacy Power BI dataflow, listed separately from "Dataflows gen2" — and mark **`Org app`** *(preview)* where Git integration does not. `Dashboard` appears in neither the definition-API list nor the Terraform resources, so deployment pipelines support an item that cannot be versioned or created headlessly. Neither list includes `SQLEndpoint`; it is an implicit child of a Warehouse or Lakehouse.

### 2. Creatable by API but not round-trippable through Git

These can be created headlessly yet are absent from the Git supported-items list, so they cannot be authored in the bound dev workspace and committed:

`Dataflow` (Power BI, definition-only), `OrgAppAudience` (definition-only), `AzureDatabricksStorage` (definition-only), `MirroredCatalog`. Definition pages also exist for `PolicySet`, `Monitoring` and `PostgreSQL database`, but they do not appear in the API support table, so their create support "could not establish" — treat them as unusable.

### 3. No public definition API — deployment is impossible by any of our routes

`SQLEndpoint`, `Dashboard`, `Scorecard`, `Datamart`, `MirroredWarehouse`, `MLModel`, `MLExperiment`. The `SQLEndpoint` row is the most consequential: Create ❌, Create-with-definition ❌, Get ❌, Update ❌, Delete ❌, **List ✅** only. The warehouse page confirms "Version control support for SQL analytics endpoints isn't currently available", and the lakehouse page shows the endpoint's metadata riding along inside the parent item rather than as an item of its own.

`Dashboard` and `Scorecard` are equally closed: Create ❌, Get ❌, Update ❌, List ✅. There is no item-definition path to them at all.

### 4. Terraform versus the definition API

**Neither a superset nor a subset — overlapping with different edges.** The provider now ships item resources for roughly 40 types, including ones with no Git support (`fabric_shortcut`) and workspace-level settings. It *lacks* resources for `DataBuildToolJob`, `GraphModel`, `GraphQuerySet`, `EventSchemaSet`, `Plan`, `DeploymentPlan` (the item, as distinct from `fabric_deployment_pipeline`), `OrgAppAudience`, `PolicySet` and `SQLDatabase`-adjacent endpoint types.

Its stated caveats, verbatim from the provider docs: "**Not all Fabric resources support Service Principals yet**"; trial capacity "is not supported"; and the provider globally "is an open-source project that is **NOT** covered by the Microsoft Fabric or Microsoft support policies". The provider also exposes `preview = false` by default — "Enable preview mode to use preview features" — so a resource existing in the directory does not mean it works without opting in.

### 5. Preview in one surface, GA-looking in another

- **Warehouse** — unmarked in the Git supported-items list, but its own page says "This feature is in preview."
- **Org app** — unmarked in Git, *(preview)* in deployment pipelines.
- **Ontology** — *(preview)* in both Git and deployment-pipeline lists, yet the API support table lists it with ✅ across the board and Terraform ships `fabric_ontology`.
- **Semantic model and Report** — *(preview)* in both ALM lists, but ✅ in the API table and treated as ordinary by `fabric-cicd`.
- **Dataflow** — *(preview)* in deployment pipelines, and the deployment-pipeline API says flatly "Dataflows are currently not supported", so the UI supports something the API refuses.

⚠️ The API support page contradicts itself on `Dataflow`: a note says "The following item types are not supported for any API: … Dataflow", while the Power BI table three sections later gives `Dataflow` Create ✅ and "✅ definition only". The most likely reading is that the note means the legacy Power BI dataflow and the table means Dataflow Gen2, but the page does not say so. Do not promise Dataflow Gen2 on that row alone.

⚠️ Deployment pipelines also carry a dated retirement: "Beginning February 12, 2026, Fabric deployment pipelines retire support for semantic models that aren't upgraded to Enhanced Metadata." That date has passed, so any non-Enhanced-Metadata semantic model is already undeployable through that surface.

## What this settles

- **Can promise through the pipeline (23):** Notebook, Lakehouse, Warehouse, Semantic model, Report, Paginated report, Data pipeline, Dataflow Gen2 (with the contradiction caveat), Eventstream, Eventhouse, KQL database, KQL queryset, Real-Time dashboard, Environment, Spark job definition, Mounted data factory, Mirrored database, Ontology, Data agent, User data function, GraphQL API, Copy job, Activator.
- **Promise only as a shell, with DDL/schema deployed separately:** Warehouse, SQL database, Lakehouse schemas. `fabric-cicd` says "Only the item shell is deployed" for the first two and "Schemas are not deployed" for the third.
- **Must be created by hand:** SQL analytics endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model, ML experiment, lakehouse tables and Files folders, workspace-level settings.
- **Never author in the Git-bound dev workspace** (cannot be committed, so portal work is unversioned and invisible): Dataflow (Power BI), Org app audience, Azure Databricks Storage, Mirrored catalog, Dashboard, Scorecard, SQL analytics endpoint.
- **Do not put Mirrored database or Activator behind a service principal without checking the tenant**: both are definition-deployable but the API table marks service-principal support ❌.

## What this does not establish

- Whether the API support table is complete. It omits `ApacheAirflowJob`, `Map`, `AnomalyDetector`, `CosmosDBDatabase`, `VariableLibrary`, `DataAgent`, `UserDataFunction`, `GraphModel`, `EventSchemaSet`, `OperationsAgent` and `WarehouseSnapshot` even though several have definition pages and `fabric-cicd` handlers. Absence there is not evidence of absence.
- Whether `fabric-cicd`'s README list matches what the library actually publishes today; the docs are generated and the library "moves quickly" (its own wording).
- Runtime behaviour of preview items, throttling headroom, or whether `fabric-cicd` will gain handlers for Org app, Graph QuerySet and Mirrored Azure Databricks Catalog.
- Whether Terraform resources marked preview-gated actually round-trip definitions for every type; only the resource's existence was checked, not each `definition` schema.

## Answered 2026-11-12 — is the "API support" table complete?

**No, and it does not have to be read as if it were.** `item-management-overview` is a curated matrix
of 37 item types; the OpenAPI spec that the REST reference is generated from declares 61 groups, 49 of
which carry a `getDefinition`/`updateDefinition` pair. Eighteen of those 49 are absent from the matrix.
Five of the six types the issue names — `Map`, `VariableLibrary`, `AnomalyDetector`,
`CosmosDBDatabase`, `OperationsAgent` — have the definition pair, a Learn definition page and a place in
both supported-items lists. `WarehouseSnapshot` has none of the three and is a different case.

Census used: `docs/reference/api-operations.tsv`, **825 operations / 61 groups**, generated 2026-11-12
from `microsoft/fabric-rest-api-specs` at commit `3f8600f` (2026-11-10). All five definition pairs below
are `POST /workspaces/{workspaceId}/<collection>/{id}/getDefinition` and `…/updateDefinition`.

| Census group | Ops | Definition operations | Learn definition page | Git list | Deployment-pipeline list |
| --- | --- | --- | --- | --- | --- |
| `map` | 7 | `Items_GetMapDefinition`, `Items_UpdateMapDefinition` | "Map item definition" | Maps | Maps |
| `variableLibrary` | 7 | `Items_GetVariableLibraryDefinition`, `Items_UpdateVariableLibraryDefinition` | "Variable Library definition" | Variable Library | Variable Library |
| `anomalyDetector` | 7 | `Items_GetAnomalyDetectorDefinition`, `Items_UpdateAnomalyDetectorDefinition` | "Anomaly detector item definition" | Anomaly detection *(preview)* | Anomaly detection *(preview)* |
| `cosmosDbDatabase` | 7 | `Items_GetCosmosDBDatabaseDefinition`, `Items_UpdateCosmosDBDatabaseDefinition` | "Cosmos DB Database definition" | Cosmos database *(preview)* | Cosmos database *(preview)* |
| `operationsAgent` | 7 | `Items_GetOperationsAgentDefinition`, `Items_UpdateOperationsAgentDefinition` | "Operations agent definition" | Operations Agent *(preview)* | Operations Agent *(preview)* |
| `warehouseSnapshot` | 5 | **none** — create, get, update, delete, list only | none | absent | absent |

Sources for those columns: [item-mgmt] (37 rows, footer "Last updated on 2026-06-18", metadata
updated 2026-11-10), [itemdef] (48 entries, two of them duplicated — Dataflow and KQL Dashboard — so
46 distinct; updated 2026-11-11), [git-intro] (updated
2026-11-10), [dp-intro] (updated 2026-11-06).

### The matrix is right about what it lists, and silent about the rest

Its 37 rows span seven experience headings — Data Factory 4, Data Engineering 7, Data Science 2, Data
Warehouse 7, Fabric IQ 1, Power BI 7, Real-Time Intelligence 9. Thirty-one carry a definition pair in
the census; the six that do not are exactly this note's manual-only list (`Dashboard`, `Datamart`,
`MirroredWarehouse`, `MLExperiment`, `MLModel`, `SQLEndpoint`). That is a good consistency check on both
sides. The failure is directional only: a type missing from the matrix is not a type missing from the
API.

The eighteen definition-carrying groups absent from the matrix are `anomalyDetector`, `apacheAirflowJob`,
`cosmosDbDatabase`, `customStreamConnector`, `dataAgent`, `deploymentPlan`, `eventSchemaSet`,
`graphModel`, `map`, `monitoring`, `operationsAgent`, `plan`, `platform`, `policySet`, `share`,
`sqlDatabase`, `userDataFunction`, `variableLibrary`. Two of those are not item types — `platform` holds
the generic `items/{itemId}/getDefinition` endpoints and `share` the OneLake data-share ones — leaving
**16 item types** with documented definition operations that the matrix does not mention.

Learn contradicts itself here independently of the census: `sqlDatabase` and `deploymentPlan` are absent
from the matrix yet appear in **both** supported-items lists, and both have definition pages. So "not in
the API support table" cannot even be used as a signal that a type is uncooked.

### The instruction in §2 above is overturned

§2 says `PolicySet`, `Monitoring` and `PostgreSQL database` "do not appear in the API support table, so
their create support 'could not establish' — treat them as unusable". Absence from that table is not
evidence about operations. The census gives `policySet` 16 operations and `monitoring` 9, each with the
definition pair, and [itemdef] lists "PolicySet item definition" and "Monitoring definition". What stays
unknown is narrower: whether those definitions round-trip, and whether a service principal may call them
— the census explicitly cannot answer either.

### What remains unestablished

- **Whether any of the five definitions round-trips.** The spec proves the operations are declared; the
  definition page proves a format is documented; neither proves `getDefinition` output is accepted back
  by `updateDefinition`. The probe: for each type, create in a dev workspace, `getDefinition`, delete,
  re-create with that definition, then `updateDefinition` the same payload and diff. A failure is
  informative per type, not per group.
- **Whether the deployment-pipeline list is UI truth.** This note already records one UI/API mismatch on
  that page (`Dataflow`: supported in the list, "Dataflows are currently not supported" in the API). The
  same caution applies to Maps, Anomaly detection, Operations Agent, Cosmos database and Variable
  Library until a deploy is run.
- **Service-principal support for all six.** Absent from the census by construction; the matrix has no row
  for them either, so there is no author statement to quote.
- **`WarehouseSnapshot`'s route, if any.** It has item CRUD and no definition operations, is in neither
  supported-items list, and has no definition page. It appears to be created from a warehouse rather than
  authored, but no page checked says how it may be deployed; treat it as manual and out of scope for the
  23-type promise.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [git-intro] | Git supported items, preview markers, 1,000-item limit | ms.date 2026-09-01, upd. 2026-11-10 |
| [git-process] | workspace structure mirrored, folders, unsupported items ignored | ms.date 2026-06-15, upd. 2026-10-26 |
| [dp-intro] | deployment-pipeline supported items, Dashboard/Dataflow delta, semantic-model retirement | ms.date 2026-09-24, upd. 2026-11-06 |
| [dp-auto] | "Dataflows are currently not supported" in the pipeline API | ms.date 2026-09-24, upd. 2026-09-29 |
| [itemdef] | the definition-based API list per item type | ms.date 2024-11-12, upd. 2026-11-11 |
| [item-mgmt] | authoritative create/definition/SP-support matrix; `SQLEndpoint`, `Dashboard`, `Scorecard` rows | upd. 2026-11-10 |
| [create-item] | `ItemType` enum, Contributor requirement, SP caveat | upd. 2026-11-11 |
| [wh-git] | "This feature is in preview"; SQL analytics endpoint not versioned | ms.date 2026-08-13, upd. 2026-09-22 |
| [lh-git] | tables/folders not tracked, shortcut tracking, schema deployment | ms.date 2026-10-13 |
| [cicd-home] | "Only supports items that have Source Control, and Public Create/Update APIs"; README item list | read 2026-11-11 |
| [cicd-types] | per-item documented limitations (shell-only, shortcuts flag, `.jar`) | read 2026-11-11 |
| [tf-res] | resource directory listing; which item resources exist | read 2026-11-11 |
| [tf-index] | "Not all Fabric resources support Service Principals yet", `preview` flag | v1.15.1, read 2026-11-11 |
| [tf-shortcut] | Shortcut is a child resource needing `item_id`, not an item | read 2026-11-11 |

[git-intro]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration
[git-process]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process
[dp-intro]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines
[dp-auto]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/pipeline-automation-fabric
[itemdef]: https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/item-definition-overview
[item-mgmt]: https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/item-management-overview
[create-item]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item
[wh-git]: https://learn.microsoft.com/en-us/fabric/data-warehouse/git-integration
[lh-git]: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-git-deployment-pipelines
[cicd-home]: https://microsoft.github.io/fabric-cicd/latest/
[cicd-types]: https://microsoft.github.io/fabric-cicd/latest/reference/item_types/
[tf-res]: https://github.com/microsoft/terraform-provider-fabric/tree/main/docs/resources
[tf-index]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/index.md
[tf-shortcut]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/shortcut.md

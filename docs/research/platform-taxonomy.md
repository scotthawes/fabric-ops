# What is Microsoft's own component vocabulary for Fabric, and where does each component sit?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the system map. It is drawn from this vocabulary rather than invented layers, so every box on it must have a name from section 2 or 6.

## Short answer

Four words carry the containment — **tenant → capacity → workspace → item** — and only the capacity is an Azure resource. Nine **workloads** contribute **items**, every item's data lands in the single **OneLake**, and capacity units are spent by **engines**, not by metadata services. The **control plane** is `api.fabric.microsoft.com`; the **data plane** is a set of per-engine endpoints (OneLake DFS, T-SQL, KQL, XMLA), and only OneLake's token audience is stated plainly in the docs (`Storage`).

## Detail

### 1. The containment hierarchy, in the product's words

| Level | Microsoft's definition | Azure resource? |
| --- | --- | --- |
| **Tenant** | "A *tenant* is a single instance of Fabric for an organization, aligned with a Microsoft Entra tenant." It is also "at the top level of the hierarchy" of OneLake. | No. It is an Entra tenant. |
| **Capacity** | "Each capacity in a tenant is a distinct resource pool for Microsoft Fabric." "Capacities use stock-keeping units (SKUs)." F SKUs are "purchased through Azure". | Yes for F SKUs — created in a subscription and resource group, and managed by "Fabric capacity REST APIs … part of the Azure REST APIs". P SKUs are Microsoft 365; a Trial capacity is neither. |
| **Workspace** | "Workspaces reside within capacities and act as containers for Microsoft Fabric items." Also "the collaboration and security boundary", capped at 1,000 items. | No. Created and named inside Fabric. |
| **Item** | "An *item* is an object in Fabric, such as a lakehouse, notebook, warehouse, or eventhouse." | No. |

The nesting described above is real, but one boundary matters more than the tree:

- **Where containment stops, and where it is not a tree.** A capacity contains workspaces and a workspace contains items, but items never carry a capacity reference: "Each workspace is part of a capacity that's tied to a specific region and billed separately" — so an item's capacity is derived from its workspace. Some items are children of other items rather than siblings: "an eventhouse can hold multiple KQL databases", and the **SQL analytics endpoint** is a "feature" of a lakehouse, warehouse or mirrored database, not something you create. Item APIs still expose these children as items (`SQLEndpoint`, `KQLDatabase`), so a two-level map under-counts.

### 2. The workloads, the items each contributes, and the engine behind them

Microsoft's own list, verbatim: "The Fabric workloads include Data Engineering, Data Factory, Data Science, Data Warehouse, Databases, Industry Solutions, Real-Time Intelligence, Fabric IQ, and Power BI." Item names below are the product's display names; REST `ItemType` values are given where the API differs.

| Workload | Items it contributes | Compute engine |
| --- | --- | --- |
| **Data Engineering** | Lakehouse, Notebook, Spark job definition, Environment, User data functions, GraphQL API | **Apache Spark** — "Two Spark VCores … equals one capacity unit (CU)". |
| **Data Factory** | Pipeline, Dataflow Gen2, Copy job, Mounted Data Factory, dbt job, Apache Airflow job, Operations agent (preview) | No single engine: orchestration meters (`ActivityRun`, `DataMovement`) for pipelines, the Power Query/mashup engine for Dataflow Gen2 (`Dataflow Gen2 Run Queries`), plus a staging **Warehouse** for "High Scale Dataflow Compute". |
| **Data Science** | Notebook, ML experiment, ML model, Data agent | Spark plus MLflow tracking; ML model endpoints "spin up and manage the underlying container infrastructure". |
| **Data Warehouse** | Warehouse, Warehouse snapshot; the SQL analytics endpoint is a child feature | **T-SQL** — "One Fabric Data Warehouse core … is equivalent to 0.538 Fabric Capacity Units". |
| **Databases** | SQL database in Fabric, Cosmos DB in Fabric, Mirrored database | SQL engine ("One Fabric capacity unit = 0.383 SQL database vCores") and the Cosmos DB engine. |
| **Real-Time Intelligence** | Eventhouse, KQL database, KQL queryset, Real-Time Dashboard (`KQLDashboard`), Eventstream, Activator (`Reflex`), Map, Anomaly detector, Event schema set, Digital twin builder, Operations agent, Graph model + Graph queryset | **KQL** (the Kusto engine) — the `Eventhouse UpTime` operation is the meter; Eventstream meters are per hour, per GB and per vCore. |
| **Fabric IQ (preview)** | Ontology, Plan, Graph, Data agent, Operations agent, Power BI semantic model | Could not establish a per-item engine. The workload page documents items and relationships, not compute; the agent items are metered under the Copilot and AI meters (`LlmPlugin` for Data agent). |
| **Power BI** | Semantic model, Report, Dashboard, Paginated report, Scorecard, Dataflow (Gen1), Datamart, Org app | **Analysis Services engine** — "XMLA is the communication protocol used by the Microsoft Analysis Services engine, which runs Power BI's semantic modeling"; "Eight CUs are equivalent to one Power BI v-core." |
| **Industry Solutions** | Could not establish an item list; docs describe industry data solutions, not item types. | Not stated. |

Two naming traps sit inside the list: the workload is **"IQ (preview)"** inside Fabric while **"Fabric IQ"** is the Microsoft IQ capability it belongs to, and the overview page's architecture diagram labels the same set differently ("Data Factory, Analytics, Databases, Real-Time Intelligence, IQ, and Power BI"). Use the terminology page's list. Items can also belong to several workloads at once — "Fabric items can be part of multiple workloads" — so a workload is a view, not an owner.

### 3. OneLake as the storage layer

OneLake is **one instance per tenant**: "Every Fabric tenant automatically includes OneLake … You can't delete OneLake or create multiple OneLakes." It is "built on Azure Data Lake Storage and stores tables in Delta Parquet or Iceberg format", and it is the reason the layer list has no per-workload storage tier.

- **The one-copy premise.** "All Fabric analytics engines work with data directly in OneLake." T-SQL, Spark and Analysis Services "all store data in OneLake in the open Delta Parquet format", and Power BI reads them in **Direct Lake** mode "without making a copy".
- **Tables versus files.** A lakehouse is "a collection of files, folders, and tables"; its `Tables/` area holds Delta tables and `Files/` holds arbitrary files. The SQL analytics endpoint reads the Delta tables; the lakehouse explorer is the UI over both.
- **Shortcuts** are "a reference to data stored in other file locations" — "files and folders look like you have them stored locally" while nothing is copied, including across clouds and tenants.
- **Mirroring has two modes and only one is copy-free.** "Database mirroring continuously replicates data … into OneLake as analytics-ready Delta tables" — that *is* a copy. "Metadata mirroring synchronizes an external catalog and uses shortcuts to access its open-format data in place without copying it." Do not write "mirroring never copies" on the map.
- **Iceberg interop** is metadata virtualization: virtual metadata makes Iceberg read as Delta and vice versa, without conversion copies.

### 4. Engines, services and storage — and what never spends a CU

**Consumes capacity units (compute):** Spark (notebooks, Spark job definitions, lakehouse table loads, materialized lake views, shortcut transformations); T-SQL (Warehouse, SQL analytics endpoint, Warehouse snapshot, SQL database); KQL (Eventhouse uptime, KQL queries); the Analysis Services engine (interactive queries, semantic model refresh, XMLA read/write); the Power Query engine (Dataflow Gen2, Dataflow Gen1 refresh); orchestration and data movement (Pipeline `ActivityRun`, `DataMovement`); Eventstream per-hour/GB/vCore; GraphQL (10 CU per hour); User data functions; ML model endpoints; Copilot and AI meters. Operations are classified **interactive** or **background**, and that split, not the workload, drives throttling.

**Storage:** OneLake. It is metered as storage (GB, "current and billable storage by workspace") plus per-operation CU for reads and writes — so it is the one layer that appears in both halves.

**Metadata/control services that consume no capacity units:** workspace and item CRUD, item definitions, domains, endorsements, sensitivity labels, tenant settings, capacity administration, deployment pipelines, Git integration, and catalog search. Caveat: this is established **by omission** — none of these appears in the per-experience operation tables, and Microsoft never states "control-plane calls are free". Also note "Non-billable items and operations reflect preview features that don't count towards your capacity limit", so preview items (much of IQ) distort any consumption picture.

### 5. Control plane versus data plane

| Surface | Endpoint | Documented auth |
| --- | --- | --- |
| **Management / items** | `https://api.fabric.microsoft.com/v1/` | Entra token with Fabric scopes, written in the `https://api.fabric.microsoft.com/<Scope>` form (for example `Workspace.ReadWrite.All`, `Item.ReadWrite.All`). |
| **Management / admin** | The Fabric REST **Admin** APIs (namespace `/rest/api/fabric/admin/`), which cover "most of the actions available from the UI" for domains and peers | Same token; additionally gated by Fabric admin role and admin-API allow-lists. |
| **Management / capacity** | Azure Resource Manager for `Microsoft.Fabric/capacities` | Azure RBAC, not Fabric scopes. |
| **Portal** | `*.fabric.microsoft.com` (TCP 443) | Entra. |
| **OneLake files** | `*.onelake.dfs.fabric.microsoft.com` (DFS APIs), `*.onelake.blob.fabric.microsoft.com` (Blob APIs) | "OneLake only supports tokens in the `Storage` audience." |
| **T-SQL** | `*.datawarehouse.fabric.microsoft.com`, TCP 1433 (TDS); `*.database.fabric.microsoft.com` for SQL database | Entra user or service principal; SQL auth unsupported. |
| **KQL** | `https://*.z[0-9].kusto.fabric.microsoft.com` | Entra. |
| **XMLA (semantic models)** | `powerbi://api.powerbi.com/v1.0/<tenant>/<workspace>` | Entra, per the XMLA client library rules. |

The audience question is only half answered: Fabric scopes are namespaced to `api.fabric.microsoft.com`, OneLake requires `Storage`, and the TDS/KQL/XMLA pages document Entra authentication without stating a distinct audience string. **Could not establish** a single audience table; do not infer one.

### 6. Cross-cutting surfaces, and the layer each acts at

| Surface (exact name) | Layer it acts at |
| --- | --- |
| **Tenant settings** | Tenant-wide switches, optionally scoped to security groups; some are delegable to a capacity or a domain. |
| **Domains** (and subdomains) | Above workspaces: groups workspaces for governance. "Domain assignment doesn't affect item visibility or accessibility for tenant users." |
| **Sensitivity labels** | Per item, inherited downstream from Microsoft Purview Information Protection. |
| **Endorsement** | Per item — three badges only: **Promoted**, **Certified**, **Master data**. |
| **Capacity administration** | One capacity: admins, contributors, resize, workloads, delegated tenant settings. |
| **Workspace roles** | One workspace: **Admin**, **Member**, **Contributor**, **Viewer**. |
| **Deployment pipelines** | Workspace-to-workspace promotion in 2–10 stages, with item **pairing**. |
| **Git integration** | One workspace bound to one branch of an Azure DevOps/GitHub repo; "The integration with source control is on a workspace level." |
| **Item definition APIs** | One item: `Get Item Definition`, `Update Item Definition`, `Create Item with Definition`, plus bulk import/export. |
| **Monitor hub** | Cross-estate observability (preview): job runs, alerts, applications, capacity, agents — filtered to items you can see. |
| **Real-Time hub** | Tenant-wide discovery of data in motion ("Every Fabric tenant automatically includes the hub"); lists streams and KQL tables, and is not a workload. |
| **Microsoft Fabric Capacity Metrics app** | A Power BI app over capacity telemetry (Health, Compute, Storage, Timepoint pages) — the only place CU consumption is attributed to an item. |
| **OneLake catalog** | Tenant-wide discovery and governance, in three tabs: **Explore**, **Govern**, **Secure**. |

### 7. Vocabulary traps

| Term | Sounds like | Correct reading |
| --- | --- | --- |
| **Pipeline** | a deployment pipeline | A Data Factory item for orchestration. The terminology page is explicit: "These pipelines are different from the deployment pipelines in Fabric." |
| **Capacity** | a SKU | The SKU is the size (F64, F2048); the capacity is the provisioned resource instance that workspaces are assigned to. Resizing changes the SKU, not the capacity's identity. |
| **Workspace** | workspace identity | The workspace is the container; the **workspace identity** is "an automatically managed service principal that can be associated with a Fabric workspace", used for trusted workspace access. |
| **Semantic model** | dataset | Same object, renamed: "The term *Semantic model* replaces the term *dataset*. You may still see the old term in the UI." |
| **Item** | artifact | The REST API calls them artifacts ("read all artifacts of type `<itemType>`"); the product says item. One concept. |
| **Workload** | experience, item | Workload is the grouping (Data Engineering); experience is the UI surface; item is the object (Lakehouse). The three are not interchangeable. |
| **Monitor hub** | Monitoring hub, admin monitoring workspace | The current product page says **Monitor hub** (preview); operational docs and the admin overview still say "Monitoring hub" and "Monitoring and health". One surface under three names. |
| **Real-Time hub** | Real-Time Intelligence | The hub is a tenant-wide discovery surface; Real-Time Intelligence is the workload whose items (Eventhouse, Eventstream) feed it. |
| **"Lakehouse catalogue"** | OneLake catalog | No such product name. The tenant-wide catalogue is the **OneLake catalog**; a lakehouse's own object tree is the lakehouse explorer. |
| **Deployment plan** | deployment pipeline | A plan is an item (preview) attached to a deployment to impose order and actions; the pipeline is the stage container. |
| **Dataflow** | Dataflow Gen2 | Gen1 lives in Power BI and still appears as an item; "You can't upgrade from Gen1 to Gen2." They have separate meters. |

## What this settles

| Component | Layer | Engine | Consumes CU |
| --- | --- | --- | --- |
| Tenant | containment root | — | no |
| Capacity (F SKU) | Azure resource, containment | — | no (it *supplies* CU) |
| Workspace | containment / security boundary | — | no |
| Lakehouse | item, Data Engineering | Spark + SQL analytics endpoint | yes (on Spark and T-SQL operations) |
| Warehouse | item, Data Warehouse | T-SQL | yes |
| SQL analytics endpoint | child feature of lakehouse/warehouse/mirrored DB | T-SQL | yes |
| Notebook | item, Data Engineering / Data Science | Spark | yes |
| Spark job definition | item, Data Engineering | Spark | yes |
| Pipeline | item, Data Factory | orchestration | yes |
| Dataflow Gen2 | item, Data Factory | Power Query/mashup | yes |
| Eventhouse / KQL database | items, Real-Time Intelligence | KQL (Kusto) | yes |
| Eventstream | item, Real-Time Intelligence | streaming | yes |
| Semantic model | item, Power BI (also IQ) | Analysis Services | yes |
| Report / Paginated report | items, Power BI | Analysis Services | yes |
| SQL database in Fabric / Cosmos DB in Fabric | items, Databases | SQL / Cosmos | yes |
| Ontology, Plan | items, IQ (preview) | not documented | not established (preview, meter unlisted) |
| OneLake | storage | — | yes for reads/writes; storage metered separately |
| Shortcut | OneLake object, not an item | — | yes only when transform or read occurs |
| Domain, endorsement, label, tenant setting | governance metadata | — | no |
| Deployment pipeline, Git integration, item definition API | control plane | — | no |

## What this does not establish

- The per-item compute model for **Fabric IQ (preview)** and the item list for **Industry Solutions**; the docs describe concepts, not engines or meters.
- That control-plane calls are unmetered, and token audiences for TDS, KQL and XMLA. Both are inferred: the first from the absence of any operation row, the second from pages that document Entra auth without naming an audience. Only OneLake's `Storage` audience is stated plainly.
- Whether "Monitor hub" replaces "Monitoring hub" as the official name, and whether any surface called a "Lakehouse catalogue" exists. Neither is resolvable from the docs; the nearest real things are the Monitor hub page and the OneLake catalog.
- Capacity overage, surge protection and autoscale mechanics — covered in `capacity-provisioning-and-cost-control.md`.

## Sources

| Source | ms.date | Used for |
| --- | --- | --- |
| [Microsoft Fabric terminology](https://learn.microsoft.com/en-us/fabric/fundamentals/fabric-terminology) | 2026-07-08 | Workload list; item, workspace, tenant, capacity, domain definitions; pipeline-vs-deployment-pipeline |
| [What is Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/microsoft-fabric-overview) | 2026-03-18 | Components, engines, OneLake positioning, hierarchy |
| [Fabric licenses and capacity](https://learn.microsoft.com/en-us/fabric/enterprise/licenses) | 2026-06-15 | Tenant/capacity/workspace containment; F vs P vs Trial; SKUs and CUs |
| [Workspaces](https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces) | 2026-07-28 | Workspace roles, 1,000-item cap, workspace settings |
| [Fabric operations](https://learn.microsoft.com/en-us/fabric/enterprise/fabric-operations) | 2026-10-23 | Which operations consume CU; CU conversion factors; interactive vs background; semantic model vs dataset |
| [OneLake overview](https://learn.microsoft.com/en-us/fabric/onelake/onelake-overview) | 2026-03-09 | One-copy premise, Delta/Iceberg, shortcuts, mirroring modes |
| [Connect to OneLake](https://learn.microsoft.com/en-us/fabric/onelake/onelake-access-api) | 2026-05-18 | OneLake URI, DFS endpoint, `Storage` audience |
| [Fabric IQ overview](https://learn.microsoft.com/en-us/fabric/iq/overview) | 2026-07-08 | IQ (preview) workload and its item list |
| [Fabric allow-list URLs](https://learn.microsoft.com/en-us/fabric/security/fabric-allow-list-urls) | 2026-02-13 | Data-plane endpoints: OneLake DFS/Blob, `*.datawarehouse`, `*.kusto`, `*.database` |
| [Fabric API quickstart](https://learn.microsoft.com/en-us/rest/api/fabric/articles/get-started/fabric-api-quickstart) | 2025-05-28 | `https://api.fabric.microsoft.com/v1/` base URL and scope string form |
| [Fabric REST API scopes](https://learn.microsoft.com/en-us/rest/api/fabric/articles/scopes) | 2025-02-03 | Scope families; "artifacts" as the API word for items |
| [Fabric REST APIs for automation](https://learn.microsoft.com/en-us/rest/api/fabric/articles/get-started/using-fabric-apis) | 2026-07-28 | Capacity APIs are Azure REST APIs |
| [Item definitions](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/item-definition-overview) | 2024-11-12 | Item definition API names |
| [Deployment pipelines](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines) | 2026-09-24 | Stages, pairing, supported items |
| [Git integration](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration) | 2026-09-01 | Workspace-level binding, supported items |
| [Capacity Metrics app](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app) | 2026-08-28 | CU attribution, storage pages, non-billable preview operations |
| [Manage your capacity](https://learn.microsoft.com/en-us/fabric/admin/capacity-settings) | 2026-03-06 | Capacity administration scope, capacity types, delegated tenant settings |
| [Fabric administration](https://learn.microsoft.com/en-us/fabric/admin/admin-overview) | 2026-09-01 | Govern/Secure/Operate/Optimize surfaces, admin tooling |
| [Domains](https://learn.microsoft.com/en-us/fabric/governance/domains) | 2025-05-01 | Domain layer and non-effect on visibility |
| [OneLake catalog](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-overview) | 2026-08-26 | Explore/Govern/Secure tabs |
| [Endorsement](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) | 2024-07-11 | Promoted / Certified / Master data |
| [Information protection](https://learn.microsoft.com/en-us/fabric/governance/information-protection) | 2026-07-13 | Label inheritance and coverage |
| [Monitor hub](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub) | 2026-09-04 | Monitor hub pages, preview status |
| [Workspace identity](https://learn.microsoft.com/en-us/fabric/security/workspace-identity) | 2026-09-16 | Workspace identity definition and lifecycle |
| [XMLA endpoint](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-premium-connect-tools) | 2026-02-05 | Analysis Services engine, `powerbi://` connection string |
| [Warehouse connectivity](https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity) | 2026-09-09 | TDS endpoint, port 1433, auth types |

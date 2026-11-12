# What governance metadata does Fabric emit by itself, what has to be maintained by hand, and can any of it be automated?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the governance-metadata section of the deployment design, and the run-book item "what the scheduled governance job reads".

## Short answer

Fabric emits one governance artefact free — an item-level lineage graph per workspace — plus the
catalogue columns it derives from item state (owner, refresh, endorsement, label). Beyond that,
metadata is either not captured (cross-workspace downstream edges, column detail), not writable
(endorsement, ownership), or leaves Fabric only through a Purview scan someone registered, licensed and
scheduled. A pipeline can own **description and tags**; labels are creation-only and the Fabric-native
setter refuses service principals.

## Detail

### 1. Lineage: automatic inside one workspace, and it stops at the wall

> "Every workspace automatically has a lineage view." (lineage, ms.date 2023-11-06)

The graph is item-level: "you see the lineage relationships between all the items in a workspace, as
well as data sources external to the workspace one-step upstream." Cards, not columns — no page read
describes column-level lineage, and Govern says the same of subitems: "Subitems such as tables aren't
supported and don't appear in insights" (2026-08-26).

| Boundary | Behaviour |
| --- | --- |
| Upstream, outside it | "Upstream connections outside the workspace, one level up", named with the external workspace |
| Downstream, outside it | **Not shown.** "Downstream items in different workspaces aren't shown" — use impact analysis |
| External data sources | Semantic models and dataflows only; one step; a card may name the Azure SQL database |
| Who sees it | "Any user with a role in a workspace … However, users with the Viewer role won't see data sources" |

"All the items" comes with no per-type table, so "notebooks and pipelines are covered" is an inference,
not a quote (**could not establish** a coverage table). One soft spot: semantic model ↔ dataflow
lineage holds "only if the **Get Data** UI is used".

**Impact analysis** is the only downstream view and it is a person's tool: it needs write permission,
shows "direct children, or all affected downstream items and workspaces", but "For data sources, you can
only see direct children", and hides unreadable names as "Limited access" (2023-05-23).

### 2. The OneLake catalog: per-item facts on Explore, coverage on Govern

Per-item metadata lives on Explore as columns: **Owner** ("Item owner"), **Refreshed** ("Last refresh
time of data items"), **Endorsement**, **Sensitivity** (2026-10-08). Item details adds **Tags** and "the
details of the endorsing user"; **Owner** there is "the item owner or contact".

**Govern** does not show those values. It reports estate **coverage** — "sensitivity label coverage",
DLP, "description and endorsement coverage" — over "Admin Monitoring Storage", which "refreshes
automatically every day". Entries depend on your permissions: a non-admin sees only "**Configurations**,
with Help and support entries only"; "All data in Fabric" needs "tenant-wide visibility". It is "not
available when Private Link is activated", excludes cross-tenant and guest users, and needs Power BI Pro
unless the workspace is on a capacity.

**Queryability: partly.** `POST /v1/catalog/search` (`Catalog_Search`, Preview, `Catalog.Read.All`, SP
**Yes**) returns only `id`, `type`, `catalogEntryType`, `displayName`, `description` and
`hierarchy.workspace` (updated 2026-11-11) — no endorsement, sensitivity, owner or refresh state; those
need three other APIs (§6). Govern's aggregates have no documented API: a generated report.

### 3. Purview integration: a pull, from a paid account, over the admin APIs

"Scanning a Fabric tenant brings in metadata and lineage from Fabric items including Power BI"
(register-scan-fabric-tenant, ms.date 2026-04-28) — the only way this metadata leaves the tenant.

- **Direction, schedule, cost:** pull. "Microsoft Purview leverages the scanner API to retrieve the
  metadata and lineage" (2025-05-01); Fabric never pushes. Trigger "**Recurring**" or "**Once**"; Full,
  Incremental and Scoped variants. The prerequisite is "An active Microsoft Purview account", and
  "Automated scans for the hybrid data estate" appear only in the Enterprise column of the
  free/enterprise comparison (2024-09-24); free covers Fabric by live view only, and the meter is
  **could not establish**.
- **Fabric-side permissions:** a security group holding the Purview managed identity or SP; **Allow
  service principals to use read-only admin APIs** scoped to it; **Enhance admin APIs responses with
  detailed metadata** and **… with DAX and mashup expressions**; **Users can access data stored in
  OneLake with apps external to Fabric**. Wait ~15 minutes.
- **Arrives:** every item type in the scan table — Lakehouse, Notebook, Data pipeline, Dataflow Gen2,
  Spark Job Definition, SQL analytics endpoint, Warehouse, KQL Database, Queryset, Experiment, ML
  model, plus the Power BI types (Paginated report: scan only, no live view). But "for all Fabric items
  besides Power BI, **only item level metadata and lineage** can be scanned. For Lakehouse tables and
  files, sub-item level metadata scanning is available but **sub-item level lineage isn't supported**."

Purview's lineage is bounded too: Power BI artefacts ("Dataflow -> Dataset -> Report -> Dashboard") and
external assets — only Azure SQL Database, Blob Storage, ADLS Gen1 and Gen2 — with column-level lineage
"only when using Azure SQL Database as source" and "not captured when you use dynamic M query
parameters". It buys cross-workspace edges and a queryable graph, not column lineage for a lakehouse.

### 4. Labels: where this note stops

Taxonomy, licensing, inheritance, protection policies and the Git/deployment-pipeline gaps are settled
in [`sensitivity-labels-lifecycle.md`](sensitivity-labels-lifecycle.md). Two boundaries belong here: the
direction is one-way (Fabric reads and displays labels; nothing set in Fabric becomes a label
definition), and one correction to that note's automation surface. It says a label "cannot be added to
an existing non-Power BI item over the Fabric API at all"; `admin/swagger.json` at commit `3f8600f` now
has `POST /items/bulkSetLabels` (`Labels_BulkSetLabels`) — set labels on Fabric items "such as lakehouses
and reports", 25 requests/hour, 2,000 items per request. The conclusion holds: its identity table reads
Service principal and managed identities **No**, and it has no Learn page (the generated URL 404s on
2026-11-12). For automation, labels remain human-only.

### 5. Endorsement and ownership: the two facts only a person can set

**Endorsement** is **Promoted**, **Certified**, **Master data**. Promoted is self-service ("Any user
with write permissions on an item can promote it"); Certified is "only users specified by a Fabric
administrator"; Master data likewise, on items that contain data (endorsement-overview, 2024-07-11).
There is **no write operation** anywhere: code search of the spec repo for `endorse`/`Endorsement`
returns 0 results on 2026-11-12, and no `Item` schema has the field. It is declared, never inferred, and
readable in bulk only through the scanner API.

**Ownership** is displayed and returned but never settable. The Admin `Item` schema documents
`creatorPrincipal` as "The item's owner"; the catalogue shows "the item owner or contact"; no operation
read sets either, and whether Owner means creator, Power BI contact or `defaultIdentity` is **not
established**. Treat ownership as who created the item plus a contact list, not a governed field.

### 6. Automation surface, checked against the specs

Census at commit `3f8600f` (2026-11-10): **0** operations mentioning `endorse`/`endorsement`, **0**
lineage operations — the only "lineage" string in 61 groups is lakehouse prose about materialized lake
view schedules.

| Governance fact | Route | Verified state |
| --- | --- | --- |
| Lineage edges | — | Portal only: workspace lineage view, item **Lineage** tab, impact analysis |
| Lineage after a scan | Purview Data Map `Lineage`: `Get`, `Get By Unique Attribute`, `Get Next Page` | Enterprise Purview; read-only view of scanned edges |
| Catalogue discovery | `POST /v1/catalog/search` (`Catalog_Search`) | Preview; `Catalog.Read.All`; SP **Yes**; 50/min; **no** endorsement/sensitivity/owner/refresh |
| Label on one item | `GET /v1/workspaces/{workspaceId}/items/{itemId}` → `sensitivityLabel.id` | Core; SP **Yes**; also on `List Items` |
| Label and endorsement in bulk | `GetScanResult` → `sensitivityLabel`, `endorsementDetails`, `configuredBy` | Power BI artefact collections only; 500/hour; kept 24h |
| Set a label, Fabric items | `POST /v1/admin/items/bulkSetLabels` | SP **No**; 25/hour; unpublished on Learn |
| Set a label, Power BI items | Power BI admin `setLabels` / `removeLabels` | 25/hour; dashboards, reports, datasets, dataflows |
| Tags | `POST /v1/workspaces/{workspaceId}/items/{itemId}/applyTags` (`Tags_ApplyTags`) | SP **Yes**; Contributor+; 25/min; `unapplyTags` removes |
| Description | `Update Item` (`PATCH`) | `displayName` and `description` only |
| Owner | `GET /v1/admin/items` → `creatorPrincipal` | Read-only; Preview; 10/min, 200/hour; no `sensitivityLabel` here |
| Endorsement, Govern aggregates | — | No endorsement write route; Govern has no documented API |

### 7. What a deployment design should do

- **Pipeline (every run):** set `description` and apply `tags` on every item — both have
  service-principal-capable write operations and both are what Govern measures. Pass
  `sensitivityLabelSettings` on `Create Item` only where a label is mandatory, knowing the default
  `ApplyOrFail` fails the create rather than shipping unlabelled.
- **Scheduled job (read-only):** nightly, join `Get Item`/`List Items` (label, tags),
  `GET /v1/admin/items` (owner) and `GetScanResult` where the estate is Power-BI-heavy (endorsement,
  `certifiedBy`); report unlabelled, undescribed, unendorsed and ownerless items as warnings. If a
  Purview account exists, monitor its scan schedule; never drive it from the pipeline.
- **Human:** endorsement of all three kinds, any change of owner or contact, labels on existing items,
  the label taxonomy, and the decision that "unlabelled target workspace" is an accepted state.

## What this settles

| Emitted automatically | Automatable with effort | Human-only |
| --- | --- | --- |
| Workspace lineage view (item-level, in-workspace plus one hop upstream) | Description; tags (`applyTags`) | Endorsement: Promoted, Certified, Master data |
| Catalogue columns for owner, refresh, endorsement, sensitivity — as a view | Label at create; label audit via `Get Item` / `GetScanResult` | Ownership / contact |
| Govern insights over Admin Monitoring Storage, refreshed daily | Purview scan (registration, tenant settings, schedule, paid account) | Labels on existing items, and the label taxonomy |
| Item-level edges into Purview, once scanned | Purview `Lineage` reads after a scan | Cross-workspace downstream edges (no API, no export) |

**The thing teams believe is automatic and is not: lineage.** "Every workspace automatically has a
lineage view" reads like a promise about the estate; it is a promise about one workspace. Downstream
items elsewhere are never drawn, upstream stops after one hop, the graph is item-level, and no operation
in 835 Fabric REST operations returns an edge. A team treating the graph as its dependency map learns on
the first cross-workspace change that the map is a Purview scan result someone must configure and pay for.

## What this does not establish

- Per-item-type lineage coverage; the page says "all the items" without a table, and whether
  column-level lineage exists anywhere in Fabric's own view is not stated either way.
- Whether non-Power BI Fabric items appear in `GetScanResult` (`WorkspaceInfo` lists only reports,
  dashboards, datasets, dataflows and datamarts, while the overview claims "all … Fabric items"), and
  whether `sensitivityLabelSettings` is honoured for a service-principal `Create Item` of every type.
- What the catalogue's **Owner** resolves to, or any non-REST route that sets one.
- Whether Govern's insights are reachable outside the generated semantic model, which is read-only for
  data agents.
- Purview's billing meter for a Fabric tenant scan — only that an account is required and automated
  scans are Enterprise.

## Sources

| Source | What it was used for |
| --- | --- |
| [Lineage in Fabric](https://learn.microsoft.com/en-us/fabric/governance/lineage) (2023-11-06) and [Impact analysis](https://learn.microsoft.com/en-us/fabric/governance/impact-analysis) (2023-05-23) | Automatic per workspace; one-hop upstream; no downstream cross-workspace; Viewer; Get Data caveat; "Limited access" |
| [Catalog overview](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-overview) and [Govern](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-govern) (2026-08-26) | Explore/Govern/Secure split; insights over Admin Monitoring Storage; coverage metrics; permission-dependent entries; Private Link limit |
| [Explore tab](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-explore) and [Item details](https://learn.microsoft.com/en-us/fabric/governance/onelake-catalog-item-details) (2026-10-08) | Owner / Refreshed / Endorsement / Sensitivity columns; "item owner or contact"; Lineage tab |
| [Catalog – Search](https://learn.microsoft.com/en-us/rest/api/fabric/core/catalog/search) (updated 2026-11-11) | Endpoint, preview, scopes, SP support, returned fields, throttling |
| [Get Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/get-item) and [List Items (Admin)](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-items) (updated 2026-11-11) | `Item` schemas: `sensitivityLabel`, `tags`, `creatorPrincipal` as "The item's owner"; no endorsement field |
| [Metadata scanning](https://learn.microsoft.com/en-us/fabric/governance/metadata-scanning-overview) (2025-06-10) and [setup](https://learn.microsoft.com/en-us/fabric/admin/metadata-scanning-setup) (2023-11-02) | Scanner API list; owner/label/tags/endorsement extraction; the two gating settings |
| [GetScanResult](https://learn.microsoft.com/en-us/rest/api/power-bi/admin/workspace-info-get-scan-result) (updated 2026-05-18) | `EndorsementDetails`, `SensitivityLabel`, `configuredBy`; 24h retention; 500/hour |
| [Fabric tenant in Purview](https://learn.microsoft.com/en-us/purview/register-scan-fabric-tenant) (2026-04-28) | Pull model, prerequisites, identity options, tenant-setting checklist, item-type table, item-level-only limit |
| [Power BI lineage into Purview](https://learn.microsoft.com/en-us/purview/data-map-lineage-power-bi) (2025-05-01) | "leverages the scanner API"; artefact and external-source limits; Azure-SQL-only column lineage |
| [Purview free version](https://learn.microsoft.com/en-us/purview/data-governance-free-version) (2024-09-24) and [Data Map – Lineage](https://learn.microsoft.com/en-us/rest/api/purview/datamapdataplane/lineage) (2023-09-01) | Automated hybrid scans are Enterprise; `Get` / `Get By Unique Attribute` / `Get Next Page` |
| [Endorsement overview](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) (2024-07-11) | Three badges; who may grant each; eligible types |
| [fabric-rest-api-specs `admin/swagger.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/admin/swagger.json) and [`platform/swagger.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/platform/swagger.json) (`3f8600f`, read 2026-11-12) | `Labels_BulkSetLabels` limits and SP **No**; `Tags_ApplyTags`; zero endorse and lineage operations |
| [Create Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item) and [Update Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/update-item) (updated 2026-11-11) | `sensitivityLabelSettings` at create; update limited to `displayName`/`description` |

# What is the actual shape and size of the Fabric REST API surface, and which parts of it are deployment-relevant?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's API client and permission run-book; the "Fabric REST" row of the ADR 0003 boundary table. Sibling notes: [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) (which item types deploy), [`terraform-provider-surface.md`](terraform-provider-surface.md) (the same question for Terraform).

## Short answer

**835 operations across 61 groups**, read from `microsoft/fabric-rest-api-specs` at commit `3f8600f9cbe3105b91015db31a6cd96915eeebd4` (branch `main`, committed 2026-11-10T22:36:27Z). Every spec declares `host: api.fabric.microsoft.com`; 60 use `basePath: /v1` and one (`admin`) uses `/v1/admin`. The specs are **not** organised by workload — there is no Data Engineering, Data Factory or Power BI group. They are one group per item type plus `platform` (published on Learn as **Core**) and `admin`, and Learn's reference agrees group-by-group except for four groups. **434 operations** fall into the deployment-relevant families below (286 write, 148 read), but a pipeline that creates, binds, deploys, runs and audits needs about **24** of them.

## Detail

### 1. The groups, and how they were counted

**Method.** Read the repo tree (`.../git/trees/<sha>?recursive=1`): 1,349 blobs, 62 `swagger.json` files across 61 directories. For each file I parsed the JSON and counted `paths` × methods in `{get, put, post, patch, delete}`; no spec uses `head` or `options`. I excluded `sqlEndpoint/swagger_refreshMetadata.json`, a 1-operation partial that repeats `POST /sqlEndpoints/{sqlEndpointId}/refreshMetadata` from the full file — hence **835 as written** (836 counting it). Cross-check: `learn.microsoft.com/en-us/rest/api/fabric/toc.json` has 60 groups / 845 operation pages; counting `leaves − sub-group overview pages` reproduces the spec count exactly in **57 of 61** groups. The four exceptions are stated after the table.

| Cross-cutting group | Ops | Learn group | Ops |
| --- | --- | --- | --- |
| `platform/swagger.json` (`/v1`) | 187 | **Core** (same ops) | 187 |
| `admin/swagger.json` (`/v1/admin`) | 60 | Admin | 60 |

Item-type groups, ops per group (`swagger.json` each):

| Group | Ops | Group | Ops | Group | Ops |
| --- | --- | --- | --- | --- | --- |
| dataAgent | 41 | lakehouse | 23 | operationsAgent | 7 |
| apacheAirflowJob | 26 | warehouse | 19 | orgApp | 7 |
| environment | 31 | eventstream | 18 | orgAppAudience | 7 |
| copyJob | 16 | policySet | 16 | paginatedReport | 7 |
| spark | 16 | dataPipeline | 15 | plan | 7 |
| dataflow | 15 | mlModel | 15 | report | 7 |
| sqlDatabase | 13 | mirroredCatalog | 12 | semanticModel | 8 |
| notebook | 12 | mirroredDatabase | 11 | share | 7 |
| kqlDatabase | 11 | sparkjobdefinition | 11 | shareSubscription | 5 |
| mirroredAzureDatabricksCatalog | 11 | graphModel | 10 | snowflakeDatabase | 7 |
| dataBuildToolJob | 9 | monitoring | 9 | userDataFunction | 7 |
| reflex | 8 | eventhouse | 7 | variableLibrary | 7 |
| anomalyDetector | 7 | eventSchemaSet | 7 | warehouseSnapshot | 5 |
| appBackend | 5 | graphQLApi | 7 | mlExperiment | 5 |
| graphQuerySet | 7 | kqlDashboard | 7 | **dashboard** | **1** |
| kqlQueryset | 7 | map | 7 | **datamart** | **1** |
| mountedDataFactory | 7 | ontology | 7 | **mirroredWarehouse** | **1** |
| deploymentPlan | 7 | digitalTwinBuilder | 7 | **realTimeIntelligence** | **1** |
| digitalTwinBuilderFlow | 7 | cosmosDbDatabase | 7 | azureDatabricksStorage | 7 |
| customStreamConnector | 7 | sqlEndpoint | 6 | | |

*(The bolded four are list-only or single-purpose; see §5.)*

**Where the specs and Learn disagree.** `platform` is published as **Core** (Learn hrefs are `core/*`). `share` (7) and `shareSubscription` (5) have **no Learn group** — they are OneLake data-sharing routes under `/workspaces/{workspaceId}/shares` rather than `/items`, and are effectively undocumented. `dataAgent` is 41 in the spec and 42 on Learn. Conversely Learn carries **Workload Development** (24 pages = 20 operations) with no spec directory: those are APIs *you implement* for a custom workload, not APIs you call.

### 2. Total operations

- **836 operation definitions** in 62 files; **835** after dropping the duplicated `sqlEndpoint` partial. That is the count I would defend.
- **818 distinct `METHOD path` strings.** The 18 collisions are 16 admin-vs-Core pairs that are genuinely different operations distinguished only by `basePath` (`GET /v1/admin/workspaces` vs `GET /v1/workspaces`, the connection and role-assignment reads, `GET /tags`, `GET /domains`), 2 `policySet` activate/deactivate pairs, and the 1 partial above. So the collision count is a text artefact, not duplicate API surface.
- 98 of the 835 are `getDefinition`/`updateDefinition` (49 pairs) and 2 more are `bulkExportDefinitions`/`bulkImportDefinitions`.

### 3. The deployment-relevant subset

`{ws}` = `workspaces/{workspaceId}`, `{item}` = `items/{itemId}`. All paths are under `/v1` unless stated.

| Family | Method and path | What it does | Class |
| --- | --- | --- | --- |
| Workspaces | `POST /workspaces` (`capacityId`, `domainId` optional in body) | create the container | administration |
| Workspaces | `POST /{ws}/roleAssignments` · `PATCH`/`DELETE …/{workspaceRoleAssignmentId}` | grant/change Admin·Member·Contributor·Viewer | administration |
| Workspaces | `POST /{ws}/assignToCapacity` · `assignToDomain` | move container | administration |
| Items | `POST /{ws}/items` (`definition`, `creationPayload`, `folderId`) | create item, optionally with definition | deployable content |
| Items | `POST /{ws}/{item}/getDefinition` (body/query `format`) | read part-based definition | deployable content |
| Items | `POST /{ws}/{item}/updateDefinition` (`updateMetadata`) | overwrite definition | deployable content |
| Items | `POST /{ws}/items/bulkExportDefinitions` · `bulkImportDefinitions` | read/write definitions in bulk | deployable content |
| Items | 53 type-specific `POST /{ws}/<plural>` (`/lakehouses`, `/notebooks`, …) | the per-type route to the same create | deployable content |
| Git | `POST /{ws}/git/connect` · `initializeConnection` · `updateFromGit` · `commitToGit` | bind branch, pull, push | deployable content |
| Git | `GET /{ws}/git/status` · `GET /{ws}/git/connection` | what differs from the branch | read-only |
| Git | `POST /{ws}/git/disconnect` · `PATCH /git/myGitCredentials` · `git/connectionSettings` · `git/workspaceRelations` | credential and relation plumbing | administration |
| Deployment pipelines | `POST /deploymentPipelines` · `PATCH`/`DELETE …/{deploymentPipelineId}` · `stages/{stageId}/assignWorkspace` | pipeline and stage topology | administration |
| Deployment pipelines | `POST /deploymentPipelines/{id}/deploy` | promote items between stages (LRO) | deployable content |
| Deployment pipelines | `GET …/{id}/operations/{operationId}` | per-pipeline LRO status | read-only |
| Connections | `POST /connections` · `PATCH`/`DELETE …/{connectionId}` · `POST …/testConnection` | cloud/on-prem connections | administration |
| Connections | `POST /connections/{id}/roleAssignments` (+`GET`/`PATCH`/`DELETE`) | who may use a connection | administration |
| Gateways | `POST /gateways` · `members` · `restart` · `shutdown` · `checkStatus` | gateway lifecycle | administration |
| OneLake roles | `GET`/`PUT`/`POST`/`DELETE /{ws}/{item}/dataAccessRoles[/{roleName}]` | OneLake data access roles (PUT takes `dryRun`) | administration |
| Jobs | `POST /{ws}/{item}/jobs/{jobType}/instances` | run on demand — returns **only** 202 | job execution |
| Jobs | `GET …/jobs/instances/{jobInstanceId}` · `GET …/jobs/instances` · `POST …/cancel` | poll, list, cancel | job execution / read |
| Schedules | `GET`/`POST`/`PATCH`/`DELETE /{ws}/{item}/jobs/{jobType}/schedules[/{scheduleId}]` | recurring runs | job execution |
| Tenant settings | `GET /admin/tenantsettings` · `POST /admin/tenantsettings/{tenantSettingName}/update` | read/flip one setting | read-only / administration |
| Domains | `POST /admin/domains` · `assignWorkspaces` · `roleAssignments/bulkAssign` | tenant governance grouping | administration |
| Domains | `GET /domains` · `GET /domains/{domainId}` | the Core-side read | read-only |
| Capacities | `GET /capacities` · `GET /capacities/{capacityId}` | discover the GUID and state | read-only |
| Capacities | `GET`/`PATCH /capacities/{capacityId}/overageConfiguration` · `surgeProtection` (+ blocked/mission-critical actors) | capacity behaviour, not lifecycle | administration |
| Admin reads | `GET /admin/workspaces` · `/admin/items` · `/admin/users/{userId}/access` · `/{ws}/users` · `/{item}/users` · `/admin/workspaces/discoverGitConnections` | inventory and audit | read-only |

Measured size of this subset: **434 operations** (286 non-`GET`, 148 `GET`), assigning each operation to the first family it matches so shared routes such as delegated tenant-setting overrides count once. The other 401 operations are item-level routes beyond definition read/write, shortcuts, folders, tags, networking and encryption policies, external data shares, catalog search, relations, item identities, recoverable items, and the agents' and environments' sub-resources.

### 4. Minimum endpoint set for this project

Ordered as you would implement it. Every `202` means "poll `Location`, honour `Retry-After`".

1. `GET /v1/capacities` — resolve the F SKU name to the **capacity GUID** and confirm state `Active` (the AzureRM resource ID is not accepted anywhere).
2. `POST /v1/workspaces` with `{displayName, capacityId, domainId}` — capacity and domain are body fields, so no separate assign call is needed.
3. `POST /v1/workspaces/{workspaceId}/roleAssignments` per principal (`principal.id`, `principal.type`, `role`).
4. `POST /v1/workspaces/{workspaceId}/git/connect` (`gitProviderDetails`, `myGitCredentials.source`) then `POST …/git/initializeConnection` or `POST …/git/updateFromGit` (`remoteCommitHash`) to materialise the branch.
5. `POST /v1/workspaces/{workspaceId}/items` with `definition {format, parts}` — one call per item; the 53 per-type routes are equivalent.
6. `POST …/items/{itemId}/getDefinition` — the only way to diff deployed state; there is no "read definition back" on the list endpoint.
7. `POST …/items/{itemId}/updateDefinition` — redeploy; `updateMetadata=false` leaves display name and description alone.
8. `POST …/items/{itemId}/jobs/{jobType}/instances` — run; then `GET …/jobs/instances/{jobInstanceId}` until terminal.
9. `POST …/items/{itemId}/jobs/{jobType}/schedules` — only where the schedule is part of the deployment.
10. `GET /v1/admin/workspaces/{workspaceId}/users` and `GET /v1/admin/items/{itemId}/users` — effective access for audit.
11. `GET /v1/admin/users/{userId}/access` — per-principal access, the inverse query audit actually asks.
12. `POST /v1/admin/tenantsettings/{tenantSettingName}/update` — only the settings the pipeline depends on, from a separate gated root.
13. `POST …/git/commitToGit` (`mode`, `workspaceHead`) — only if the repo is downstream of a portal-edited workspace.
14. `GET /v1/operations/{operationId}` and `/result` — the generic poller behind steps 5–7.

### 5. Operations that exist but are unusable headlessly

| Reason | Evidence |
| --- | --- |
| **List-only** | `dashboard` (1 op: `GET /{ws}/dashboards`), `datamart` (1), `mirroredWarehouse` (1) — no create, get-by-id, update or delete exists to call. |
| **No definition payload** | 12 groups have **no** `getDefinition`/`updateDefinition`: `admin`, `appBackend`, `dashboard`, `datamart`, `mirroredWarehouse`, `mlExperiment`, `mlModel`, `realTimeIntelligence`, `shareSubscription`, `spark`, `sqlEndpoint`, `warehouseSnapshot`. `mlModel` (15 ops) and `mlExperiment` (5 ops) can be created and updated but never read back as content — it corroborates the sibling note's "ML model/experiment are not round-trippable". |
| **Service principal "No"** | **58 operations** carry `| Service principal and Managed identities | No |` in their own identity table: all 7 `anomalyDetector`, all 7 `digitalTwinBuilder`, 7 `eventSchemaSet`, 7 `operationsAgent`, 7 `userDataFunction`, 5 `mlModel`, 5 `mlExperiment`, the 4 `dataflow` job/schedule runs, 3 `dataAgent` feedback routes, `GET /{ws}/dashboards`+`datamarts`+`mirroredWarehouses`+`sqlEndpoints`, and `POST /admin/items/bulkSetLabels`/`bulkRemoveLabels`. |
| **Beta-gated** | **48 paths** require `?beta=true`, with the spec's own warning: "This API is part of a Beta release … not recommended for production use." Includes `items/{itemId}/relations/*`, `items/{itemId}/identities/default/assign`, `lakehouses/…/tables/{tableName}/load`, `capacities/{capacityId}/spark/pools`, `graphModels/{id}/executeQuery`, `admin/policySets/active`. `environment` ships parallel `?beta=true` and `?beta=false` paths for the same operation — proof both variants are live simultaneously. |
| **Admin group restriction** | Anything under `/v1/admin` needs "a Fabric administrator or authenticate using a service principal" **plus** the admin-API tenant settings and an allowed security group; tenant settings are additionally capped at "Maximum 25 requests per minute". |
| **GA call, beta sub-feature** | `POST /deploymentPipelines/{id}/deploy` is GA, but accepting a *deployment plan* in its body is beta: "To use deployment plan support, callers must specify `true` as the value for the query parameter `beta`." |

### 6. Conventions worth knowing

- **Pagination.** Responses carry `value` plus `continuationToken` and `continuationUri`; both are *removed* (not nulled) when exhausted, so loop on presence. Pass either back — as `?continuationToken=` or by following the URI. `common/definitions.json` `PaginatedResponse` is the shared shape.
- **Long-running operations.** `200`/`201` with a body, or **`202` with an empty body** plus `Location`, `x-ms-operation-id` and `Retry-After`. Poll `GET /v1/operations/{operationId}` for `{status, percentComplete, error}` and `…/result` for the payload. 214 operations declare a 202; 201 of them document both `Location` and `Retry-After`. **Exception:** `POST …/jobs/{jobType}/instances` returns *only* 202 and is **not** tagged as an LRO — poll the job instance, never `/operations`.
- **Throttling.** Three identity-scoped quotas on a fixed 60-second window, replenished all at once: **Platform 500 calls/min, Job Scheduler 200, Long-Running operations 500**. They are independent, so exhausting job runs does not block workspace calls. 429 carries two distinct `errorCode`s — `RequestBlocked` (rate; honour `Retry-After`) and `CapacityLimitExceeded` (compute; retrying immediately will not help). Per-operation limits still apply on top: 140 descriptions repeat the Platform row, and the common item-level "API limit" is **200** or **50 calls/min** (49 and 71 operations respectively); admin tenant settings are **25/min**.
- **Error shape.** `errorCode` and `message` are required; `requestId` (uuid), `isRetriable`, `moreDetails[]`, `relatedResource`, `parameters[]` are optional. Log `requestId` — it is the only handle support accepts.
- **No `beta` path prefix.** Beta is a **query parameter**, `?beta=true`, on the 48 paths above. There is no `/beta/…` route and no separate beta host, so a beta dependency is invisible in a URL prefix and has to be tracked per call.
- **Items are two-layer.** Shell (`POST /items`: `displayName`, `type`) and content (`definition.parts[]`) are separate payloads, and `getDefinition` is a `POST` because the requested `format` travels in the body/query. `updateDefinition` replaces the whole part set; there is no per-part patch.
- **Caution.** `admin/swagger.json` records workspace restore as `GET /workspaces/{workspaceId}/restore`. A restore that mutates state behind `GET` is almost certainly a spec error — do not generate a client from that operation without checking the Learn page first.

### 7. What the specs do not cover

- **Data plane.** OneLake DFS (`onelake.dfs.fabric.microsoft.com`), T-SQL against warehouse/SQL database, KQL against eventhouse, and XMLA against semantic models are all outside `api.fabric.microsoft.com/v1` and absent from this repo. Item definitions move *metadata*; table rows and DDL do not travel through these APIs.
- **ARM.** Capacity create, suspend/resume and scale are `Microsoft.Fabric/capacities` operations in Azure Resource Manager, not `/v1`. The Fabric side offers only `GET /capacities`, `GET /capacities/{id}` and the overage/surge-protection configuration — **there is no `POST /capacities`**.
- **Power BI legacy.** The `api.powerbi.com/v1.0/myorg` family (datasets, refresh, admin scanner, dashboards, paginated reports) is a different surface; the Fabric `dashboard`/`datamart` groups here are read-only shims over the same objects.
- **Inbound workload APIs.** Learn's Workload Development group (20 operations: item lifecycle callbacks, job callbacks, endpoint resolution) is what a custom workload must *implement*; nothing calls it from a pipeline.
- **Clients and servers.** Fabric MCP servers, the Fabric CLI and `fabric-cicd` are clients over this surface, not additional surface.

## What this settles

- **Surface: 835 operations, 61 groups, 62 spec files, 818 distinct `METHOD path`.** Read at `3f8600f`, dated 2026-11-12; re-count before quoting the number, since the repo publishes on most weekdays ("Updating swagger files" was the head commit).
- **Deployment-relevant subset: 434 operations** across the thirteen families in §3 — 286 writing, 148 reading. That is just over half the surface, because most item types ship full CRUD.
- **A working pipeline needs ~24 calls**, listed in §4; everything else is either an alternative route to the same object or an administration nicety.
- **Not available to an unattended pipeline, despite appearing in the API:**
  - `Dashboard`, `Datamart`, `MirroredWarehouse` — list-only, no create.
  - `MLModel`, `MLExperiment`, `SQLEndpoint`, `AppBackend`, `WarehouseSnapshot`, `Spark`, `ShareSubscription` — no definition payload, so nothing to deploy or diff.
  - `AnomalyDetector`, `DigitalTwinBuilder`, `EventSchemaSet`, `OperationsAgent`, `UserDataFunction` — service principals explicitly unsupported, all seven operations each.
  - 48 beta-param paths, including item relations, item identity assignment and lakehouse table load.
  - Everything under `/v1/admin` without the admin-API tenant settings *and* an allowed security group.
  - `POST /deploymentPipelines/{id}/deploy` with a deployment plan (the plain deploy is fine).

## What this does not establish

- Whether the 58 "Service principal: No" operations fail identically in practice, or only for some calls — the table is the spec's claim, not a measurement.
- Whether `share`/`shareSubscription` are GA, preview or abandoned. They have no Learn group, no `?beta` marker and no entry in the sibling notes' item-type tables.
- Whether the `GET …/restore` operation works at all, and whether the 2 `policySet` collisions are one implementation or two.
- The real per-operation rate limits for the ~690 operations that do not restate a throttling table; only the article's three unified quotas are documented for them.
- Whether Learn's extra `dataAgent` operation (42 vs 41) is a page that has not reached the spec, or a spec omission.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`microsoft/fabric-rest-api-specs` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/tree/3f8600f9cbe3105b91015db31a6cd96915eeebd4) | tree (1,349 blobs), 62 `swagger.json`, all 835 operation counts, `host`/`basePath`, per-family membership | commit 2026-11-10, read 2026-11-12 |
| [`platform/swagger.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/platform/swagger.json) | the 187 Core operations, item/Git/deploy/DAR/job routes, 202 + header inventory, beta notes | read 2026-11-12 |
| [`admin/swagger.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/admin/swagger.json) | the 60 admin operations, `/v1/admin`, tenant-setting update, admin reads | read 2026-11-12 |
| [`common/definitions.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/common/definitions.json) | `ErrorResponse` / `ErrorResponseDetails`, `PaginatedResponse` | read 2026-11-12 |
| [`platform/definitions/platform.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/platform/definitions/platform.json) | `CreateWorkspaceRequest` (`capacityId`, `domainId`), `CreateItemRequest` (`definition`), `ItemDefinition` | read 2026-11-12 |
| [REST reference toc](https://learn.microsoft.com/en-us/rest/api/fabric/toc.json) | the 60 Learn groups, 845 pages, Core = platform, Workload Development | read 2026-11-12 |
| [Throttling](https://learn.microsoft.com/en-us/rest/api/fabric/articles/throttling) | three unified quotas 500/200/500, 60-second fixed window, `RequestBlocked` vs `CapacityLimitExceeded` | ms.date 2026-08-14, upd. 2026-09-24 |
| [Long running operation](https://learn.microsoft.com/en-us/rest/api/fabric/articles/long-running-operation) | 202 + `Location`/`x-ms-operation-id`/`Retry-After`, poll state then result | ms.date 2025-03-14, upd. 2025-07-02 |
| [Pagination](https://learn.microsoft.com/en-us/rest/api/fabric/articles/pagination) | `continuationToken`/`continuationUri`, removal when exhausted | upd. 2025-07-02 |
| [Identity support](https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support) | SP/MI tenant setting — still worded "**Service principals can use Fabric APIs**", the stale name the Terraform note also records | upd. 2026-04-08 |
| [List Tenant Settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings) / [Update Tenant Setting](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/update-tenant-setting) | 25 calls/min, `settingName` vocabulary, full error/`TenantSetting` schema | upd. 2026-09-15 |

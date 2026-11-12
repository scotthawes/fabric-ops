# Which Fabric runtime operations can be automated — running, scheduling, cancelling and controlling mirroring — as distinct from deploying definitions?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's operational run-book and anything in `docs/specs/` that assumes "deploy" ends the pipeline. Sibling notes: [`fabric-api-inventory.md`](fabric-api-inventory.md) (the whole surface), [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) (what watches the runs), [`../guides/automation-coverage.md`](../guides/automation-coverage.md) (verdicts per action).

## Short answer

Running, listing, cancelling and scheduling are a **single small API family** — six paths under `/v1/workspaces/{workspaceId}/items/{itemId}/jobs/…` — and the spec marks all of them service-principal capable. Scheduling is genuinely declarative (a `Cron`/`Daily`/`Weekly`/`Monthly` resource, and Terraform's `fabric_item_job_scheduler` covers it), but the schedule is owned by a *person*, runs as that person, and auto-disables itself after repeated failure. Mirroring is a separate pair of verbs (`startMirroring`/`stopMirroring`) with a read-only status enum, and **semantic-model refresh is not on this API at all** — it stays on `api.powerbi.com`. The hard limits are cancellation (asynchronous, and the docs say nothing about partial notebook output) and dependency ordering (only inside data pipelines, preview-only).

## Detail

Read against `microsoft/fabric-rest-api-specs` at commit `3f8600f9cbe3105b91015db31a6cd96915eeebd4` (2026-11-10), plus Learn pages dated in Sources.

### 1. Job types

`jobType` is a **free-form string path parameter**, not an enum: `platform/swagger.json` declares only `"name": "jobType" … "description": "Job type"`, and the run operation's documented error is `InvalidJobType`. Three separate vocabularies describe the same thing, and they do not agree:

| Source | Values | Coverage |
| --- | --- | --- |
| Spec path segments (`jobs/<segment>/instances`) | `execute`, `applyChanges`, `sparkjob`, `refreshMaterializedLakeViews`, `tableMaintenance`, `refreshGraph` | fixed per item type |
| Terraform `job_type` doc, v1.15.1 | `dataflow: {ApplyChanges, Execute}`; `datapipeline: {Execute}`; `lakehouse: {RefreshMaterializedLakeViews}` | the **only explicit enumeration**, three item types |
| `ItemJobEventLogs.JobType` (workspace monitoring) | `Data Pipeline`; `RunNotebook`, `RunNotebookInteractive`, `PipelineRunNotebook`, `SparkSecurityControl`; `TableMaintenance`, `TableLoad`, `LakehouseOperation`, `LivyBatch`, `LivySession`, `MaterializedLakeViews`; `SqlAnalyticsEndpoint`; `CopyJob`; `Refresh`, `Publish`; `DBTItem`; `MLExperimentRun`; `Algorithm`, `Load`, `Refresh`; `BuildTileset`; `SyncJob` | broadest list, telemetry spelling |

The generic examples use `DefaultJob`; the beta notebook route uses `jobs/execute`, and the notebook page calls the same run `RunNotebook`. **Do not infer one layer from another** — a value that works on the item-specific route (`execute`) is not necessarily the string the generic route accepts. There is no published mapping table: *could not establish* the accepted `jobType` string for every item type on `POST /items/{itemId}/jobs/{jobType}/instances`.

`invokeType` is the on-demand-versus-scheduled distinction: `Manual` or `Scheduled`. An on-demand run returns **only `202`** with `Location` and `Retry-After`, no body, and is **not tagged as a long-running operation** — poll the job instance, never `/v1/operations/{id}`. `executionData` is fixed per job type; `parameters` is "not broadly supported" and answers `FeatureNotAvailable` with "Parameter is not allowed for this item type or this item job type" where unsupported.

### 2. Run, list, get, cancel

| Operation (spec `operationId`) | Call | Returns |
| --- | --- | --- |
| `JobScheduler_RunOnDemandItemJob` | `POST /workspaces/{ws}/items/{item}/jobs/{jobType}/instances` | `202`, `Location`, `Retry-After` |
| `JobScheduler_ListItemJobInstances` | `GET /workspaces/{ws}/items/{item}/jobs/instances` | `ItemJobInstances`, pageable |
| `JobScheduler_GetItemJobInstance` | `GET /workspaces/{ws}/items/{item}/jobs/instances/{jobInstanceId}` | `ItemJobInstance` + `Retry-After` |
| `JobScheduler_CancelItemJobInstance` | `POST /workspaces/{ws}/items/{item}/jobs/instances/{jobInstanceId}/cancel` | `202`, `Location` |

States (`ItemJobStatus`): `NotStarted`, `InProgress`, `Completed`, `Failed`, `Cancelled`, `Deduped` — the last means "A job instance of the same job type is already running and this job instance is skipped". `failureReason` carries a full `ErrorResponse` when `Failed`. Instance fields: `id`, `itemId`, `jobType`, `invokeType`, `status`, `rootActivityId`, `startTimeUtc`, `endTimeUtc`.

Retention is a **count, not a window**: "Most items have a limit of 100 recently completed entities, and there is not [sic] limit for active entities." The Monitor hub shows the last five per item. No time-based expiry is documented — *could not establish*.

Cancel is a **request**: `202` with a `Location` header, and the only documented refusal is `JobAlreadyCompleted` ("Requested cancellation can not take be processed as job instance run has completed"). Cancelling needs *execute* permission, not write. What a cancelled notebook does with already-committed writes is **not documented — could not establish**; the only authoritative partial-work statement in this surface is for enhanced refresh, where `commitMode: partialBatch` means "the model might be empty or include only a subset of the data". Treat cancel as stop-the-rest with no rollback guarantee.

Ceilings that matter to an unattended caller: 100 concurrent jobs per item ("All jobs submitted beyond this number are automatically failed"), jobs terminated after 24 days, and 100 job submissions plus 100 Get Job requests per user per minute.

### 3. Scheduling

REST: `JobScheduler_ListItemSchedules` / `CreateItemSchedule` / `GetItemSchedule` / `UpdateItemSchedule` / `DeleteItemSchedule` on `/jobs/{jobType}/schedules[/{scheduleId}]`. Create returns `201` with `Location`; exceeds-limit answers `ScheduleExceedsLimit`.

`ScheduleConfig` requires `type`, `startDateTime`, `endDateTime`, `localTimeZoneId`, and is discriminated into exactly four shapes:

- `Cron` — `interval` in **minutes**, 1 to 5270400 (ten years).
- `Daily` — `times` in `hh:mm`, max 100 slots.
- `Weekly` — `times` plus `weekdays` (max 7).
- `Monthly` — `recurrence` 1–12, `times`, plus `occurrence` of `DayOfMonth` (`dayOfMonth` 1–31) or `OrdinalWeekday` (`weekIndex` `First`…`Fifth` + `weekday`).

Both timestamps are UTC and "must be in UTC"; the *times* are interpreted in `localTimeZoneId`, a **Windows** zone id ("Central Standard Time"), not IANA. A past `startDateTime` "will trigger a job instantly". An invalid date such as February 31 "will automatically skip to the month that includes the 31st day". Limits: 20 schedules per data pipeline and 20 per dataflow.

Terraform `fabric_item_job_scheduler` maps one-to-one: `workspace_id`, `item_id` and `job_type` are **ForceNew**, `enabled` and `configuration` are the mutable pair, `local_time_zone_id` defaults to `Central Standard Time`, and import is `"<WorkspaceID>/<ItemID>/<JobType>/<ScheduleID>"`. Because `job_type` is ForceNew, changing which job you schedule replaces the schedule rather than editing it.

**Survives redeployment?** Depends on the route, and only one half is documented. Learn: "Schedules are included when you deploy an item" (deployment pipelines) and "Schedules are stored in a `.schedules` file in your item definition" (Git integration), with the public API as the third path. Whether `POST …/updateDefinition` — which "replaces the whole part set" — preserves a schedule that is not in the payload is **not stated anywhere I could find**. Treat schedule re-creation as an explicit deploy step rather than an assumption.

**Ownership and auto-disable.** The schedule is owned by "the identity that created or last modified the schedule", tracked separately from the item; taking over the item "doesn't transfer ownership of its existing schedules", and a scheduled notebook runs as the schedule owner. After consecutive failures the platform "shuts down the scheduler and places it into an *auto-disabled* state… you must manually restart the scheduler through the UI, API, or CI/CD process"; the threshold "varies by item and is typically set to 10 consecutive failed runs". Separately, schedules "expire if a user doesn't log in to Fabric for 90 consecutive days".

### 4. Semantic-model refresh

The Fabric items/jobs API has **no semantic-model job**: `semanticModel/swagger.json` holds eight operations (list, create, get, patch, delete, `getDefinition`, `updateDefinition`, `bindConnection`) and no `jobs` path, and the six Core job paths are item-generic only. The Terraform enumeration omits it too. The current surface is the **Power BI legacy API** — `POST https://api.powerbi.com/v1.0/myorg/datasets/{datasetId}/refreshes`, or the `/groups/{groupId}/…` variant for a workspace.

- Async: `202` + `Location` whose last segment is the `requestId`; "the service accepts only one refresh operation at a time for a model", a second request gets `400`.
- History **is** readable: `GET /refreshes` returns 20–60 entries under a 3-day retention rule, with `refreshType` of `Scheduled`, `OnDemand`, `ViaApi`, `ViaXmlaEndpoint`, `ViaEnhancedApi` or `OnDemandTraining`.
- A failure programmatically is `status: "Failed"` plus `serviceExceptionJson`, e.g. `{"errorCode":"ModelRefreshFailed_CredentialsNotSpecified"}`; in-progress is `status: "Unknown"` with no `endTime`. Enhanced refresh adds `Cancelled` and `extendedStatus`.
- Cancel exists **only** for enhanced refresh: `DELETE /refreshes/{requestId}`. "You can't cancel scheduled or on-demand model refreshes that were triggered by selecting the refresh button in the portal", and those cannot be read by `requestId` either.
- The refresh *schedule* is a different object: `GET`/`PUT /datasets/{datasetId}/refreshSchedule` with `days`, `times`, `enabled`, `localTimeZoneId`, `notifyOption`; a service principal may only use `NoNotification`.

So: refresh is automatable and observable, but it is a second API host with a second auth audience (`https://api.powerbi.com`), and its schedule is not the job scheduler.

### 5. Mirroring

Database mirroring is the only mirrored item with lifecycle verbs (all service-principal capable, `MirroredDatabase.ReadWrite.All` or `Item.ReadWrite.All`):

| Operation | Call | Returns |
| --- | --- | --- |
| `Mirroring_StartMirroring` | `POST …/mirroredDatabases/{id}/startMirroring` | `200`, no body |
| `Mirroring_StopMirroring` | `POST …/mirroredDatabases/{id}/stopMirroring` | `200`, no body |
| `Mirroring_GetMirroringStatus` | `POST …/getMirroringStatus` | `{status, error}` — a **POST to read** |
| `Mirroring_GetTablesMirroringStatus` | `POST …/getTablesMirroringStatus` | per-table status + metrics |

Item status enum: `Initializing`, `Initialized`, `Starting`, `Running`, `Paused`, `Stopping`, `Stopped`, plus an `error` field ("Error is set if error happens in mirroring"). **There is no `Failed` item status** — failure is `Running` plus a populated `error`. Start is refused while `Initializing`. There is no pause or resume verb: `Paused` is what you observe, and Learn attributes it to pausing the capacity ("Replication is paused. It happens when you pause and resume the Fabric capacity"). The portal shows richer labels — `Running with warning`, `Failed`, `Paused` — that have **no documented API equivalent at item level**; table status is the finer signal: `Initialized`, `Snapshotting`, `Replicating`, `Reseeding`, `Stopped`, `Failed`.

**Metadata mirroring is a different item with a different API.** `mirroredCatalog` has `refreshCatalogMetadata` (an LRO) and a `GET …/mirroringStatus` whose state enum is only `Running`, `Stopped`, `Failed` with `lastSyncDateTime` and `error`. It has **no start/stop**. `mirroredAzureDatabricksCatalog` has neither, and the mirroring article says plainly: "These REST APIs don't apply to mirrored database from Azure Databricks."

To a monitoring job, a problematic mirror looks like **nothing at all**: mirroring creates no job instance, so the jobs API and the job scheduler never see it, `ItemJobEventLogs` has no mirroring row type, and a capacity pause produces `Paused` with no error and no failed run. Detection is polling `getMirroringStatus`, or the `MirroredDatabaseTableExecution` log table in workspace monitoring. Definition edits are also fenced by status: the source connection, database and default schema "can only be updated when **Get mirroring status** API returns `Initialized`/`Stopped`".

### 6. Ordering and dependencies

The item job scheduler has **no dependency concept**: `ScheduleConfig` carries only time fields, so no schedule can be told to run after another item. Ordering exists in three places, all inside Fabric pipelines:

1. **Run conditions (preview)** on a pipeline — types `Custom`, `Data availability`, `Window coverage`. `Custom` waits for named upstream pipelines matched on a **run dimension** (date, region+batch, partition); multiple upstreams use "all-required matching behaviour"; `Data availability` waits for files in OneLake or ADLS; `Window coverage` waits for successful upstream interval windows and passes `windowStartTime`/`windowEndTime` downstream. Cross-workspace works with access on both sides.
2. **`Invoke pipeline` activity** — one pipeline calls another as an activity, so success/failure branching is inside the caller.
3. **Event-based runs** — triggers on file, job and workspace events, implemented through Eventstream and Activator; Activator's documented action list includes "run a Fabric item". That is the only general "after item X finishes, do Y" mechanism that crosses item types.

For anything else — notebook finishes, now refresh the semantic model — there is **no Fabric-native edge**. The external pipeline must sequence it: run, poll the instance to a terminal state, then call refresh. Run conditions do not span a notebook and a semantic model, and the job scheduler cannot express it.

### 7. What this means for automation

**Safe unattended, every run:** on-demand run of an idempotent item, `GET` the instance, `GET` the instance list, schedule CRUD against a known `jobType`, read refresh history, read mirroring status. All are service-principal capable, all are idempotent reads or additive writes.

**Needs a guard (approval, or a check before acting):** `cancel` (only `JobAlreadyCompleted` protects you; partial work is undefined); `stopMirroring` (halts ingestion and the delta history stops advancing); `startMirroring` (resumes load on the source); `refresh` (capacity-consuming, eight requests/day on shared capacity, one at a time); creating a schedule (it will run as *your* identity, so a service principal's schedule runs as that principal, with that principal's data access); re-enabling an auto-disabled scheduler (restarting it without fixing the cause just burns ten more failures).

**No route:** a cross-item dependency edge, a pause/resume for mirroring, cancel-by-`requestId` for a standard refresh, and a documented way to stop a notebook without leaving whatever it already wrote. Interactive notebook sessions are not job instances either — the API cancels a `jobInstanceId`, and `livySessions` is read-only.

**Asynchronous, returns before the work finishes:** `POST …/jobs/{jobType}/instances` (`202`), the `cancel` (`202`), refresh (`202`), `refreshCatalogMetadata` (LRO), and the *effect* of `startMirroring`/`stopMirroring` (immediate `200`, status moves through `Starting`/`Stopping` later). Only `POST /v1/operations/{operationId}`-style LROs are pollable that way; job instances and refresh `requestId`s are not.

## What this settles

| Runtime operation | Automatable | Mechanism |
| --- | :-: | --- |
| Run an item job on demand | **Yes** | `POST …/jobs/{jobType}/instances`, then poll the instance |
| List / get job instances | **Yes** | `GET …/jobs/instances[/{id}]`, 100 completed retained |
| Cancel a job instance | **Partial** | `POST …/cancel`, `202`; refusal only `JobAlreadyCompleted`; no rollback promise |
| Create / update / delete a schedule | **Yes** | `…/jobs/{jobType}/schedules`, or `fabric_item_job_scheduler` |
| Disable a schedule | **Yes** | `PATCH` `enabled: false`, or `enabled = false` in Terraform |
| Predict that a schedule survives a definition redeploy | **Partial** | Deployment pipelines and Git carry it (`.schedules`); `updateDefinition` behaviour unstated |
| Recover an auto-disabled scheduler | **Partial** | Restart via UI/API/CI-CD, but the cause must be fixed first |
| Read semantic-model refresh history | **Yes** | `GET api.powerbi.com/…/datasets/{id}/refreshes` |
| Trigger a semantic-model refresh | **Yes** | `POST …/refreshes` (`202`, one at a time) |
| Cancel a refresh | **Partial** | `DELETE /refreshes/{requestId}`, enhanced refresh only |
| Read / set a refresh schedule | **Yes** | `GET`/`PUT …/refreshSchedule`, separate from the job scheduler |
| Start / stop database mirroring | **Partial** | `POST startMirroring` / `stopMirroring`, `200`, effect later |
| Read mirroring status | **Yes** | `POST getMirroringStatus` / `getTablesMirroringStatus` |
| Start / stop metadata mirroring | **No** | Only `refreshCatalogMetadata`; no start/stop exists |
| Order one item after another | **Partial** | Pipeline run conditions (preview) / `Invoke pipeline` / event triggers; otherwise external |
| Enumerate every run in a workspace | **No** | No tenant- or workspace-wide run endpoint; per-instance, or monitoring logs |

**The three that most often surprise people**

1. **The run call is not an LRO.** `POST …/jobs/{jobType}/instances` returns `202` with no body and is not tagged long-running, so a client built around `/v1/operations/{operationId}` polls the wrong resource forever. The `Location` header *is* the instance URL.
2. **A schedule belongs to a person, not to the item.** It runs as the identity that created or last modified it, is not transferred by item takeover, disappears from use after 90 days without a Fabric login, and stops itself after roughly ten consecutive failures — with no failed-run alert unless someone typed an address into **Failure notifications**.
3. **Mirroring is invisible to the job surface.** No job instance, no `Failed` item status (the status stays `Running` and `error` is set), and a paused capacity reads as `Paused` with no error. A monitoring job that only watches job instances reports a dead mirror as healthy.

## What this does not establish

- The accepted `jobType` string for every item type on the generic route, and whether the path-segment (`execute`) and telemetry (`RunNotebook`) spellings are interchangeable. Only three item types have a published enumeration.
- What a cancelled notebook does with writes already committed, and whether any item type ignores a cancel rather than refusing it with `JobAlreadyCompleted`.
- Whether `updateDefinition` preserves, resets or deletes a schedule that is not in the payload; the `.schedules` part name is documented for Git, not for the definition APIs.
- Job-instance retention in time (only "100 recently completed" is documented), and whether `Deduped` instances ever appear in `GET /items/{id}/jobs/instances` or only in telemetry.
- Whether a semantic-model refresh appears as an item job instance anywhere (the Monitor hub lists Semantic model as a supported item type; the jobs API has no such route).
- What `startMirroring` costs on the source, whether `stopMirroring` drops the mirrored tables, and how long `Starting`/`Stopping` actually last.
- Whether run conditions are usable for a production dependency at all — the whole feature is preview, and its limitations section covers only matching behaviour.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`platform/swagger.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/platform/swagger.json) | the six job paths, `jobType` as free string, `202`-only semantics, `InvalidJobType`/`JobAlreadyCompleted`/`TooManyRequestsForJobs` | read 2026-11-12 |
| [`platform/definitions/platform.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/platform/definitions/platform.json) | `ItemJobInstance`, `ItemJobStatus`, `InvokeType`, `ItemSchedule`, `CreateScheduleRequest` | read 2026-11-12 |
| [`common/job_scheduling.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/common/job_scheduling.json) | `ScheduleConfig` discriminators, Cron/Daily/Weekly/Monthly fields, `localTimeZoneId`, `OrdinalWeekday` | read 2026-11-12 |
| [`mirroredDatabase/swagger.json` + definitions @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/mirroredDatabase/swagger.json) | `startMirroring`/`stopMirroring`/`getMirroringStatus`, `MirroringStatus`, `TableMirroringStatus`, status-gated definition edits | read 2026-11-12 |
| [`mirroredCatalog` + `mirroredAzureDatabricksCatalog` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/mirroredCatalog/swagger.json) | `refreshCatalogMetadata`, `mirroringStatus`, `ItemMirroringState` = `Running`/`Stopped`/`Failed`, no start/stop | read 2026-11-12 |
| [`semanticModel/swagger.json` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/semanticModel/swagger.json) | eight operations, none of them refresh or jobs | read 2026-11-12 |
| [Run On Demand Item Job](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler/run-on-demand-item-job), [List](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler/list-item-job-instances), [Cancel](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler/cancel-item-job-instance) | operation names, the 100-completed limit, the `Deduped`/`Cancelled` definitions, `202` + `Location` | read 2026-11-12 |
| [Job Scheduler in Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/job-scheduler) | recurrence shapes, 90-day expiry, auto-disable and manual restart, schedule ownership, `.schedules` and deployment-pipeline inclusion, 100 jobs/submissions per minute, 24-day ceiling | ms.date 2026-10-29 |
| [`fabric_item_job_scheduler` v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/docs/resources/item_job_scheduler.md) | the only explicit `job_type` enumeration, ForceNew fields, `Central Standard Time` default, import syntax | v1.15.1, 2026-11-11 |
| [Item job event logs](https://learn.microsoft.com/en-us/fabric/fundamentals/item-job-event-logs) | the per-item `JobType` vocabulary used for monitoring | ms.date 2026-01-09, upd. 2026-11-10 |
| [Monitor job runs in the Monitor hub](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub-jobs) | last five runs per item, supported item types, `Canceled` status | ms.date 2026-10-05 |
| [Mirroring overview](https://learn.microsoft.com/en-us/fabric/mirroring/overview), [Monitor replication](https://learn.microsoft.com/en-us/fabric/mirroring/monitor), [Mirroring REST API](https://learn.microsoft.com/en-us/fabric/mirroring/mirrored-database-rest-api) | database vs metadata vs open mirroring, portal statuses incl. `Running with warning`, `Paused` on capacity pause, `Initialized`/`Stopped` gate on definition updates | 2026-08-28 / 2025-09-05 / 2026-03-18 |
| [Run, schedule, or trigger a pipeline](https://learn.microsoft.com/en-us/fabric/data-factory/pipeline-runs), [Run conditions (preview)](https://learn.microsoft.com/en-us/fabric/data-factory/pipeline-run-conditions), [Activity overview](https://learn.microsoft.com/en-us/fabric/data-factory/activity-overview) | event-based runs, `Custom`/`Data availability`/`Window coverage`, run dimensions, `Invoke pipeline`, `Fabric Actions`, 20 schedules per pipeline | 2026-09-21 / 2026-08-10 |
| [Refresh Dataset](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/refresh-dataset), [Get Refresh History](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-history), [Get Refresh Schedule](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-schedule), [Enhanced refresh](https://learn.microsoft.com/en-us/power-bi/connect-data/asynchronous-refresh) | the current refresh surface, `202` + `requestId`, history retention and statuses, `serviceExceptionJson`, `DELETE` cancel limits, `NoNotification` for SPs | 2018-03-14 refs / ms.date 2025-01-07 |
| [Develop, execute, and manage notebooks](https://learn.microsoft.com/en-us/fabric/data-engineering/author-execute-notebook), [How to use notebooks](https://learn.microsoft.com/en-us/fabric/data-engineering/how-to-use-notebook) | API run and cancel via the Job Scheduler, exit values for downstream signalling, schedule-owner identity | 2026-08-07 / 2026-04-24 |

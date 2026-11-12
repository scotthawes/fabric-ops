# Automation coverage: what Fabric will let you do unattended

**Dated 2026-11-12.** One row per action, across the whole platform lifecycle, with the mechanism and
the blocker. This is the "can we automate it?" answer; the *how* lives in
[`what-goes-where.md`](what-goes-where.md).

Three columns of judgement:

- **Auto** — safe to do on every run, no human.
- **Gated** — automatable, but belongs behind an approval because it is destructive or expensive.
- **Manual** — no route, or the route exists and refuses a service principal.

## Platform and capacity

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | :-: | --- | --- |
| Create capacity | Auto | Terraform `azurerm_fabric_capacity` | Subscription-scope Azure; separate root (ADR 0007) |
| Resize capacity (SKU) | Gated | ARM / `azurerm` | ForceNew-ish in practice; costs money immediately |
| Assign capacity admins | Auto | `administration_members` | Update-in-place unverified |
| Set overage threshold / surge protection | Manual | Portal/API | AzureRM is pinned to API `2023-11-01`; no field exists |
| Pause / resume | Gated | ARM action `suspend`/`resume` | Out of Terraform state; bills accrued backlog at pause |
| Read utilisation / throttling | Auto | Capacity Metrics app has **no API**; RTI events | No Azure Monitor metrics at all |
| Alert on capacity state | Auto (build) | Eventstream + Activator | Five alerts to build, none to configure |

## Tenant and governance

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | --- | --- | --- |
| Set a tenant setting | Gated | `fabric_tenant_setting` | No `import`; `delete_behaviour` defaults to `NoChange` |
| Create a domain | Gated | `fabric_domain` | Requires Fabric administrator; app must have no admin-consented Fabric permission |
| Assign workspaces to a domain | Auto | `fabric_domain_workspace_assignments` (preview) | Preview-gated, provider-wide flag |
| Apply a sensitivity label | Partial | `setLabels` (Power BI artifacts only) | Covers dashboards, reports, datasets, dataflows; no Fabric-native items; no API for an existing Fabric item |
| Endorse an item (promoted/certified) | Manual | Portal | No documented API |

## Workspaces and access

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | --- | --- | --- |
| Create workspace | Auto | `fabric_workspace` | Needs capacity contributor + the SP tenant setting |
| Assign workspace to capacity | Auto | `capacity_id` on the workspace | Needs workspace **Admin** too, not Contributor alone |
| Grant workspace role | Auto | `fabric_workspace_role_assignment` | Admin principal only (Member-or-higher) |
| Grant Admin to a group | Gated | Same resource | Structurally identical to any role; review is the control |
| Create workspace identity | Auto | `identity = SystemAssigned` | Dies with the workspace; restore does not bring it back |
| Rename workspace | Gated | REST update | Check what it breaks — see the lifecycle note |
| Delete workspace | Gated | REST / Terraform destroy | Soft-deletes items; recovery mints new IDs |

## Content

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | --- | --- | --- |
| Deploy 23 item types | Auto | `fabric-cicd` | Full deploy each run; overwrites portal edits |
| Deploy 7 item types | — | **Nothing** | No public definition API: SQL endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model, ML experiment |
| Deploy schema (warehouse) | Auto | `SqlPackage` publish | Preview DacFx; partial atomicity |
| Deploy lakehouse tables | Auto | `dbt-fabricspark` | Keys `NOT ENFORCED` |
| Create a shortcut | Auto | `fabric_shortcut` | Needs the target item's `item_id`; ordering after items |
| Set a schedule | Auto | `fabric_item_job_scheduler` | Four shapes (Cron/Daily/Weekly/Monthly), UTC bounds; auto-disables after ~10 failures; runs as its owner |
| Run a job on demand | Auto | `POST …/jobs/{jobType}/instances` | Returns `202` and is **not** an LRO — poll the instance, never `/v1/operations` |
| Cancel a job | Gated | `POST …/instances/{id}/cancel` | A request, not a guarantee; only documented refusal is `JobAlreadyCompleted` |
| Refresh a semantic model | Auto | Legacy `api.powerbi.com/…/refreshes` | Not on the Fabric jobs API; cancel only for enhanced refresh |
| Start / stop mirroring | Gated | `startMirroring` / `stopMirroring` | Reports `Paused`/`Stopped` with an `error` field; metadata mirroring has neither |
| Refresh a semantic model | Auto | REST refresh | Refresh can fail long after a green deploy |
| Move an item between workspaces | Manual | — | There is no cross-workspace move. `Move Item` is folder-only, so a "move" is create + delete with a **new item ID** |
| Delete an item | Gated | REST | Soft delete; `hardDelete=true` makes it unrecoverable and needs only item write |

## Connectivity and data

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | --- | --- | --- |
| Create a connection | Auto | `fabric_connection` | Creating it does not bind it |
| Bind a semantic model to a gateway or cloud connection | Auto | `POST …/semanticModels/{id}/bindConnection` | Caller must **own** the model; per item, per stage |
| Create a gateway datasource | Partial | REST `Create Datasource` | On-premises gateways only; gateway-admin permission; no OAuth2 |
| Set or rotate datasource credentials | Manual | Portal / PowerShell | Credential-shaped |
| Add a principal to a gateway | Partial | PowerShell `Add-DataGatewayClusterUser` | Accepts a service principal; no REST |
| Install, register and cluster a gateway | Manual | Installer on a host | Outside Fabric; recovery key is a secret |
| Create managed private endpoint | Auto | `fabric_workspace_managed_private_endpoint` | Approval by the target owner may still be needed |
| Approve a managed private endpoint | Manual | Target-side approval | Human decision |
| Create storage resource instance rule | Manual | ARM / PowerShell | No `azurerm` support |
| Grant workspace identity on storage | Manual | Azure RBAC | Azure-side permission |
| Semantic-model RLS roles | Partial | XMLA read-write + TMSL | No REST operation; an SP can create roles but not be a role member |
| Rebinding a report / dataset takeover | Auto | Power BI `Rebind Report`, `TakeOver` | Legacy audience; Write + Build on the target |
| Publish a workspace app | Manual | Portal only | The `Apps` group is eight reads |
| Create OneLake security roles | Gated | `fabric_onelake_data_access_security` (preview) | `role_name` is ForceNew — rename is destroy/create |

## The API surface underneath

Measured at `microsoft/fabric-rest-api-specs` commit `3f8600f`, 2026-11-10:

- **835 operations across 61 groups** (825 de-duplicated — see the
  [census](../reference/api-operations.md)), grouped by *item type* rather than by workload — there is no
  "Data Engineering" or "Power BI" group. The two cross-cutting groups are `platform` (187 ops,
  published on Learn as **Core**) and `admin` (60 ops).
- **434 are deployment-relevant** (286 write, 148 read) across thirteen families.
- **About 24 calls** implement everything this project needs.
- **58 operations declare service-principal support as No** — whole groups in some cases:
  `anomalyDetector`, `digitalTwinBuilder`, `eventSchemaSet`, `operationsAgent`, `userDataFunction`,
  `mlModel`, `mlExperiment`. That is why the Manual column is not merely "we haven't got to it".
- **48 paths are `?beta=true`**, and beta is a *query parameter*, never a path prefix — so it is easy
  to call a beta surface without noticing.

Two cautions from the spec itself: `admin/swagger.json` records workspace restore as a **`GET`**, so do
not generate a mutating client from it unchecked; and the 18 `METHOD path` collisions are mostly
admin-vs-Core pairs that differ only by base path.

The apparent gap between "434 write operations" and "23 deployable item types" is not a contradiction:
most of those writes are per-item *operations* — refresh, run job, list tables, update a connection on
an item — not definition deployment.

## What this audit does not yet cover

Be honest about the boundaries — this is a derived audit, not an endpoint census.

| Gap | Why it matters | Status |
| --- | --- | --- |
| Any step relying on the legacy `api.powerbi.com` surface | Needs a second token audience; "groups" means workspaces; separate service-principal switches; no Fabric support statement | cost of the legacy route |
| Endpoint-level confirmation | The Auto column now rests on a measured inventory: **835 operations**, 434 deployment-relevant | done — see [API inventory](../research/fabric-api-inventory.md) |
| Workspace apps and audiences | `fabric_org_app` exists for org apps; the workspace *app* may have no route | not assessed |
| Gateway registration and members | `fabric_gateway` exists, but installation and clustering are separate | not assessed |
| Mirroring start/stop | Changes whether ingestion is a pipeline concern at all | not assessed |
| Report rebinding, dataset takeover | Needed when a model is replaced rather than updated | not assessed |
| Tags, folders, encryption (CMK), external data shares | All have Terraform resources, all preview or newer | not assessed |
| Data agent and ontology configuration | New, preview, likely portal-first | not assessed |
| Job run and cancel | Running a notebook or pipeline on demand versus on schedule | not assessed |

Anything marked "not assessed" is a *maybe*, not a *no*. Do not quote this page as the final answer
on what is automatable until those rows are filled.

## The safety rails

Three structural protections, in decreasing order of strength — the first one is stronger than any
check you could write in a pipeline:

1. **The deploy principal is not a Fabric administrator.** A principal without that role cannot reach
   *any* of the irreversible operations: permanent workspace delete, capacity delete, hard delete.
   This is why [ADR 0002](../adr/0002-two-service-principals-federated.md) refuses to give the
   deploy identity admin rights, and it is a better control than a protected stage.
2. **`hardDelete=true` is never sent.** One query parameter converts a recoverable delete into an
   unrecoverable one, and it needs no elevated role beyond item write. Treat it as forbidden in code,
   not just in review.
3. **A capacity delete is the real point of no return.** The Azure resource disappears, and items are
   recoverable for seven days *only if* the workspace is reassigned to a same-region capacity within
   that window. There is no equivalent of a workspace's soft delete for the capacity itself.

One free interlock: deleting a workspace that is assigned to a deployment pipeline simply fails, which
is an accidental reason to leave that assignment in place.

## The shape of the answer

Of roughly 40 actions: **half are fully automatic**, a quarter are automatable but deserve an
approval, and a quarter have no route at all.

Two patterns explain almost every manual row:

1. **It is a relationship, not an object.** Bindings, credentials and grants-on-other-resources have
   no create/update definition to deploy.
2. **The platform has no write path.** Either the endpoint is list-only, or defaults are not applied
   to service principals, or the setting lives in ARM while the pipeline lives in Fabric.

Read the manual rows as the platform's honest limit, not as a backlog for the work repo.

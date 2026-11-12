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
| Apply a sensitivity label | Partial | `setLabels` (Power BI artifacts only); `POST /v1/admin/items/bulkSetLabels` for Fabric items | The bulk operation exists but its identity table says Service principal **No**, and the Learn page 404s — treat as unavailable until it works |
| Set an item description | Auto | `Update Item` | The only governance metadata a pipeline can write routinely |
| Apply tags to an item | Auto | `Tags_ApplyTags` | Service principal supported |
| Endorse an item (promoted / certified) | Manual | Portal | Zero "endorse" operations across all 61 spec groups; no schema field |
| Set item ownership | Manual | Portal | `creatorPrincipal` is read-only; no operation sets it |
| Export governance metadata to Purview | Auto | Purview **Fabric** source scan | Pull via scanner/admin APIs; needs an active Purview account; item-level only outside Power BI |

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
| Assign an item to a folder | Auto | `POST …/items/{itemId}/move` | Same workspace only; `fabric_folder` is preview |
| Configure a data agent | Auto | `dataAgent` group, including staging | Preview item type; 41 operations |
| Deploy an ontology | Auto | `ontology` group, `updateDefinition` | Preview |
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

## Closing the last three gaps

Checked directly against the generated census rather than assumed:

| Question | Answer | Evidence |
| --- | --- | --- |
| Can items be assigned to folders? | **Yes** — folders are full CRUD plus a move, and `POST /workspaces/{id}/items/{itemId}/move` moves an item **to a folder**. Still within one workspace | census, `platform` group |
| Can a data agent be configured unattended? | **Yes** — full CRUD plus staging operations for datasources, elements, few-shots and topics. Preview item type, but no API gap | census, `dataAgent` group (41 ops) |
| Can an ontology be deployed? | **Yes** — create, update, `getDefinition`, `updateDefinition` | census, `ontology` group |
| Can cross-item dependencies be expressed? | **No** — no dependency operations exist in any group. Sequencing two items is the external pipeline's problem | census, no matches |

So of the nine rows that read "not assessed" earlier today, **all nine are now answered**, and eight of
them are automatable.

## The rule, if you keep only one line

> A surface is automatable **iff** a write operation exists **on the object itself** and its identity
> table says Service principal **Yes**. A `GET`-only group, a view published over other items, or a
> verb that acts on a set is portal-only.

That rule predicted every verdict below, including the three we had wrong before checking.

## Governance and workspace surfaces

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | :-: | --- | --- |
| Create an org app and its audience | Auto | `fabric_org_app`, `fabric_org_app_audience` | GA operations, SP supported, neither resource preview |
| Publish a **workspace** app | Manual | Portal | Different object from an org app; no `/apps` write route, and the Power BI `Apps` group is read-only |
| Create a tag | Gated | `fabric_tag` | Tenant-scope tag creation needs Fabric administrator |
| Assign a tag | Auto | REST tag assignment | Contributor-level; Terraform has no apply-tag field |
| Encrypt a workspace (CMK) | Gated | `Assign`/`Reset Workspace Encryption` | Learn documents the operations; the provider gates it behind `preview`; needs a tenant setting and a Key Vault role |
| Workspace firewall and inbound Azure rules | Auto | REST + Terraform | The API is the only route once private links break the portal UI |
| Create or revoke an external data share | Auto | `fabric_external_data_share` | Creates/revokes only |
| **Accept** an external data share | Auto | API, in the customer's tenant | Must run in the receiving tenant — a second identity, not a second mechanism |
| Endorse (promoted / certified) | Manual | Portal | Zero "endorse" operations across all 61 specs; no field in any item schema |

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

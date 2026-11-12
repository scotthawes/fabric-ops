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
| Apply a sensitivity label | Manual | Portal (or `Create Item` only) | No call labels an existing item; defaults do not apply to SPs |
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
| Set a schedule | Auto | `fabric_item_job_scheduler` | Schedules are not in definitions; auto-disable after ~10 failures |
| Refresh a semantic model | Auto | REST refresh | Refresh can fail long after a green deploy |
| Move an item between workspaces | Manual | — | There is no cross-workspace move. `Move Item` is folder-only, so a "move" is create + delete with a **new item ID** |
| Delete an item | Gated | REST | Soft delete; `hardDelete=true` makes it unrecoverable and needs only item write |

## Connectivity and data

| Action | Verdict | Mechanism | Blocker or caveat |
| --- | --- | --- | --- |
| Create a connection | Auto | `fabric_connection` | Creating it does not bind it |
| Bind a connection to an item | Manual | Portal / per-item settings | No API; per stage, per item |
| Install a gateway | Manual | Installer on a host | Outside Fabric; recovery key is a secret |
| Create managed private endpoint | Auto | `fabric_workspace_managed_private_endpoint` | Approval by the target owner may still be needed |
| Approve a managed private endpoint | Manual | Target-side approval | Human decision |
| Create storage resource instance rule | Manual | ARM / PowerShell | No `azurerm` support |
| Grant workspace identity on storage | Manual | Azure RBAC | Azure-side permission |
| Create OneLake security roles | Gated | `fabric_onelake_data_access_security` (preview) | `role_name` is ForceNew — rename is destroy/create |

## What this audit does not yet cover

Be honest about the boundaries — this is a derived audit, not an endpoint census.

| Gap | Why it matters | Status |
| --- | --- | --- |
| **The legacy Power BI REST API** (`api.powerbi.com`) | Likely to move gateway binding, semantic-model RLS and label setting from Manual to Auto. Our conclusions were reached from the Core API alone | being verified |
| Endpoint-level confirmation | The Auto column rests on earlier notes, not on a full operation list | API inventory in progress |
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

# Which workspace and item lifecycle operations can automation run safely, and which are irreversible?

- **Status:** answered (with three named gaps) · **Checked:** 2026-11-12
- **Blocks:** the pipeline stages that touch workspaces and items, the deploy principal's role set, and the run-book entry for recovery
- **Sibling notes:** [`terraform-operating-model.md`](terraform-operating-model.md) §5 established workspace-delete semantics from the provider side; this note tests them against the REST contracts and adds item recovery, rename and bulk behaviour.

## Short answer

Rename, capacity reassignment, domain assignment and definition updates are in-place on the same ID and repeatable. Deletion is *almost* always soft — 7 days for a collaborative workspace, 3 days for a supported item — but the recover path returns a different object than the one you deleted in three specific ways: a restored workspace loses its workspace identity, a restored item loses its share permissions, and a workspace restore is a preview Fabric-admin API that demands a new name. Anything with `hardDelete`, the two `recoverableItems` routes, permanent workspace deletion, capacity deletion and identity deletion has no undo at all, and none of them require more than a role the deploy principal should not hold. Cross-workspace item *move* does not exist as an operation; "Move Item" moves to a folder.

## Detail

### 1. Workspace lifecycle

| Operation | Contract | In place? | Undo |
| --- | --- | --- | --- |
| Create | `POST /v1/workspaces` | new object, new `id` | delete → soft delete |
| Rename / describe | `PATCH /v1/workspaces/{workspaceId}`, body `displayName`, `description` | **yes** — same ID returned | rename back |
| Change capacity | `POST /v1/workspaces/{workspaceId}/assignToCapacity`, body `capacityId` → `202 Accepted` | **yes** | reassign; see failure mode below |
| Move to domain | `POST /v1/admin/domains/{domainId}/assignWorkspaces`, body `workspacesIds` | **yes** | assign to previous domain |
| Delete | `DELETE /v1/workspaces/{workspaceId}` — "Deletes the specified workspace and the items under it", caller needs *admin* workspace role | soft delete | Fabric-admin restore inside the window |

- **Capacity assignment is in-place but not atomic.** The call returns `202` — "assignment is in progress" — and the reassignment page warns "Moving a workspace to a different capacity might start successfully but finish with errors, which could affect some or all items in the workspace", leaving items "attached to a different capacity than the workspace". Cross-region moves require deleting every non-movable item first; only Report, semantic model (small storage), Dashboard, Dataflow Gen1, Paginated Report, Datamart and Scorecard are movable. Non-Power BI items "don't support migration across region".
- **Domain assignment overwrites.** "Preexisting domain assignments will be overridden unless bulk reassignment is blocked by domain management tenant settings" — a declarative-looking call that silently re-parents workspaces. Fabric administrator only (`Tenant.ReadWrite.All`).
- **A deployment-pipeline member workspace cannot be deleted at all**: "If you attempt to delete a workspace … and that workspace is currently assigned to a Deployment Pipeline, the deletion will fail." Free interlock; do not design around it.
- **Renaming a workspace also renames its workspace identity** ("the workspace identity is also renamed to match the workspace name. However its Microsoft Entra application and service principal remain the same").

### 2. Item lifecycle

| Operation | Contract | Preview? | Effect on references |
| --- | --- | --- | --- |
| Create | `POST /v1/workspaces/{workspaceId}/items`; `201` or `202` + LRO headers | GA; `contributor` role | new ID; nothing points at it yet |
| Rename / describe | `PATCH /v1/workspaces/{workspaceId}/items/{itemId}`, body `displayName`, `description` | GA | same `id` **and** same `logicalId` returned; ID-keyed references survive |
| Update definition | `POST …/items/{itemId}/updateDefinition` (+`?updateMetadata`), LRO; "does not affect its sensitivity label" | GA | none documented |
| Delete | `DELETE …/items/{itemId}`, optional `?hardDelete={hardDelete}` | GA | soft delete by default |
| Recover | `POST /v1/workspaces/{workspaceId}/recoverableItems/{itemId}/recover` | recycle bin is *preview*; route documented on the recovery page | **original ID preserved** (§3) |
| Move between workspaces | **none** | — | see below |
| Duplicate | **none** | — | see below |

**Move is a trap in the name.** `Move Item` is `POST …/items/{itemId}/move` with `targetFolderId`, and the summary is explicit: "Moves the specified item to a folder within the same workspace." `Bulk Move Items` is "Moves multiple items to a folder." There is no workspace-to-workspace move in the Items operation group. **Could not establish** any public API or portal path that relocates an item between workspaces; the only cross-workspace copy mechanisms documented are deployment pipelines (which keeps the *target* item's "ID, URL, and permissions … unchanged") and Get-Definition-then-Create (which mints a new ID and breaks every reference to the old one).

**Duplication** likewise has no operation. The full Items operation list contains Create, Update, Update Definition, Move, Bulk Move, Bulk Export/Import Definitions, Update Logical Id, Delete and the two relation reads — no clone or copy. Duplicating is `Get Item Definition` + `Create Item`; the copy is a new identity and a copied report definition can still point at the original semantic model until rebound.

**References behave by item type, not by intent.** Deployment pipelines "automatically connect (autobind) the deployed item to the item it depends on" when the linked item exists in the target stage and fail the deployment when it does not — but "a Direct Lake semantic model … doesn't automatically bind to items in the target stage", still pointing at the source lakehouse. A report pointing at a model is therefore safe under deployment *if the model was deployed too*, and silently wrong under Direct Lake.

### 3. The recover path

| Object | Retention | Who restores | Same ID? | What is left broken |
| --- | --- | --- | --- | --- |
| Collaborative workspace | 7 days default, 7–90, tenant setting **Define workspace retention period**; setting off still means 7 days | **Fabric administrator** only | **could not establish** | workspace identity; admin/role list (see below) |
| My workspace | 30 days, fixed | Fabric administrator | could not establish | becomes a normal workspace |
| Item (supported types) | 3 days default, 3–90, **Item Recovery** tenant setting, enabled by default | Contributor, Member or Admin | **yes** — "restoring an item from the recycle bin preserves the original item ID" | shared item permissions only |
| Item (unsupported type) | none | — | — | "Fabric irreversibly deletes them" |

- **Workspace restore is a preview admin API**: `POST /v1/admin/workspaces/{workspaceId}/restore`, body `newWorkspaceName` + `newWorkspaceAdminPrincipal`, scopes `Tenant.ReadWrite.All`, "part of a Preview release … not recommended for production use", max 10 requests/minute. The UI version requires "a new name for the workspace and assign at least one user the Admin role".
- **Whether the restored workspace keeps its ID: could not establish.** The route addresses the deleted workspace by its old ID and returns `200` with no body, so the surviving ID is not observable from the contract; the dashboard note flags the same gap. Treat any automation that stores workspace IDs across a delete as broken until tested.
- **Workspace identity is not restored**: "If you restore the workspace after deletion, the workspace identity **is not** restored. If you want the restored workspace to have a workspace identity, you must create a new one." Deleting the identity directly is worse — "Deleted workspace identities cannot be restored."
- **Item restore is close to complete**: "preserves all properties, configurations, and relationships except shared item permissions" — endorsement, tags, DLP, sensitivity labels, lineage, parent-child and Warehouse snapshots come back; sharing must be redone.
- **Item restore fails on a name collision**: "If a new item with the same name as the soft-deleted item exists in the same workspace, the recovery fails until you rename the existing item."
- **Git and recovery fight each other.** "Git operations (such as Undo or Update from Git) re-create deleted items by assigning a new item ID, whereas restoring an item from the recycle bin preserves the original item ID", producing duplicates "which may cause Git Integration to stop working as expected". Mitigation is to delete the Git-created copy. Note also that soft-deleted items still count toward the 1,000-item workspace limit, and that a Git sync re-creates *definition only, no data*.
- **A retention-window change reaches backwards**: decreasing the setting can make an already-deleted workspace "eligible for permanent deletion … the next time it checks", with "no extra grace period".
- **Contradiction to note:** `retention-recovery` and `portal-workspaces` both say item retention is 3–90 with a 3-day default, but the `item-recovery` setup steps say "enter the number of days for the retention period (7 to 90 days)". Use the tenant setting, not the prose.

### 4. Bulk and destructive operations

- **Workspace delete takes every item with it** and the retention window covers them together; there is no per-item opt-out.
- **Capacity delete is a partial, timed, region-scoped undo.** "When you delete a Power BI Premium, Trial or Fabric Capacity, non-Power BI Fabric items in workspaces assigned to the capacity are soft deleted … If the workspace that holds these items is associated to a capacity (other than Power BI Embedded) from the same region as the deleted capacity within seven days, the deleted items are restored. This seven-day period is separate from the workspace retention setting." What happens to Power BI items, and to the workspace object itself: **could not establish**.
- **Two hard deletes exist and both are one parameter or one route away**: `?hardDelete=true` ("permanently deleted and cannot be recovered") and `DELETE …/recoverableItems/{itemId}`. Even after a permanent item delete, "OneLake retains the data for an additional seven days. You can't restore data during this period."
- **No bulk delete API.** Bulk operations in the Items group are definition import/export and folder move only. Bulk destruction comes from deployment tooling — a Terraform `destroy` over a root — not from a Fabric endpoint.
- **Bulk domain assignment is a bulk overwrite** (§1) and is the only "bulk" call here that changes governance state on objects you did not name.

### 5. Rename semantics

- **OneLake paths are name-keyed.** The documented path shape is `https://onelake.dfs.fabric.microsoft.com/MyWorkspace/MyLakhouse/Tables/MyShortcut/MyFile.csv`, so renaming a workspace or item changes the path every external consumer, notebook and shortcut uses.
- **Shortcuts break on a renamed target**: "If you move, rename, or delete a target path, the shortcut can break." Shortcuts are "an independent object from the target", so deleting one is safe; renaming its target is not.
- **Git sees a rename as identity churn.** The item folder in Git is built from the item's display name (falling back to `logicalId` + type when the name is unusable), and Fabric treats a rename as "add/remove operations instead of conflicting updates". A workspace rename does not change the Git connection — that is configured per workspace but is not keyed on the name.
- **Deployment pipelines are name- and position-sensitive, not rename-sensitive at the item level.** Stage count and stage names "are permanent, and can't be changed" after creation; stages are matched "by each stage's position in the pipeline … not by the stage's display name"; a rename is a "settings change (like rename)" that propagates to the paired item on deploy, while the target's "ID, URL, and permissions remain unchanged".
- **A report's saved reference to its semantic model across a rename: could not establish** a page that states it. The ID survives the rename (`PATCH` returns the same `id` and `logicalId`), so an ID-keyed reference should hold — that is reasoning, not documentation.

### 6. Automation safety

**Structural guard first: do not make the deploy principal a Fabric administrator.** Restore Workspace, Assign Domain Workspaces By Ids, Delete Domain and permanent workspace deletion all demand `Tenant.ReadWrite.All` and "Fabric administrator rights"; item hard delete demands workspace *Admin*. A deploy identity scoped to Contributor/Admin of named workspaces cannot reach the irreversible set at all — stronger than any pipeline check.

Then, per operation class:

- **Approval check belongs on the environment, not in the YAML.** "Approvals and other checks aren't defined in the yaml file. Users modifying the pipeline yaml file can't modify the checks performed before start of a stage."
- **Terraform side**: `prevent_destroy` on `fabric_workspace` and `azurerm_fabric_capacity`, keeping blocks rather than deleting them, and `removed { … lifecycle { destroy = false } }` for retirement — already established in the sibling note §3, including that the guard is not recorded in state.
- **Dry-run comparison is native on one surface only**: `terraform plan`, and deployment-pipeline stage compare ("Compare stages") which shows a rename as a settings change without opening a change review. There is no What-If for Fabric core operations.
- **Preflight beats rollback.** Before any delete, list items in the workspace and refuse if the count exceeds what the pipeline believes it owns; after any capacity reassignment, re-read the workspace and check for items still attached to the old capacity.

### 7. Not reversible at all

1. `DELETE …/items/{itemId}?hardDelete=true`.
2. `DELETE …/recoverableItems/{itemId}` — and the OneLake data is gone after a further 7 days.
3. Permanent deletion of a deleted workspace (route/portal), which "irreversibly deletes its contents".
4. Deletion of a workspace past, or pushed past, its retention window.
5. Capacity deletion — the Azure resource, its ID and its billing are gone; only items are recoverable, and only for 7 days, and only if you reassign the workspace in time.
6. Workspace identity deletion, and the identity of a deleted workspace after restore.
7. Deletion of any item type outside the supported-soft-delete list.
8. Item *move* between workspaces, because it is implemented as create + delete and therefore changes the ID.

## What this settles

| Bucket | Operations | Why |
| --- | --- | --- |
| **Safe to automate repeatedly** | `Create Item` behind a List-Items existence check; `PATCH` rename/description to a declared target; `updateDefinition`; `assignToCapacity` with a post-check; `fabric_workspace` create/update; role-assignment grants; deployment-pipeline deploys; item **recover** retried on 404 | in-place on a stable ID, idempotent by observation, and failure leaves the previous state intact |
| **Automatable but gated behind a human approval** | item delete (soft); workspace delete; domain bulk assign; cross-region capacity reassignment; `Restore Workspace`; any `destroy` plan over a workspace root | reversible but only inside a timer, only by a Fabric admin, or only with side effects (identity, share permissions, overridden domain) that the pipeline cannot restore |
| **Never automated** | `hardDelete=true`; `DELETE …/recoverableItems/{itemId}`; permanent workspace delete; capacity delete; workspace-identity delete; assigning the deploy principal Fabric administrator or `Tenant.ReadWrite.All` | no undo exists, or the undo depends on an artefact (capacity, identity, ID) that deletion destroyed first |

## What this does not establish

- Whether a restored workspace keeps its ID, and whether its role assignments survive — the restore call requires a new admin, which is consistent with either.
- Whether the Git binding of a deleted workspace is restored with it.
- What a capacity delete does to Power BI items and to the workspace object, as distinct from non-Power BI items.
- Any public path for moving an item between workspaces; absence of an operation is not proof the portal has none, though no Learn page documents one.
- Whether renaming an item breaks a report's saved model reference, as opposed to a shortcut's target path (the latter is documented).
- Whether `Assign Domain Workspaces By Capacities` overrides prior assignments the way the By-Ids call does.
- Runtime behaviour of the preview restore API under load; only its 10-requests/minute limit is documented.

## Sources

| Source | Used for | Dated |
| --- | --- | --- |
| [delws] / [updws] / [capws] | "and the items under it"; `PATCH` body; `202` assignment, cross-region limits | upd. 2026-09-24 / 2026-11-10 |
| [reassign] | partial-failure warning, movable item list, "don't delete or pause the source capacity" | ms.date 2026-01-30, upd. 2026-11-10 |
| [wsret] / [ret] / [itemrec] | 7-day and 30-day retention, restore flow, permissions matrix, per-item recovery routes, 3–90 vs 7–90 | ms.date 2026-10-05 / 2026-09-16 / 2026-09-01 |
| [delitem] / [upditem] / [updef] / [createitem] | `hardDelete`, 1,000-item counting, rename body, definition LRO, create LRO | upd. 2026-09-24 to 2026-11-11 |
| [moveitem] / [itemsidx] | folder-only move; full operation list, no move-across or duplicate | upd. 2026-11-11 / 2026-09-21 |
| [restws] / [restwsrestore] | operation list; preview restore, body, scopes, 10 req/min | upd. 2026-08-03 / 2026-09-15 |
| [domainsidx] / [assignws] / [deldomain] | domain assignment overrides; admin-only | upd. 2026-11-09 / 2026-09-15 |
| [gitproc] | recycle-bin vs Git IDs, "renamed to the logical ID", rename as add/remove | ms.date 2026-06-15, upd. 2026-10-26 |
| [logicalid] | logical ID as cross-workspace identity; deployment-plan conflicts | ms.date 2026-09-01 |
| [dpproc] | "ID, URL, and permissions remain unchanged", autobinding, Direct Lake, stage position | ms.date 2026-09-24, upd. 2026-11-02 |
| [ws] / [wsid] | delete-fails-in-pipeline, identity irretrievable/not restored, rename renames identity | ms.date 2026-09-16 / 2026-07-28 |
| [shortcuts] | name-keyed OneLake path; "If you move, rename, or delete a target path, the shortcut can break" | ms.date 2026-11-05, upd. 2026-11-08 |
| [capsets] | capacity-delete soft delete, 7-day same-region restore, separate from workspace retention | ms.date 2026-03-06 |
| [approvals] | approvals not in YAML, held by the resource owner | ms.date 2024-08-29, upd. 2026-05-07 |

[delws]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/delete-workspace
[updws]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/update-workspace
[capws]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/assign-to-capacity
[reassign]: https://learn.microsoft.com/en-us/fabric/admin/portal-workspace-capacity-reassignment
[wsret]: https://learn.microsoft.com/en-us/fabric/admin/workspace-retention
[ret]: https://learn.microsoft.com/en-us/fabric/admin/retention-recovery
[itemrec]: https://learn.microsoft.com/en-us/fabric/admin/item-recovery
[delitem]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/delete-item
[upditem]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/update-item
[updef]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/update-item-definition
[createitem]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item
[moveitem]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/move-item
[itemsidx]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items
[restws]: https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces
[restwsrestore]: https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces/restore-workspace
[domainsidx]: https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains
[assignws]: https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/assign-domain-workspaces-by-ids
[deldomain]: https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/delete-domain
[gitproc]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process
[logicalid]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/logical-id-conflict-resolution
[dpproc]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process
[ws]: https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces
[wsid]: https://learn.microsoft.com/en-us/fabric/security/workspace-identity
[shortcuts]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-shortcuts
[capsets]: https://learn.microsoft.com/en-us/fabric/admin/capacity-settings
[approvals]: https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals

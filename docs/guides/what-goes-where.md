# What goes where: launching the Fabric platform

**Dated 2026-11-12.** The launch decision sheet. Three mechanisms, one rule each, then the order to
run them in.

The rule of thumb:

- **Terraform** owns anything with an ID that must exist *before* content lands, and anything that
  must not be recreated by a deploy.
- **The content pipeline** (ADO YAML → `fabric-cicd`) owns item definitions: the things authors edit.
- **Manual** owns everything the APIs cannot express, everything credential-shaped, and everything
  tenant-wide.

> **On the name.** "Fabric deployment pipeline" is a *native feature* — stages inside Fabric that
> copy content workspace-to-workspace. It is **not** in this design: it never reads Git and cannot
> copy role assignments (see [the comparison](../research/deployment-mechanism-comparison.md)).
> Where this page says "the pipeline", it means ADO YAML + `fabric-cicd`.

## 1. The three columns

| Thing | Terraform | Content pipeline | Manual | Why |
| --- | :-: | :-: | :-: | --- |
| Resource group + F SKU (capacity) | ✅ | | | Azure resource; must exist before any workspace |
| Capacity admins, overage threshold, surge protection | | | ✅ | Portal/API settings AzureRM cannot express; overage is a money decision |
| Pause / resume | | | ✅ | ARM action, outside Terraform state (ADR 0004) |
| Tenant settings | ⚠️ | | ⚠️ | Expressible, but no import and `NoChange` default — assert only what you'll own forever |
| Entra groups (one per workspace) | | | ✅ | Identity-system work, not Fabric |
| Workspaces + capacity assignment | ✅ | | | Must exist before items; must not be recreated (ADR 0003) |
| Workspace role assignments | ✅ | | | Reviewable in a diff; the admin principal does it (ADR 0002) |
| Dev workspace Git binding | ✅ | | | Active binding, not passive — connect once, early (ADR 0005) |
| **Item definitions** (23 types) | | ✅ | | The things authors edit; full deploy each run |
| 7 item types with no definition API | | | ✅ | Cannot be deployed by anything (SQL endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model, ML experiment) |
| Warehouse / lakehouse **schema** | | ✅ | | Second stage, state-based; shells alone are empty (ADR 0008) |
| Connections (gateway, workspace identity) | ⚠️ | | ⚠️ | `fabric_connection` exists, but the binding to an item does not |
| Gateway install, cluster, recovery key | | | ✅ | Infrastructure outside Fabric |
| Per-item, per-stage connection binding | | | ✅ | Nothing copies it; the big hole in "unattended" |
| Storage-side resource instance rule | | | ✅ | ARM/PowerShell only |
| Workspace identity RBAC grants | | | ✅ | Azure-side permission |
| Sensitivity labels | | | ✅ | Create-only in the API, never in Git |
| Item sharing, apps, publish-to-web | | | ✅ | Access decisions with a human owner |
| Domains | ⚠️ | | ⚠️ | `fabric_domain` needs Fabric administrator; do it once, by a human |
| Schedules | ⚠️ | | ⚠️ | `fabric_item_job_scheduler` exists; schedules are not in definitions |
| Monitoring and alerts | | | ✅ | No alerting product — five alerts to build (see rec 02) |

`✅` = this mechanism. `⚠️` = possible but not the first choice.

### Why "there is an endpoint" is not the test

An API operation is necessary for automation and never sufficient. Four separate things can block a
call that exists:

| Blocker | What it looks like |
| --- | --- |
| The verb is missing | The item supports `List` only — SQL analytics endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model/experiment |
| The verb exists but takes no definition | Org app (`Create` unsupported, definition-only); ML experiment creates only a shell |
| Your principal is refused | `MirroredDatabase` and `Reflex` mark service-principal support unsupported; admin APIs need an allow-listed group |
| It is not an object, it is a relationship | Gateway binding, connection credentials, resource instance rules, sensitivity labels, schedules |

And one that surprises people: **capacity suspend/resume and overage are ARM operations**, not Fabric
API calls, so a Fabric-scoped principal cannot perform them at all.

The practical test before promising automation: *does a write operation exist, does it accept a
definition, will it accept a service principal, and is it out of preview?* All four, or it is manual.

## 2. The order to launch in

Sequence matters more than any single row, because of two hard dependencies: a workspace must exist
before items land, and a capacity must exist before a workspace can be assigned.

**Phase 0 — before any pipeline exists (manual, half a day)**
1. Create the Entra groups: one per workspace, name matching the workspace.
2. Create the two service principals and their federated service connections.
3. Turn on the four service-principal tenant settings, naming the admin security group.
4. Confirm the network posture (run-book item 1) — this can invalidate the agent placement.

**Phase 1 — the platform (Terraform)**
5. `terraform/capacity`: resource group and F SKU.
6. Set capacity admins, overage threshold, surge protection (manual, portal).
7. `terraform/workspaces`: the three workspaces, their group role assignments, dev's Git binding.

**Phase 2 — the first content (pipeline)**
8. Commit two items to dev; merge; the pipeline deploys them to dev.
9. Add the schema stage; confirm tables exist, not just shells.
10. Promote to test, then prod behind an approval.

**Phase 3 — the things that make it usable (manual)**
11. Connections, gateway install if needed, per-stage bindings.
12. Labels, then item sharing and any app.
13. Build the five alerts.

## 3. Where the native Fabric deployment pipeline fits

**Nowhere, as the promotion mechanism.** It is workspace-to-workspace and Git-blind, so it cannot be
the path from a repository. Two places it remains legitimate:

- A one-off comparison between two workspaces when you want Fabric to show you a diff.
- An organisation that has chosen portal-first authoring and no repository — which is the opposite of
  this design.

It is also **blocked outright** in workspaces with workspace-level private link, which is a decision
we cannot make for the tenant.

## 4. The three things that surprise people at launch

1. **A green deploy can leave an empty warehouse.** Item deployment ships shells; schema is a
   separate stage (ADR 0008).
2. **A deployed model cannot refresh until a human binds it.** The item is healthy, the connection
   is not, and the error appears at refresh, not at deploy.
3. **A pipeline-created item is unlabelled and nothing fails.** Default labelling does not apply to
   service principals.

## 5. If you only remember one thing

> Terraform builds the containers, the pipeline fills them with definitions, and a human connects
> them to the world — connections, credentials, labels and the capacity's money settings.

Numbers, if useful: **6 Terraform resources**, **23 deployable item types**, **7 item types and
roughly a dozen operational steps that stay manual.**

# How should Terraform be operated against Fabric over time — layout, ordering, adoption, drift, deletion, upgrades, and where it stops?

- **Status:** answered · **Checked:** 2026-11-12
- **Blocks:** the work repo's Terraform root layout, its pinning policy, and the run-book entries for import and destroy
- **Sibling note:** [`terraform-provider-surface.md`](terraform-provider-surface.md) covers the resource inventory, auth attributes and per-resource permissions; this note does not restate them.

## Short answer

One root per *lifetime*: a small `capacity` root (Azure resource, one state) and a `workspaces` root applied once per environment with its own state key and tfvars; no CLI workspaces. Pin the provider to an exact version and commit the lock file, because it has shipped a breaking change in a minor release. Terraform owns containers and grants, not items — it cannot read an item definition back, so it cannot see the fight it would be in.

## Detail

### 1. Layout for three environments on one shared capacity

The provider publishes no opinion on environments. Its quickstarts are one flat root each — no `env/`, no workspaces, no modules — and the getting-started guide is a single "Terraform project" ([quickstarts][qs], [getting started][gs], read 2026-11-12). `102-fabric-capacity` is the only multi-provider shape on offer: `azurerm_fabric_capacity` and `fabric_workspace` in one root, capacity read back via `data "fabric_capacity"` with `display_name` from the resource and a `postcondition` on `self.state == "Active"`.

- **One root, tfvars + state key per environment.** Keys are separate states with separate locks — the [azurerm backend][tfbe] "supports state locking and consistency checking with Azure Blob Storage native capabilities". Three applies, three plans, three blast radii, but only if the capacity is not duplicated into all three: whichever state holds `azurerm_fabric_capacity` owns the object every environment needs, so the others reach it by `data "fabric_capacity"` (as the quickstart does) or [remote state][tfrs].
- **Root per environment.** Same split, plus three copies of the code, three `required_providers` blocks and three lock files. Its real advantage is per-environment credentials, exactly what ADR [0002](../adr/0002-two-service-principals-federated.md) needs if the admin and deploy identities must not share a root.
- **CLI workspaces.** Ruled out by HashiCorp: "Workspaces are not appropriate for system decomposition or deployments requiring separate credentials and access controls" ([workspaces][tfws], v1.17 docs, read 2026-11-12). Second cost: `${terraform.workspace}` conditionals make the configuration differ per environment, which is the plan noise tfvars exists to avoid.
- **One state for all three.** A single `apply` or `destroy` reaches the shared capacity and all three workspace sets together, and `-target` becomes the only partial-apply escape.

**Recommended shape**, consistent with [`repo-layout.md`](../reference/repo-layout.md) (2026-11-11: "split by *lifetime*, not by environment"): `terraform/capacity/` → the F SKU and its resource group; `terraform/workspaces/` → one root, state key `dev|test|prod`, tfvars per environment, capacity from `data "fabric_capacity"`. *Reasoning:* the longest-lived, widest-blast-radius object sits in the smallest state, and the root that runs weekly contains only what is cheap to rebuild.

### 2. Ordering and dependency

| Step | Resource | Edge |
| --- | --- | --- |
| 1 | `azurerm_fabric_capacity` | — |
| 2 | `data "fabric_capacity"` | `display_name` from step 1; `postcondition` blocks on non-`Active` |
| 3 | `fabric_workspace` | `capacity_id = data.fabric_capacity.x.id` |
| 4 | `fabric_workspace_role_assignment` | `workspace_id = fabric_workspace.x.id` |
| 5 | `fabric_workspace_git` | `workspace_id = fabric_workspace.x.id` |
| 6 | items | **no Terraform edge** — `fabric-cicd` runs in a later pipeline stage |

Steps 3–5 are *implied*. `depends_on` is only needed "when a resource or module relies on another resource's behavior but does not access any of that resource's data in its arguments" ([depends_on][tfdo], read 2026-11-12) — a Git binding that must follow a grant to another principal, or a resource that must follow a `fabric_tenant_setting` toggle.

**Workspace plus item in one run is safe only with a reference.** `fabric_workspace` blocks until the capacity assignment settles: the read loop switches on `capacity_assignment_progress` and sleeps 30 s until `Completed`, then validates capacity state ([provider source][tfsrc], `internal/services/workspace/resource_workspace.go`, v1.15.1). An **ambient workspace ID** — a `-var` or a tfvars string — has no graph edge, so the first apply of a new environment races a workspace still attaching to capacity: intermittent 404/409 on item create, green on retry. The capacity is the slowest link, which is why the quickstart carries the `postcondition`.

### 3. Adopting existing objects

**Importable:** `fabric_workspace` (`"<WorkspaceID>"`), `fabric_workspace_role_assignment` (`"<WorkspaceID>/<WorkspaceRoleAssignmentID>"`), `fabric_domain`, `fabric_deployment_pipeline`, `azurerm_fabric_capacity` ([workspace][tfw], [role assignment][tfra], [capacity note](capacity-provisioning-and-cost-control.md)). **Not importable:** `fabric_workspace_git` and `fabric_tenant_setting` have no Import section and no `ImportState` in v1.15.1 ([workspace_git][tfwg], provider source).

A Git-bound workspace therefore cannot be adopted: you disconnect in the portal and let Terraform's create path run — and that path is not passive. It calls `Connect`, then `InitializeConnection`, then **commits out or updates from the branch** on the returned `requiredAction` (provider source, `internal/services/workspacegit/resource_workspace_git.go`). `initialization_strategy` matters only "when content exists on both the remote side and the workspace side" ([Initialize Connection][gitinit], read 2026-11-12), and `PreferRemote` means "Prefer remote Git side content" — it can overwrite the items of the workspace you are adopting. Adopt with `PreferWorkspace`.

**Importing a workspace that already holds items** records the workspace and nothing else: `fabric_workspace` has no item collection to enumerate, so no item enters state and no plan proposes deleting one. The plan reconciles `display_name`, `description` and `capacity_id` — all in place, no `ForceNew` on this resource (provider source). The destruction risk is not the plan; it is a later `destroy` or `-replace` (§5).

**Importing an item** is where a plan overwrites what it did not create: `get` reads only metadata, so `definition` lands empty, and `ModifyPlan` sees plan ≠ state with `definition_update_enabled` defaulting to `true` ("Update definition on change of source content. Default: `true`") and pushes the repo definition into the live item (provider source — *reasoning from code*). Safe for the shell, not for the content.

**Guard:** `lifecycle { prevent_destroy = true }` on `fabric_workspace` and `azurerm_fabric_capacity`, with two documented caveats — deleting the resource block destroys the object "even if `prevent_destroy` is enabled", because the rule is not recorded in state ([lifecycle][tflc], read 2026-11-12); and a guard only fires on a plan someone reads. The correct hand-off is a `removed` block: "By default, Terraform removes the resource from state and destroys the actual resource. Set `destroy` to `false` to remove the resource from state without destroying" ([removed][tfrm]).

### 4. Drift and plan noise

**It reports:** `display_name`, `description`, `capacity_id`, role assignments, the Git binding — read on refresh, visible, overwritten by the next apply.

**It cannot see item definitions.** An item resource's `get` calls `GetItem` only; `GetItemDefinition` appears in the item *data sources*, not the resources ([provider source][tfsrc], `internal/pkg/fabricitem/`). A portal edit to a Terraform-managed notebook is invisible to `plan`, which compares config against last-applied state. The provider is not lying; it has no read path to compare with. Reconciliation where wanted is `terraform plan -refresh-only`, for "changes made to remote objects outside of Terraform" ([plan][tfplan], read 2026-11-12) — it will not find a definition edit.

**Ordering noise is real but historical.** v1.10.0 fixed two `fabric_workspace_outbound_*_rules` resources "producing inconsistent result after apply due to ordering" and `fabric_workspace_git` "reporting unexpected plan diffs for `organization_name`, `project_name`, and `repository_name`" ([CHANGELOG][tfchg], 2026-05-07). No current page documents a standing ordering caveat: treat it as a bug class, not known behaviour.

**Content is compared by hash, not path.** Each definition part carries a computed `source_content_sha256` with a plan modifier over `source`/`processing_mode`/`tokens`/`parameters`/`tokens_delimiter` (provider source), so editing a file does produce a diff. `definition_update_enabled = false` turns that diff into a warning instead of an update — the repo change then never reaches the item, silently.

**The one drift the docs admit** is `skip_capacity_state_validation`: "the provider cannot detect a suspended or inactive capacity. If the capacity becomes inactive, subsequent `terraform apply` runs may fail to find workspace items and could remove them from the Terraform state, potentially causing unrecoverable state drift" ([fabric_workspace][tfw], read 2026-11-12) — the mechanical reason for ADR [0004](../adr/0004-one-shared-capacity.md)'s "never apply against a paused capacity". Separately, `fabric_domain_role_assignments` takes `principals` as a **Set** with `ForceNew` on set and `role` ([docs][tfdr], read 2026-11-12), so adding one principal replaces the whole assignment; `fabric_workspace_role_assignment` is one principal per resource and does not.

### 5. Deletion semantics

`fabric_workspace` delete calls `DeleteWorkspace`, and the API summary is unambiguous: "Deletes the specified workspace and the items under it" ([Delete Workspace][delws], read 2026-11-12). `fabric_workspace_git` delete only disconnects (`Disconnect`, provider source) — repo and items untouched.

**It is a soft delete.** A collaborative workspace enters a retention period (default 7 days, 7–90) during which a Fabric administrator can restore it; afterwards "Fabric permanently removes the workspace and irreversibly deletes its contents". Individually deleted items are soft-deleted for supported types (default 3 days, 3–90) ([Retention and recovery][ret], read 2026-11-12).

**Items exist in Terraform only if you put them there.** Item resources cover roughly 40 types, but ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md) gives items to `fabric-cicd`, so Terraform holds no record of any item: a workspace destroy reports one resource and takes every item with it, including ones no pipeline can rebuild.

**Cost of a mistaken destroy.** Workspace: recoverable for 7 days, but recovery is a *new* ID — state, Git binding, role assignments and every reference to the old ID are now wrong, and re-apply creates a second workspace beside the restored one. Capacity: the Azure resource is gone, billing stops, and every workspace that used it loses its compute; Terraform cannot restore it.

**Not stated anywhere I could find:** whether a restored workspace keeps item IDs or lands back on the ID in state; what a capacity delete does to its assigned workspaces; whether two workspaces may share a display name (which decides whether a post-destroy re-apply collides with a restore).

### 6. Upgrades and preview flags

**Cadence:** v1.0.0 on 2025-03-31, v1.15.1 on 2026-11-11 — roughly monthly, sometimes twice in a week (v1.15.0 → v1.15.1 in three days) ([releases][tfrel], read 2026-11-12).

**Breaking changes are signalled, but not by the version number.** The CHANGELOG "adheres to Semantic Versioning" ([CHANGELOG][tfchg]) yet v1.6.0, a **minor**, carries "💥 Breaking: `git_credentials` and `git_credentials.source` attributes are now *REQUIRED* for `fabric_workspace_git`". Post-1.0 breaking entries exist at v1.0.0 and v1.6.0 only; removals are deferred ("before its removal in a future major provider version").

**`preview` is provider-wide.** A provider argument — `preview` (Boolean) "Enable preview mode to use preview features" ([provider docs][tfp]) — and preview resources refuse to work without it: "'%s' is not available without explicitly opt-in to the preview mode on the provider level configuration" (provider source). One switch unlocks every preview resource in that root, and v1.0.0 marked `fabric_environment` preview "due to upcoming API breaking changes": a preview schema can move under you inside a minor.

**Pinning:** `version = "= 1.15.1"`, `required_version = ">= 1.8, < 2.0"`, commit `.terraform.lock.hcl` ([lock file][tflock]); upgrade by bumping both in a PR that plans all three environments. `~> 1.15` is defensible only because it stops at 1.15.x; `~> 1.0` is not, because of v1.6.0. Keep preview resources in their own root so `preview = true` cannot be inherited by the state holding production workspaces.

### 7. The boundary

| Object class | Owner | Why |
| --- | --- | --- |
| Capacity, resource group, tags | Terraform, `capacity` root | an ID and a price nothing else should recreate |
| Workspaces | Terraform | the ID every downstream system references |
| Workspace role assignments, domain assignments | Terraform | declarative, per-grant, idempotent |
| Git *connection*, non-production only | Terraform | binds **and syncs** (§3); ADR 0005 keeps prod unbound |
| Tenant settings | Terraform, separate gated root | tenant-wide blast radius (ADR 0003) |
| Item definitions | `fabric-cicd` | the only mechanism that reads definitions every run |
| Capacity overage, surge protection, pause/resume, retention | Manual / run-book | not expressible in current API versions (§8) |
| Item types with no public create/update API | Manual | ADR 0003's list; verify per [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) |

**What breaks when it is crossed.** An item resource in Terraform beside `fabric-cicd` on the same item gives two writers and no arbiter: Terraform holds a content hash of *its* copy, `fabric-cicd` rewrites the live definition every run, and Terraform never reads the live definition (§4), so neither sees the other. Last writer wins and the loser is invisible until someone diffs portal against repo. The other direction is worse: removing the Terraform resource deletes an item the deployer believes it owns, the next run recreates it with a new ID outside Terraform's state, and the following plan recreates it again. The boundary follows from Terraform's read path, not from taste.

### 8. Escape hatches

**`azapi_resource`** is "a very thin layer on top of the Azure ARM REST APIs… enabling the management of Azure resources that are not yet or may never be supported in the AzureRM provider" ([azapi][azapi], read 2026-11-12). With `type = "<resource-type>@<api-version>"` and a free-form `body`, `Microsoft.Fabric/capacities@2026-09-01-preview` with `properties.overage` is expressible today, as is an `F4096`/`F8192` SKU that `azurerm_fabric_capacity` does not document.

**`azapi_update_resource`** patches a subset of an existing resource and its delete is a no-op by design: "When `azapi_update_resource` is deleted, no operation will be performed, and these properties will stay unchanged" ([azapi_update_resource][azapiup], read 2026-11-12). A destroy therefore leaves the overage setting live and state diverges from reality — right tool for a *setting*, not an object.

**Suspend/resume is an action, not a property** ([capacity note](capacity-provisioning-and-cost-control.md)). Do not use the `azapi_resource_action` data source: "It should not be used to perform actions that modify the state of an Azure resource, because it will be called multiple times during a Terraform run" ([data source][azapiact], read 2026-11-12). Use CLI/REST outside Terraform, or a stateless `action` block.

**Cost of the hatch:** raw JSON in state, so server-side defaults surface as diffs unless `ignore_body_changes` is tuned; no schema validation, so an API-version bump fails at apply rather than plan; and one object must have one owner — an `azapi_resource` capacity that `azurerm_fabric_capacity` also manages is two states claiming one ID. Keep hatches to fields, not objects.

## What this settles

- **Layout:** `terraform/capacity/` (one state: resource group, F SKU) and `terraform/workspaces/` (one root, state key per environment, tfvars per environment, capacity via `data "fabric_capacity"`), no CLI workspaces, admin resources in a separate gated root per ADR 0002/0003.
- **Pinning:** exact provider version, `>= 1.8, < 2.0` for Terraform, lock file committed, previews in their own root, upgrades via a PR that plans all three environments.
**Five operational traps:**

| Trap | Symptom | Fix |
| --- | --- | --- |
| Ambient workspace ID, not a reference | first apply of a new env fails 404/409 on item create; passes on retry | pass `fabric_workspace.x.id`; where unavoidable add `depends_on` and a fail-fast preflight |
| `fabric_workspace_git` treated as a passive binding | items vanish or revert on first apply; re-apply refuses as already connected | never Terraform-connect a workspace holding content; adopt with `PreferWorkspace` after disconnecting |
| Item definitions edited in the portal | a change disappears with no plan, diff or error | repo is the only source of truth for deployed items (ADR 0005); no portal edits |
| Apply against a paused or inactive capacity | plan wants to create what exists; state entries vanish | `postcondition` on the capacity data source; resume first; never apply while paused |
| Deleting the resource block to retire a workspace | `prevent_destroy` never fires; workspace and items go | keep blocks; hand off with `removed { … lifecycle { destroy = false } }` |

- **Boundary statement:** Terraform owns objects with an ID and a lifecycle (capacity, workspaces, grants, the Git connection, tenant settings); `fabric-cicd` owns item definitions; capacity overage, surge protection, pause/resume and retention stay manual. Anything on the wrong side has two writers and no arbiter.

## What this does not establish

- Whether `fabric_workspace` create waits for anything beyond capacity assignment; the read loop is clear, but I did not trace every create path, and a create returning before the capacity is `Active` would change the same-run answer.
- What `InitializeConnection` does when both sides are empty, or how `PreferWorkspace` reconciles item-by-item; only the enumeration's one-line descriptions are documented.
- Whether a restored workspace keeps its ID, and whether item IDs survive the retention window.
- What deleting a Fabric capacity does to the workspaces still assigned to it — not stated on the pause/resume or buy-capacity pages; treat as unverified, not survivable.
- Whether two workspaces may share a display name.
- Whether anything commits the provider to SemVer beyond the CHANGELOG's claim, which v1.6.0 contradicts; nothing in `CONTRIBUTING.md`.

## Sources

| Source | Used for | Dated |
| --- | --- | --- |
| [Provider docs][tfp] | `preview` argument, required_providers wording, exact-version example, Terraform >= 1.8 | checked 2026-11-12 |
| [fabric_workspace][tfw] | attributes, import format, `skip_capacity_state_validation` drift warning, no `ForceNew` | checked 2026-11-12 |
| [fabric_workspace_role_assignment][tfra] / [fabric_workspace_git][tfwg] | import format; no Import section, ForceNew strategy | checked 2026-11-12 |
| [fabric_tenant_setting][tfts] / [domain_role_assignments][tfdr] | no Import; `principals` Set + `ForceNew` | checked 2026-11-12 |
| [fabric_capacity data source][tfcap] | `state` read-only, recommended `postcondition` | checked 2026-11-12 |
| [Provider source @ v1.15.1][tfsrc] | capacity-assignment poll, item `get`/import, `source_content_sha256`, workspace_git Connect+Initialize | read 2026-11-12 |
| [CHANGELOG][tfchg] / [releases][tfrel] | v1.6.0 break in a minor, v1.10.0 ordering fixes, release cadence | v1.15.1, 2026-11-11 |
| [Quickstarts][qs] / [getting started][gs] | one root per example; capacity → data source → workspace | read 2026-11-12 |
| [Delete Workspace][delws] / [Retention and recovery][ret] | "and the items under it"; 7-day workspace, 3-day item retention | read 2026-11-12 |
| [Initialize Connection][gitinit] | `PreferRemote` / `PreferWorkspace` semantics | read 2026-11-12 |
| [workspaces][tfws] / [depends_on][tfdo] / [lifecycle][tflc] / [removed][tfrm] | workspace caveat; explicit vs implied dependency; `prevent_destroy` not in state; `destroy = false` | v1.17 docs, read 2026-11-12 |
| [backend][tfbe] / [plan][tfplan] / [remote state][tfrs] / [lock file][tflock] | state locking, `-refresh-only`, cross-root outputs, committed lock | v1.17 docs, read 2026-11-12 |
| [azapi][azapi] / [update_resource][azapiup] / [resource_action][azapiact] | hatch scope, delete no-op, state-modifying action warning | read 2026-11-12 |

[tfp]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/index.md
[tfw]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace.md
[tfra]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace_role_assignment.md
[tfwg]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace_git.md
[tfts]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/tenant_setting.md
[tfdr]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/domain_role_assignments.md
[tfcap]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/data-sources/capacity.md
[tfsrc]: https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/internal
[tfchg]: https://github.com/microsoft/terraform-provider-fabric/blob/main/CHANGELOG.md
[tfrel]: https://github.com/microsoft/terraform-provider-fabric/releases
[qs]: https://github.com/microsoft/fabric-terraform-quickstart/tree/main/quickstarts
[gs]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/guides/getting_started.md
[delws]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/delete-workspace
[ret]: https://learn.microsoft.com/en-us/fabric/admin/retention-recovery
[gitinit]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/initialize-connection
[tfws]: https://developer.hashicorp.com/terraform/language/state/workspaces
[tfdo]: https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on
[tflc]: https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
[tfrm]: https://developer.hashicorp.com/terraform/language/block/removed
[tfbe]: https://developer.hashicorp.com/terraform/language/backend/azurerm
[tfplan]: https://developer.hashicorp.com/terraform/cli/commands/plan
[tfrs]: https://developer.hashicorp.com/terraform/language/state/remote-state-data
[tflock]: https://developer.hashicorp.com/terraform/language/files/dependency-lock
[azapi]: https://github.com/Azure/terraform-provider-azapi/blob/main/docs/index.md
[azapiup]: https://github.com/Azure/terraform-provider-azapi/blob/main/docs/resources/update_resource.md
[azapiact]: https://github.com/Azure/terraform-provider-azapi/blob/main/docs/data-sources/resource_action.md

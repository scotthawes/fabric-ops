# Run-book 04 — Terraform deployment plan

**Dated 2026-11-26.** The control-plane deployment, phase by phase: what to run, what the plan
should contain, what to check before moving on, and what to do when it does not look right. This is
the human-readable equivalent of the pipeline stages in
[`reference/ado-pipeline.yml`](../reference/ado-pipeline.yml); the YAML is the mechanism, this is the
plan.

**Scope.** The two Terraform roots only — `terraform/platform` (the capacity) and
`terraform/workspaces` (groups, workspaces, identities, grants). Item definitions and schema are
spec 0001/ADR 0008; the preconditions are [run-book 03](03-pipeline-bootstrap.md); the estate
migration is [spec 0003](../specs/0003-migration-pathway.md). Not runnable from this repo (ADR 0001).

## The plan in one table

| Phase | State | What it creates | Gate | Exit criterion |
| --- | --- | --- | --- | --- |
| 0. Preconditions | none | nothing | run-book 03 complete | every step in 03 §1–7 verified |
| 1. Platform | `platform.tfstate` | resource group, shared capacity | `fabric-platform` (optional) | capacity `Active`, admin SP listed, second plan empty |
| 2. Dev | `workspaces/dev.tfstate` | 2 groups, 1 workspace + identity, 3 grants, dev Git binding | `fabric-dev` | workspace Active on the capacity, identity has Contributor |
| 3. Test | `workspaces/test.tfstate` | same, unbound | `fabric-test` | counts equal dev, plan empty |
| 4. Prod plan | `workspaces/prod.tfstate` | *nothing* — a plan file | none (read-only job) | plan published, approver can read it |
| 5. Prod apply | `workspaces/prod.tfstate` | the same 6 objects | `fabric-prod` approval | plan applied as approved, no replacement |
| 6. Content | none | items, then schema | per env | spec 0001 — not this plan |

Three facts the table cannot show:

- **One state per environment, one blob each.** Different locks, so dev and prod can run at once;
  the same configuration reaches all three, only the tfvars and key differ.
- **The capacity is never applied twice.** It lives only in `platform.tfstate`; every workspaces
  state reads it back as `data "fabric_capacity"` and refuses to run against an inactive one.
- **A plan is not portable.** Each phase plans against its own state. Prod's plan is made after dev
  and test succeed, and applied as a file — never re-planned behind the approval.

## Phase 1 — platform

**Run** (as `sp-fabric-admin`, from the Platform stage or by hand with the same connection):

```bash
terraform -chdir=terraform/platform init -input=false \
  -backend-config="key=platform.tfstate"
terraform -chdir=terraform/platform plan -input=false \
  -lock-timeout=5m -var-file=env/platform.tfvars -out=platform.tfplan
terraform -chdir=terraform/platform show platform.tfplan   # read it before applying
terraform -chdir=terraform/platform apply -input=false -lock-timeout=5m platform.tfplan
```

**The plan should contain exactly two resources to add:** `azurerm_resource_group.platform` and
`azurerm_fabric_capacity.shared`. Nothing else, and nothing to change or destroy.

**Stop if** the plan proposes replacing a capacity that already exists — import it instead
(`terraform import azurerm_fabric_capacity.shared <ARM id>`); recreating it detaches every
workspace. `prevent_destroy` guards an apply, not an import mistake.

**Verify:**

```bash
terraform -chdir=terraform/platform output capacity_name
terraform -chdir=terraform/platform plan -input=false -detailed-exitcode \
  -var-file=env/platform.tfvars        # exit code 0 = no changes
```

Then check the capacity's `state` is `Active` in the portal or by API, and that the admin SP's
object ID appears in `administration_members`. Record the capacity's **Fabric GUID** — the
workspaces root resolves it from the name, but the run-book wants it written down.

**Rollback:** generally not needed; the capacity is created once. Deleting the resource block is
forbidden — it bypasses `prevent_destroy`. If the capacity is wrong, resize in place or retire it
deliberately with a `removed { lifecycle { destroy = false } }` hand-off.

## Phase 2 — dev

**Run:**

```bash
terraform -chdir=terraform/workspaces init -input=false \
  -backend-config="key=workspaces/dev.tfstate"
terraform -chdir=terraform/workspaces plan -input=false \
  -lock-timeout=5m -var-file=env/dev.tfvars -out=dev.tfplan
terraform -chdir=terraform/workspaces show dev.tfplan
terraform -chdir=terraform/workspaces apply -input=false -lock-timeout=5m dev.tfplan
```

**Expected first apply — seven resources without a storage grant, eight with one:**

| Resource | Count | Note |
| --- | --- | --- |
| `azuread_group.this` | 2 | `…-dev-contributors`, `…-dev-viewers` |
| `fabric_workspace.this` | 1 | with `identity { type = "SystemAssigned" }` |
| `fabric_workspace_role_assignment.groups` | 2 | one per group |
| `fabric_workspace_role_assignment.identity` | 1 | the identity's own Contributor |
| `fabric_workspace_git.dev` | 1 | dev only |
| `azurerm_role_assignment.identity_storage` | 0 or 1 | only when a storage account ID is supplied |

A plan that shows **zero** role assignments, or a workspace with no identity, is a configuration
error — not an empty workspace. Stop and read the tfvars.

**Verify, in this order:**

1. `terraform output workspace_id` and `terraform output workspace_identity_principal_id` both
   return values (not null).
2. The workspace is `Active` on `fabric-sales-forecast-shared` — the `data` source's postcondition
   already enforced this at plan time; check it again after apply.
3. The two groups exist in Entra with the named human as **owner** (`az ad group owner list`), and
   each carries `Contributor` / `Viewer` — never `Admin`.
4. The workspace identity is `Active` and holds `Contributor`.
5. A second plan is empty.

**Rollback:** revert the commit and apply. For a single bad object, fix the tfvars and re-apply; do
not `-target` a resource, which leaves the rest of the plan unapplied and the next plan confusing.

## Phase 3 — test

Identical to dev with `env/test.tfvars`, `key=workspaces/test.tfstate`, and `bind_git = false`.
**Exit criterion is a comparison, not an absolute:** the plan adds the same six resources dev added
(test has no Git binding), and the resulting role-assignment count matches dev. A difference with no
corresponding tfvars difference is the signal that an environment key leaked into a shared default.

Test is also where **the prod plan is produced** — its last job, after both test deploys:

```bash
terraform -chdir=terraform/workspaces init -input=false \
  -backend-config="key=workspaces/prod.tfstate"
terraform -chdir=terraform/workspaces plan -input=false \
  -lock-timeout=5m -var-file=env/prod.tfvars -out=prod.tfplan
```

Publish `prod.tfplan` as an artefact. This job reads prod state; it changes nothing.

## Phase 4 — prod apply

**Run** (Prod stage, after the `fabric-prod` approval; no `plan`, no `-var-file`):

```bash
terraform -chdir=terraform/workspaces init -input=false \
  -backend-config="key=workspaces/prod.tfstate"
terraform -chdir=terraform/workspaces apply -input=false -lock-timeout=5m \
  "$(Pipeline.Workspace)/tfplan-prod/prod.tfplan"
```

`init` is required even though the plan exists: it loads the providers and the backend. It does not
re-plan, and it cannot change what the approved file does.

**The plan the approver reads** should add six resources and replace nothing. If it proposes
replacing `fabric_workspace.this` or `azurerm_fabric_capacity`, reject and investigate — a
replacement is a new workspace ID, a new identity, and lost role assignments.

**If the apply reports the plan is stale:** prod state changed between plan and apply. Do not
`-refresh=false`, do not force it. Re-run Phase 3's plan job (a new Test run), get a new approval.

## Phase 5 — steady state

| Change | Do | Watch for |
| --- | --- | --- |
| New workspace in the same project | new tfvars entry and state key, or a new root per project — not a `for_each` over environments | one state, one workspace; a map of workspaces in one state widens the blast radius |
| Capacity SKU | `-var capacity_sku=F8` in the platform root, plan, apply | in-place update; read the plan for `-/+` |
| Provider upgrade | bump the exact pin + lock file, `plan` all four states, read the changelog for breaking minors | v1.6.0 shipped a break in a minor |
| Retire a workspace | add the `removed` block with `destroy = false`, then remove the Terraform resources in a later change | items and identity survive the block removal; the workspace is not deleted |
| New environment | not in this design — there are three, by naming rule 3 | a fourth environment is a new decision, not a variable |

**Adding a second project** is the common case. Do not add a second `fabric_workspace` to an
existing state: copy the root or turn it into a module applied with a state key per
`project/env`. Two workspaces in one state means one plan can recreate both, and a dev failure
blocks a prod change.

## A plan you must stop on

| In the plan | Why it is wrong | Do |
| --- | --- | --- |
| `-/+` on `fabric_workspace` or `azurerm_fabric_capacity` | replacement: new IDs, lost identity, lost grants | find the forcing change; never apply |
| `-` on `azuread_group` | the group's object ID churns under every external reference | `prevent_destroy` should have caught it; investigate the block |
| zero `fabric_workspace_role_assignment` | the groups were not resolved/created; access would be empty | check `groups` in tfvars and the Graph consent |
| the workspace has no `service_principal_id` after apply | identity provisioning failed | re-apply once; if it persists, check `provisionIdentity` and the workspace-admin role |
| `data.fabric_capacity` postcondition fails | capacity paused or invisible to the caller | resume it; do not set `skip_capacity_state_validation` |
| counts differ between test and dev with no tfvars diff | an environment value leaked | stop before prod; find the shared default |

## Rollback, honestly

| Situation | Reversible? | How |
| --- | --- | --- |
| Bad config in dev or test | yes | revert the commit, re-apply; state records what exists |
| Bad prod apply | mostly | revert and re-apply; a deleted workspace is soft-deleted for 7 days |
| Workspace deleted | **no** | restore returns a **new ID**; identity, Git binding and grants are stale |
| Workspace identity deprovisioned | **no** | restore does not recreate it; new app and SP IDs |
| Group deleted, then purged | **no** | role assignment dangles (#18 in the backlog) |
| State file corrupted | yes, if versioning is on | restore the blob version or `terraform state pull` from a backup |

The rule behind the table: **Terraform can rebuild a container, not what lived inside it.** Items,
identity and grants are the contents; the workspace is the container.

## Who runs which phase

| Phase | Principal | Human involvement |
| --- | --- | --- |
| 0 | — | all of it (run-book 03) |
| 1 | `sc-fabric-admin` | optional approval on `fabric-platform` |
| 2–3 | `sc-fabric-admin` | review the plan in the PR; optional env approval |
| 4 | `sc-fabric-admin` | **required** approval on `fabric-prod`, reading the plan |
| content | `sc-fabric-deploy` | none beyond the prod approval |

## What this plan does not cover

- Item definitions, schema and the content pipeline — spec 0001, ADR 0003, ADR 0008.
- The tenancy facts still unverified (SP licensing, capacity Contributor, private link); run-book 01.
- Anything about the work tenant's actual settings or state. Every check here is documentation-derived
  until it is run once there.

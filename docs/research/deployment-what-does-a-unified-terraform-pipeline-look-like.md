# What does a unified Terraform pipeline deploy, in what order, and what does it promote from non-production to production?

- **Status:** answered
- **Checked:** 2026-11-26
- **Blocks:** the work repo's pipeline topology, and three recorded positions it contradicts —
  [ADR 0010](../adr/0010-delegation-and-administration-model.md) §2 (groups stay manual),
  [spec 0001](../specs/0001-fabric-deployment-pipeline.md) ("one Terraform root"; groups out of scope),
  and [ADR 0002](../adr/0002-two-service-principals-federated.md)'s "prefer separate pipelines"
- **Siblings:** [`terraform-operating-model.md`](terraform-operating-model.md) (layout, ordering,
  deletion), [`terraform-provider-surface.md`](terraform-provider-surface.md) (resource inventory,
  auth), [`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md) (connections, approvals, agents),
  [`workspace-identity.md`](workspace-identity.md) (what the identity is and what it cannot do),
  [`entra-and-ado-operations.md`](entra-and-ado-operations.md) (Graph and ADO operations).

## Short answer

"One pipeline" is a pipeline *definition*, not one root: it is four bands over three state scopes —
a shared `platform` state holding the capacity, a per-environment `workspaces` state holding groups,
workspaces, identities and grants, and a content band with no state at all. The capacity is applied
once and read back by each environment as a `data` source; the environments are separate blobs in one
container, applied in order dev → test → prod. What is promoted is the **commit** (plus the lock
file) for Terraform and a **built content artefact** for `fabric-cicd`; a Terraform plan is per state
and cannot be promoted, so prod must plan against prod state *after* the last change to it and apply
that saved plan behind the approval. Entra groups are the one band not forced by the tooling: putting
them in the workspaces root buys a real dependency edge and costs `Group.Create` + `User.Read.All`,
so it is an amendment to ADR 0010, not a pipeline detail.

## Detail

### 1. The shape: four bands, three state scopes

| Band | Root | State | Principal | Runs |
| --- | --- | --- | --- | --- |
| 0. Bootstrap | none | none | a human | once |
| 1. Platform | `terraform/platform/` | `platform.tfstate` | `sc-fabric-admin` | when the capacity changes, rarely |
| 2. Containers | `terraform/workspaces/` | `workspaces/dev\|test\|prod.tfstate` | `sc-fabric-admin` | every merge that touches the control plane |
| 3. Content | `content/` + a deploy script | none (`fabric-cicd` is stateless) | `sc-fabric-deploy` | after band 2, per environment |

Band 1 is ADR 0007's `capacity` root, renamed because it also owns the resource group and the
capacity's `administration_members`. Band 2 is ADR 0007's `workspaces` root. The note adds no root
unless groups go into a state of their own (§4).

The three state keys are three independent locks on three blobs in one container: the
[`azurerm` backend][tfbe] stores state "as a Blob with the given Key within the Blob Container" and
"supports state locking and consistency checking with Azure Blob Storage native capabilities". A
dev apply therefore cannot block a prod apply, which is the concurrency property spec 0001 asks
for. The backend authenticates with Entra ID, not a key: `use_azuread_auth = true`, `use_oidc = true`,
and `oidc_azure_service_connection_id`; the identity needs **Storage Blob Data Contributor** on the
container ("Recommended for least privilege"). In an `AzureCLI@2` job the connection ID is already
in `AZURESUBSCRIPTION_SERVICE_CONNECTION_ID`, so it is one variable, not a secret.

### 2. Why "unified" cannot mean one root

Four facts, each already established elsewhere in the pack, decide it:

1. **The capacity must not be created three times.** It is an Azure resource that outlives every
   environment (ADR 0004, ADR 0007). A single root applied once per environment would either create
   three capacities or need `count = var.env == "prod" ? 1 : 0` — a conditional that makes every
   plan differ by environment and gives one failure the blast radius of all three.
2. **Terraform CLI workspaces are ruled out** for exactly this case: HashiCorp says they are "not
   appropriate for … deployments requiring separate credentials and access controls", and ADR 0002
   requires two principals ([terraform-operating-model §1](terraform-operating-model.md)).
3. **Credentials differ by band, not by environment.** Band 1 and 2 need `sc-fabric-admin`; band 3
   needs `sc-fabric-deploy`. One root cannot switch identity between resources.
4. **`preview` is provider-wide.** One preview resource in a root turns preview on for everything in
   it ([provider surface §2](terraform-provider-surface.md)); keeping previews out of the root that
   touches production is only possible if the root is small.

The same reasoning is why the roots are split by **lifetime**, not by environment: the capacity's
state changes yearly, the workspaces' state changes weekly, and the content changes daily.

### 3. The bands in order

**Band 0 — bootstrap, once, by a person.** The pipeline cannot create its own preconditions:

1. A resource group and storage account for state, and `Storage Blob Data Contributor` on the
   container for `sp-fabric-admin`.
2. Two app registrations and their federated credentials, two ADO service connections
   (`sc-fabric-admin`, `sc-fabric-deploy`) — the order and the draft/finish dance are in
   [`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md) §1.
3. One ADO **environment per gated stage**, each with its Approvals check.
4. **Graph application permissions and admin consent** for `sp-fabric-admin` — a Privileged Role
   Administrator, human, by design ([`entra-and-ado-operations.md`](entra-and-ado-operations.md)).
   The set depends on §4.
5. Tenant settings: "Service principals can call Fabric public APIs", "Service principals can
   create workspaces, connections, and deployment pipelines", and **Create workspaces** scoped to a
   platform group rather than `Everyone`.
6. Azure rights for `sp-fabric-admin` to create the resource group/capacity — Contributor on the
   subscription, or a pre-created resource group it can write to. If the capacity already exists,
   import it rather than recreating it.

**Band 1 — the platform, one state.** `azurerm_fabric_capacity` with
`administration_members = [sp-fabric-admin object id]`. This is the important detail: the provider
documents the member as "an Entra user or a service principal" (object ID for an SP), and Create
Workspace requires the caller to "have *contributor* permissions or be an Admin on the capacity".
Making the automation principal a **capacity administrator** therefore sidesteps the open question
"can an SP hold capacity Contributor" (issue #15) for the pipeline's own needs; whether that is
acceptable breadth is a decision, not a fact. The `capacity_id` consumed downstream is the Fabric
GUID, not the ARM ID — `data "fabric_capacity"` with a `postcondition` on `state == "Active"`
([provider surface §5](terraform-provider-surface.md)).

**Band 2 — containers, one state per environment.** The order inside the root is forced by three
references, not by taste:

| Step | Resource | Edge |
| --- | --- | --- |
| 1 | `data "fabric_capacity"` | `display_name` from band 1; postcondition on `Active` |
| 2 | `azuread_group` × roles, if in code | name derived from the workspace name (§4) |
| 3 | `fabric_workspace` | `capacity_id = data.fabric_capacity.x.id`; `identity = { type = "SystemAssigned" }` |
| 4 | `fabric_workspace_role_assignment` per group | `workspace_id = fabric_workspace.x.id`, `principal_id = azuread_group.y.object_id` |
| 5 | `fabric_workspace_role_assignment` for the identity | `principal_id = fabric_workspace.x.identity[0].service_principal_id` |
| 6 | `azurerm_role_assignment`, identity → storage | storage scope is a reference from the storage root or a data source (§5) |
| 7 | resource instance rule on the storage account | `azapi_update_resource`; no AzureRM resource documents it (§5) |
| 8 | dev only: `fabric_workspace_git` | after the grants that must precede it (ADR 0005) |

Steps 2 and 3 can run in parallel; step 4 orders both. Step 5 is a **direct grant to a service
principal**, which ADR 0006 permits only as an exception for people — the workspace identity is a
workload, not a person, but the exception should be written down rather than inferred.

**Band 3 — content.** `fabric-cicd` over the same commit, per environment, after band 2 in that
environment, then the schema step (ADR 0003, ADR 0008). No Terraform state, no Terraform lock: a
content deploy may run while another environment's control plane is being applied, which is what
"safe to run concurrently for different environments" means in practice.

### 4. Entra groups: the decision this forces

ADR 0010 §2 keeps group creation manual and refuses directory write on the platform principal.
`entra-and-ado-operations.md` lists `sp-fabric-admin` as *able* to create the 3N groups, and
[`what-goes-where.md`](../guides/what-goes-where.md) puts them in the manual column. The pack
therefore contains a capability, a decision, and a guide that disagree; the ADR is the most recent
and wins until it is amended. Moving groups into the pipeline has a precise price:

| | Manual (ADR 0010) | Code, same root as workspace | Code, separate `identity` root |
| --- | --- | --- | --- |
| Graph permissions on the SP | none | `Group.Create` + `User.Read.All` if a human is owner | same |
| Dependency edge to the role assignment | none — a missing group fails plan | resource reference, one apply | stage order or `terraform_remote_state` |
| Group object ID across a workspace rebuild | stable | **churns** unless protected | stable |
| Deleting the workspace | group remains, owned by a human | destroys the group too, unless `prevent_destroy` | group remains |
| Review surface | a human step, invisible in the diff | a directory change in the same plan | a directory change in its own plan |

The permission line is the one usually guessed wrong. `azuread_group`'s own documentation says the
least privileged application permissions are **`Group.Create`** plus one of `User.Read.All`
(users as owners/members), `Application.Read.All` (other service principals) or `Directory.Read.All`
(either). So an SP-created group with a *named human owner* — which is what ADR 0010 §3 delegates
membership to — also buys `User.Read.All`, not just group write. The provider's default gives the
applying principal sole ownership ("By default, the principal being used to execute Terraform is
assigned as the sole owner"), which is permitted ("Groups cannot be created with no owners") but
leaves the human-owner step to be done afterwards — the manual click returns, one level down.

Two more facts change the "name is the contract" reasoning in ADR 0010 §2:

- **Group display names are not unique.** "Group names are not unique within Azure Active
  Directory"; `prevent_duplicate_names` defaults to `false`. A `data "azuread_group"` lookup by name
  is ambiguous the moment a second group shares it. Workspace names, by contrast, are unique:
  Create Workspace accepts "only unused workspace names".
- **Group deletion is a 30-day soft delete**, but for cloud security groups "soft delete and restore
  … is in preview and available only in public clouds" ([restore a deleted group][grpdel]). A group
  deleted and then permanently purged leaves the workspace role assignment pointing at an object
  that no longer exists — the open question in the backlog (#18), and the reason the group's
  lifecycle should be deliberate rather than incidental to the workspace's.

**Recommendation.** Keep groups manual for the current scale. Three environments' worth of groups
is a one-time creation per new workspace, not a recurring cost, and it does not justify standing
directory write on the most privileged principal in the design. If the team decides otherwise, put
the groups in the **workspaces root** so the role assignment has a resource edge, set
`prevent_duplicate_names = true`, and add `lifecycle { prevent_destroy = true }` so a workspace
rebuild cannot silently churn the group's object ID. Do not use a separate root unless a different
team owns the directory; the lookup or remote-state hop buys nothing for three environments. Either
way, ADR 0010 §2 and the "Entra groups" row in `what-goes-where.md` must be amended together, and
spec 0001's "Entra groups from code" out-of-scope line corrected.

### 5. Workspace identity inside the run

`fabric_workspace` exposes `identity` with the single value `type = "SystemAssigned"` and exports
`application_id` and `service_principal_id` read-only ([workspace resource][tfws], checked
2026-11-26). That makes the identity a property of the workspace in Terraform even though the API
provisions it with a separate POST — the provider hides the ordering, and the computed
`service_principal_id` is what steps 5–7 above reference, giving same-run ordering.

Three consequences for a pipeline:

- **Grant it a workspace role deliberately.** A workspace identity "holds no workspace role until
  one is granted", and trusted workspace access wants Contributor ([`workspace-identity.md`](workspace-identity.md)
  §5–6). Step 5 is that grant.
- **The identity is not replaceable in production.** Permanently deleting the workspace deprovisions
  the identity, and a restore from soft delete does **not** restore it — new application and service
  principal IDs, so every Azure RBAC assignment and connection goes stale. That is why the
  workspaces root carries `prevent_destroy` on `fabric_workspace`, and why retirement is a
  `removed { lifecycle { destroy = false } }` hand-off rather than deleting a block (the block
  removal bypasses `prevent_destroy` — [operating model §3](terraform-operating-model.md)).
- **The resource instance rule is still outside the provider.** Neither `azurerm_storage_account` nor
  its network-rules resource documents `resource_access_rules`, so a firewall-enabled storage
  account needs `azapi_update_resource` on `networkAcls.resourceAccessRules` or an ARM template
  ([`workspace-identity.md`](workspace-identity.md) §5, §7). Treat it as a field hatch, not an
  object: the `azapi` guidance in the operating model is that one object must have one owner.

The identity also needs a workspace role **at run time** for any pipeline that uses it: Fabric
"issues a workspace identity token only to an identity that holds one of these roles … both to the
user who runs the pipeline on demand and to the service principal that runs it on a schedule"
([`workspace-identity.md`](workspace-identity.md) §6). So `sp-fabric-deploy` needs Contributor in
every workspace it runs data pipelines in, which it already has.

### 6. Promotion: what is promoted, and what a plan is worth

Two artefacts promote, and they promote differently.

| | Terraform (bands 1–2) | Content (band 3) |
| --- | --- | --- |
| What is promoted | the commit, the `.terraform.lock.hcl`, and the pinned provider version | the content bundle built once in `Build` |
| What differs per environment | `env/<env>.tfvars` and the state key | `parameter.yml` keys |
| Where the plan is made | per environment, against that environment's state | n/a |
| What the gate approves | the prod plan | the prod run |

**A Terraform plan is not portable.** `-out=FILE` writes "an opaque file format" containing "your
full configuration, all of the values associated with planned changes, and all of the plan options
including the input variables", and "if your plan includes any sort of sensitive data … it will be
saved in cleartext" ([plan docs][tfplan]). It is bound to the state snapshot it was made against,
so the dev plan cannot approve the prod apply. HashiCorp also warns that a speculative plan can
differ from the final one, because "other changes made to the target system in the meantime might
cause the final effect … to be different" — the same reasoning applies between an approved plan and
a later state change.

**Where the prod plan lives.** ADO evaluates an environment's approval checks when the stage
*starts*, not when a job inside it starts, so a plan produced inside the prod stage is approved
before anyone has seen it. Spec 0002 already contains the refinement: **put the prod plan in the
last job of the test stage**, publish it, gate the prod environment on a human, and have the prod
stage do nothing but `terraform apply <planfile>`. Passing a saved plan is itself the approval —
`-auto-approve` is ignored when a plan file is passed ([apply docs][tfapply]) — so the plan file
is the thing the approver must actually read, and its retention and artifact permissions are part
of the control.

The cost is honest: if anything changes prod state between the plan and the apply, the plan is stale
and the run must re-plan, which means a second approval. That is the price of "what was approved is
what runs"; the alternative — plan-and-apply inside the prod stage — approves a diff nobody saw.

### 7. Authority in one YAML

ADR 0002 splits the principals and says "prefer separate pipelines", because "a single run that
deploys and then grants access has to switch identity mid-flight". A unified pipeline does exactly
that. The workable compromise is one pipeline file with two authority tracks:

| Stage | Job | Connection | Can |
| --- | --- | --- | --- |
| `platform` | apply | `sc-fabric-admin` | capacity, resource group |
| `dev` / `test` | control plane | `sc-fabric-admin` | groups, workspaces, identities, role assignments |
| `dev` / `test` | content | `sc-fabric-deploy` | item definitions only |
| `prod` | apply plan | `sc-fabric-admin` | same as test, behind the approval |
| `prod` | content | `sc-fabric-deploy` | item definitions only |

The structural risk is that one authorised pipeline can use either connection, so a YAML change on
the merge path could put admin rights behind a content step. The controls are the ones already
recorded: branch policy on `main`, deny "Edit build pipeline" to Contributors, per-pipeline
authorisation on each connection, and an **Exclusive lock** on each environment so an admin run and
a content run cannot overlap. If those are judged insufficient, the split has to become two
pipeline files chained by a completion trigger — unified *entry point*, separate *credentials*. The
pack should not claim the single file is as safe as two; it is as safe as its permissions.

### 8. The YAML, illustratively

Labelled illustrative, 2026-11-26 — not a manifest, and not deployable (ADR 0001). It shows only the
shape the sections above force.

```yaml
stages:
  - stage: Build
    jobs:
      - job: bundle
        steps:
          - publish: content
            artifact: fabric-content        # built once; every deploy stage consumes this

  - stage: Platform
    jobs:
      - deployment: capacity
        environment: fabric-platform        # approval optional; changes rarely
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - bash: terraform -chdir=terraform/platform init -backend-config=...
                - bash: terraform -chdir=terraform/platform plan -out=plan.tfplan
                - bash: terraform -chdir=terraform/platform apply plan.tfplan

  - stage: Dev
    dependsOn: Platform
    jobs:
      - deployment: control
        environment: fabric-dev
        steps: [terraform init/plan/apply, terraform/workspaces, key=workspaces/dev.tfstate]
      - deployment: content
        environment: fabric-dev
        steps: [download artifact, python scripts/deploy_items.py --env dev]

  - stage: Test
    dependsOn: Dev
    jobs: [same shape, key=workspaces/test.tfstate, then a final job that plans prod]

  - stage: Prod
    dependsOn: Test
    jobs:
      - deployment: apply
        environment: fabric-prod            # Approvals check; timeout marks the stage skipped
        steps: [terraform apply prod.tfplan] # the plan made in the Test stage's last job
      - deployment: content
        environment: fabric-prod
        steps: [deploy the same content artefact]
```

Two mechanical details the sketch hides. `terraform init` must run with the **same connection ID
under three different variable names** in one job: `ARM_OIDC_AZURE_SERVICE_CONNECTION_ID` for
`azurerm`/`azuread`, `FABRIC_AZURE_DEVOPS_SERVICE_CONNECTION_ID` for the Fabric provider, and
`FABRIC_OIDC_REQUEST_TOKEN: $(System.AccessToken)` ([azuread index][azad], [azurerm backend][tfbe],
[provider surface §3](terraform-provider-surface.md)). And an `apply` long enough to outlive the
assertion fails with `AADSTS700024` — the assertion expires "after approximately 1 hour" — so the
apply gets its own job rather than sharing one with everything else ([`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md) §3).

### 9. What breaks

| Symptom | Mechanism | Response |
| --- | --- | --- |
| A green-looking run where prod never deployed | approval **timeout** marks the stage *skipped*, not failed | `isSkippable: false` on guards; read skipped as "did not run" |
| Prod apply runs a diff nobody approved | plan made inside the prod stage, after the gate | plan in the last job of the test stage; prod applies the file |
| Prod apply fails as stale | state changed between plan and apply | re-plan and re-approve; do not `-refresh=false` to force it |
| First apply of an environment fails 404/409 on item create | ambient capacity or workspace ID has no graph edge | reference `fabric_workspace.x.id`; never pass IDs as strings |
| Workspace identity gone, RBAC stale | workspace restored from soft delete | never destroy in prod; `prevent_destroy` plus a `removed` block |
| Group object ID changed under an external reference | group shared the workspace's lifecycle | `prevent_destroy` on the group, or a separate identity root |
| Plan proposes destroying items it does not own | Terraform holds no item definitions | items stay with `fabric-cicd`; never import one into state |
| Apply against a paused capacity wants to recreate what exists | `skip_capacity_state_validation` warns state may vanish | postcondition on the capacity; resume before applying |
| Content and admin runs collide | state locks are per blob; Fabric items have no lock | Exclusive lock on the environment; one content job per workspace |

## What this settles

- **Topology:** one pipeline definition, four bands, three state scopes — `platform.tfstate`,
  `workspaces/{dev,test,prod}.tfstate`, and stateless content. The capacity is applied once and read
  per environment; it is never in a per-environment state.
- **Ordering:** capacity → (groups) → workspace + identity → role assignments → storage RBAC and
  resource instance rule → dev Git binding → content.
- **Promotion:** the commit and the lock file promote for Terraform; the built content bundle
  promotes for `fabric-cicd`; a Terraform plan is per state, produced for prod in the test stage's
  last job and applied behind the approval.
- **Identity:** `sp-fabric-admin` becomes a capacity **administrator** via `administration_members`,
  which sidesteps open question #15 without answering it; `sp-fabric-deploy` never touches the
  control plane.
- **Groups:** keep them manual at the current scale. If they move into code, they belong in the
  workspaces root with `Group.Create` + `User.Read.All`, `prevent_duplicate_names = true` and
  `prevent_destroy`.

**Decision impact — three recorded positions need an explicit amendment, not a silent edit:**

| Document | What it says | What this note would change |
| --- | --- | --- |
| [ADR 0010](../adr/0010-delegation-and-administration-model.md) §2 | group creation manual; directory write refused | **amended 2026-11-26** — groups are created in the workspaces root with `Group.Create` (+ `User.Read.All` for a human owner); §3 ownership and §4 the Admin assertion are unchanged |
| [spec 0001](../specs/0001-fabric-deployment-pipeline.md) | "One Terraform root"; groups out of scope | **corrected 2026-11-26** — two roots per ADR 0007, the prod plan made in Test, and groups moved into scope |
| [ADR 0002](../adr/0002-two-service-principals-federated.md) | "prefer separate pipelines" | record the single-file/two-track compromise and the controls that make it defensible |

## What this does not establish

- Whether a service principal can hold capacity **Contributor** (issue #15) — the design avoids the
  question by using `administration_members`, which the provider documents as accepting an SP object
  ID, but that is a broader grant and a tenant fact remains open.
- Whether `fabric_workspace`'s `identity` block can be **added to or removed from an existing
  workspace in place**, or what `terraform import` does with an existing identity. The schema shows
  no `ForceNew`; that is not proof.
- Whether `fabric_workspace_role_assignment` accepts a workspace identity's service principal as a
  principal in every tenant — the schema lists `ServicePrincipal`, but nothing was executed.
- Whether an SP-owned group with a human co-owner is editable by that human in every tenant
  configuration, which is what ADR 0010's delegation model would then depend on.
- What Fabric displays for a role assignment whose group has been permanently purged (issue #18).
- Whether the Fabric provider tolerates being initialised with `ARM_*` and `FABRIC_*` variables in
  the same job on a self-hosted agent — the variable names are documented, the combination was not
  run.
- Anything observed in a real tenant or organisation: no apply, plan or Graph call was executed.

## Sources

| Source | Used for | Checked |
| --- | --- | --- |
| [`fabric_workspace` resource](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace.md) | `identity` block and computed `service_principal_id`; capacity and skip-validation attributes; import by workspace ID | 2026-11-26 |
| [Create Workspace](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/create-workspace) (rev. 2026-09-24) | create permission, capacity contributor/admin, the SP tenant setting, "only unused workspace names" | 2026-11-26 |
| [Restore a deleted group](https://learn.microsoft.com/en-us/entra/identity/users/groups-restore-deleted) (2026-03-11) | 30-day retention; cloud security group soft delete in preview | 2026-11-26 |
| [`azurerm` backend](https://developer.hashicorp.com/terraform/language/backend/azurerm) (v1.17) | blob/state locking, `use_azuread_auth`, OIDC and the ADO connection ID, Storage Blob Data Contributor | 2026-11-26 |
| [`terraform plan`](https://developer.hashicorp.com/terraform/cli/commands/plan) (v1.17) | `-out`, plan file contents and sensitivity, speculative vs final plan, `-target` caveat | 2026-11-26 |
| [`terraform apply`](https://developer.hashicorp.com/terraform/cli/commands/apply) (v1.17) | saved plan is the approval; `-auto-approve` ignored; no rollback | 2026-11-26 |
| [`azuread` provider](https://github.com/hashicorp/terraform-provider-azuread/blob/main/docs/index.md) | OIDC arguments and ADO environment variables | 2026-11-26 |
| [`azuread_group`](https://github.com/hashicorp/terraform-provider-azuread/blob/main/docs/resources/group.md) | `Group.Create` + read permission set, owner default, `prevent_duplicate_names`, non-unique names | 2026-11-26 |
| [`terraform-operating-model.md`](terraform-operating-model.md) | layout, ordering, `prevent_destroy`, `removed`, paused-capacity drift | 2026-11-12 |
| [`terraform-provider-surface.md`](terraform-provider-surface.md) | capacity GUID vs ARM ID, `administration_members`, provider auth, preview flag | 2026-11-12 |
| [`ado-pipeline-mechanics.md`](ado-pipeline-mechanics.md) | connections, approvals at environment, assertion expiry, artifact promotion | 2026-11-12 |
| [`workspace-identity.md`](workspace-identity.md) | identity lifecycle, restore behaviour, runtime role check, resource instance rule | 2026-11-12 |
| [`entra-and-ado-operations.md`](entra-and-ado-operations.md) | Graph permissions, admin consent, app-only capability | 2026-11-12 |

[tfws]: https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace.md
[tfbe]: https://developer.hashicorp.com/terraform/language/backend/azurerm
[tfplan]: https://developer.hashicorp.com/terraform/cli/commands/plan
[tfapply]: https://developer.hashicorp.com/terraform/cli/commands/apply
[azad]: https://github.com/hashicorp/terraform-provider-azuread/blob/main/docs/index.md
[grpdel]: https://learn.microsoft.com/en-us/entra/identity/users/groups-restore-deleted

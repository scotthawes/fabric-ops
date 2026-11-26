# Run-book 03 — Pipeline bootstrap

**Dated 2026-11-26.** The human steps that must happen before the pipeline's first run, and the order
the first run takes. Written for the platform engineer who builds the work repo's pipeline, and for the
tenant administrator who has to sit beside them for four of the ten steps.

**The pipeline cannot create any of its own preconditions.** Every item in §1–§7 is a tenant setting, a
directory permission, an Azure role or an Azure DevOps object that only a human — or a principal
holding rights the pipeline will never hold — can create. That is band 0 of
[the pipeline design](../research/deployment-what-does-a-unified-terraform-pipeline-look-like.md#3-the-bands-in-order),
and nothing in the YAML can be written to work around it.

Not runnable from this repo ([ADR 0001](../adr/0001-research-artefact-not-deployment-tool.md)). Names,
state keys and the stage graph are fixed by
[the pipeline contract](../reference/pipeline-contract.md); this page adds only the order and the
checks. `PLACEHOLDER` marks a value the work repo supplies; `00000000-0000-0000-0000-000000000000`
stands in for every GUID, `1111…` for `sp-fabric-admin`'s object ID and `2222…` for
`sp-fabric-deploy`'s.

Two conventions. **VERIFY** marks a claim that is a tenant fact, was not executed here, or drifts —
check it in the tenant and write the date beside it. Command shapes come from the CLI and provider
references and were not run (ADR 0001); a flag that does not exist will fail before it changes
anything, which is the cheap half of the risk.

## Steps at a glance

| # | Step | Who can do it | Once or repeatable |
| --- | --- | --- | --- |
| 1 | State storage: resource group, storage account, `tfstate` container, data-plane grant | Azure subscription **Owner** (or Contributor **plus** User Access Administrator) | once per tenant |
| 2 | Two app registrations and service principals | Entra **Application Administrator**, or an existing admin principal | once per principal; repeatable on rotation |
| 3 | Graph application permissions and admin consent | **Privileged Role Administrator**, a human, by design | once per permission set |
| 4 | Two ADO service connections, workload identity federation, per-pipeline authorisation | **Project Collection Administrator** for the first SP; then a **Project Administrator** | once per connection; repeatable on rename or re-issuer |
| 5 | Four ADO environments with approvals, branch control, exclusive lock | **Project Administrator** | once; approver lists repeatable |
| 6 | Three Fabric tenant settings | **Fabric administrator** | once; drifts silently, so re-check |
| 7 | Azure rights: capacity administrator, Contributor, resource provider | **Subscription Owner** or **capacity admin** | once |
| 8 | First run, in stage order | automation (`sc-fabric-admin`, `sc-fabric-deploy`) **plus** the prod approver | once, then every merge |
| 9 | Verification after the first full run | platform engineer | after the first run; repeatable |
| 10 | The residue that stays manual | named humans | forever |

**Steps 2 and 4 interleave, and the order is forced.** The federated credential cannot be created until
the service connection exists, and the connection cannot be finished until the credential exists. §2
creates the identities and the credential *shape*; §4 creates the connection between them and hands the
issuer and subject back. Do not reorder those into "identities, then credentials, then connections" —
it produces a connection whose `Verify` fails with a message that looks like a wrong tenant.

## Failure modes first

| Symptom | Mechanism | Do this instead |
| --- | --- | --- |
| Prod stage goes green and nothing was deployed | approval **Timeout** marks the stage `skipped`, not failed | read `skipped` as "did not run"; alert on it; `isSkippable: false` on guard stages ([ADO note §2](../research/ado-pipeline-mechanics.md#2-approvals-and-checks)) |
| Apply dies an hour in with `AADSTS700024` | the federated **assertion** expires after roughly an hour; the access token is not the thing that expired | one `apply` per job; re-acquire per long step |
| Group create fails on a duplicate name, or two groups answer one name | Entra display names are **not unique** | `prevent_duplicate_names = true`; resolve groups by object ID, never by name at run time |
| Plan wants to recreate what already exists | capacity is **paused**, and Fabric may have dropped state | `postcondition` on `state == "Active"`; resume before applying; never `skip_capacity_state_validation` to get past it |
| The group exists and nobody can edit it | an SP-created group with no owner is created "anonymously" and is not modifiable | set `owners@odata.bind`; require a named human owner; check Owners, not just existence |
| Second run blocks, first run is dead | state locks are **per blob**, and a killed run leaves one held | confirm no run is live, then `terraform force-unlock`; the Exclusive lock in §5 is what stops the overlap that causes it |

## 1. State storage

- **Create:** one resource group for state — **`rg-fabric-tfstate`, deliberately not the resource group the
  platform root manages** — one storage account, one container `tfstate`. One container holds every
  state key — `platform.tfstate`, `workspaces/{dev,test,prod}.tfstate` — because they are independent
  locks on independent blobs ([contract §2](../reference/pipeline-contract.md)). Keeping state in
  `rg-fabric-sales-forecast` would put the state inside the lifecycle of the root that reads it.
- **Path or command:**
  ```bash
  az group create --name rg-fabric-tfstate --location PLACEHOLDER-region
  az storage account create --name stfabricopssalesdev --resource-group rg-fabric-tfstate \
    --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false
  az storage container create --account-name stfabricopssalesdev --name tfstate --auth-mode login
  ```
  The storage account name is a name, not a secret; `stfabricopssalesdev` is what
  [`naming.md`](../reference/naming.md) gives, and the contract does not fix one — **VERIFY** against
  the work repo. `naming.md` also still shows `rg-fabric-sales-forecast-shared` and a
  `fabric-sales-forecast/dev.tfstate` key path; the contract's `workspaces/{dev,test,prod}.tfstate`
  keys supersede the latter, and the former is the capacity's group, not state's. The divergence is a
  rename, not a second estate. `--allow-shared-key-access false` is deliberate: it removes the fallback everyone
  reaches for when RBAC is wrong, so the first failure is a real permission error rather than a silent
  key path. **VERIFY** whether anything in the work repo's backup or restore tooling still needs a key
  before turning it off.
- **Grant:** `Storage Blob Data Contributor` **on the container**, not the subscription, to
  `sp-fabric-admin`. The backend reads and writes state and takes locks, so it needs the data plane,
  not the control plane ([`azurerm` backend][tfbe], cited in
  [the design note](../research/deployment-what-does-a-unified-terraform-pipeline-look-like.md#1-the-shape-four-bands-three-state-scopes)).
  ```bash
  az role assignment create \
    --assignee-object-id 11111111-1111-1111-1111-111111111111 \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" \
    --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fabric-tfstate/providers/Microsoft.Storage/storageAccounts/stfabricopssalesdev/blobServices/default/containers/tfstate
  ```
- **Required permission:** subscription **Owner** (or Contributor **plus** User Access Administrator at
  that scope) — Contributor alone can create storage and cannot grant a role. Creating the container
  needs a data-plane role of the human's own, or `--auth-mode login` with one.
- **Verify** — as `sp-fabric-admin`, from a pipeline job, not from your own login:
  ```bash
  az storage container show --account-name stfabricopssalesdev --name tfstate --auth-mode login \
    --query "{name:name, publicAccess:properties.publicAccess, etag:properties.etag}" -o json
  az storage blob list --account-name stfabricopssalesdev --container-name tfstate --auth-mode login -o table
  ```
  It returns a name, a null `publicAccess` and an etag, and the blob list is empty. There is no key in
  either command, and `ARM_ACCESS_KEY` must never be set in the pipeline.
- **If skipped:** `terraform init` fails with a 403 from the blob endpoint — the message names
  authorisation, and the tempting fix (a key) reintroduces the secret [ADR 0002](../adr/0002-two-service-principals-federated.md)
  exists to remove. **VERIFY** the exact error text in the tenant; it varies by path.

## 2. Two app registrations and service principals

- **Create:** `sp-fabric-admin` and `sp-fabric-deploy`, each an app registration plus its service
  principal, with **no client secret**. **VERIFY** whether the tenant permits app creation by an
  Application Administrator or requires a higher role — a directory fact, not a documented constant.
  ```bash
  az ad app create --display-name sp-fabric-admin --sign-in-audience AzureADMyOrg
  az ad sp create --id 00000000-0000-0000-0000-000000000000      # the appId returned above
  az ad sp show --id 00000000-0000-0000-0000-000000000000 --query id -o tsv   # object ID, for §1/§7
  ```
  Repeat with `sp-fabric-deploy`. The **object ID** is what Azure roles and `administration_members`
  take; the **appId** is what a service connection takes. Confusing them produces a connection that
  verifies and a role assignment that grants nothing.
- **The federated credential, and why it is not created here.** The credential hangs off the
  **application**, not the service principal, and it cannot exist before the connection that supplies
  its issuer and subject does ([ADO note §1](../research/ado-pipeline-mechanics.md#1-service-connections),
  [Entra note Part A](../research/entra-and-ado-operations.md)). Once §4 has produced both:
  ```bash
  # fic.json — every value copied from the connection, none constructed
  # {"name":"ado-sc-fabric-admin",
  #  "issuer":"https://login.microsoftonline.com/00000000-0000-0000-0000-000000000000/v2.0",
  #  "subject":"<copied from the connection>",
  #  "audiences":["api://AzureADTokenExchange"]}
  az ad app federated-credential create --id 00000000-0000-0000-0000-000000000000 --parameters @fic.json
  ```
  The subject binds organisation, project and connection identifiers, so a **rename silently breaks
  the exchange** and the error does not surface until a token exchange fails (`AADSTS700213`). The
  legacy Azure DevOps issuer retires 2027-07-01 — a credential on it needs reissuing before then, and
  the date is the one thing on this page that can be diarised rather than verified.
- **Required permission:** Application Administrator (or ownership of the app) to create the app, the
  SP and the credential; a **Project Collection Administrator** to add the first SP to the ADO
  organisation, which is a separate human step inside §4.
- **Verify:** the exchange, not the object. In the connection, `Verify and save` performs it; then a
  pipeline job proves the pipeline's own path:
  ```yaml
  - task: AzureCLI@2
    inputs: { azureSubscription: sc-fabric-admin, scriptType: bash,
              addSpnToEnvironment: true, inlineScript: 'az account show --query "{t:tenantId,u:user.name}"' }
  ```
  `user.name` is the appId. **VERIFY** that the tenant shows it as the appId rather than a UPN — the
  noted shape is unrun here.
- **If skipped:** the connection saves and every job fails at login; or, with a secret created "just to
  test", the design is defeated quietly and nothing fails at all. Delete any client secret created
  during setup.

## 3. Graph application permissions for `sp-fabric-admin`

- **Create:** two **application** permissions — `Group.Create` and `User.Read.All` — with admin
  consent. The pair, not the first alone: a group created with `Group.Create` and no owner is created
  anonymously and cannot be modified, and naming a human owner is what adds the user read
  ([ADR 0010 §3](../adr/0010-delegation-and-administration-model.md)).
- **Why these two, and why it is a decision rather than a detail.** Groups built as code are what needs
  `Group.Create`, and the pipeline contract puts them in the workspaces root — but
  [ADR 0010 §2](../adr/0010-delegation-and-administration-model.md) currently keeps group creation
  **manual** and refuses directory write on the platform principal. Until the amendment the contract
  says it makes is recorded, the consented set is a capability the pipeline does not use. Consenting it
  is a standing grant on the most privileged principal in the design; make that trade deliberately.
  Because the workspaces root **creates** the groups in this design, it does not look them up by name;
  the only directory read it needs is the one `User.Read.All` already covers, for binding a human
  owner. If groups are instead kept manual, the root must resolve them by object ID or name and needs
  at least `Group.Read.All` — **VERIFY** the least permission that works, because the provider's
  documented floor has moved.
- **Path:** Entra admin centre → **App registrations** → `sp-fabric-admin` → **API permissions** →
  **Add a permission** → **Microsoft Graph** → **Application permissions** → `Group.Create`,
  `User.Read.All` → **Add permissions** → **Grant admin consent**. The CLI can add the same entries,
  but the role IDs must be **read from the Graph service principal, never typed from memory**:
  ```bash
  az ad sp show --id <graph-app-id> \
    --query "appRoles[?value=='Group.Create' || value=='User.Read.All'].{value:value,id:id}" -o table
  az ad app permission add --id 00000000-0000-0000-0000-000000000000 \
    --api <graph-app-id> --api-permissions <Group.Create id>=Role <User.Read.All id>=Role
  ```
  `<graph-app-id>` is the Microsoft Graph first-party app in the tenant. Resolve it
  (`az ad sp list --display-name "Microsoft Graph" --query "[0].appId" -o tsv`) rather than typing an
  ID from memory — the same rule as the role IDs.
- **Required permission:** a **Privileged Role Administrator**, a human. Application Administrator and
  Cloud Application Administrator are explicitly excluded from consenting to Graph app roles
  ([Entra note](../research/entra-and-ado-operations.md)). `az ad app permission admin-consent` only
  works if the person running it already holds that role — it is a convenience, not a way around the
  human.
- **Verify:**
  ```bash
  az ad app permission list --id 00000000-0000-0000-0000-000000000000 \
    --query "[].resourceAccess[].{id:id,type:type}" -o table
  az ad app permission list-grants --id 00000000-0000-0000-0000-000000000000 -o table
  ```
  Read both, and read what they do not show: `list-grants` reports **delegated** grants, so an empty
  table is not proof of failure and a populated one is not proof of application consent. The real
  check is the token — request a Graph token as the SP in a pipeline job and confirm `roles` contains
  both, then prove `User.Read.All` with `GET https://graph.microsoft.com/v1.0/users?$top=1`. `Group.Create`
  is proven by the first dev apply, or by nothing: do not create a scratch group to test it.
- **If skipped:** plan succeeds, apply fails `403 Authorization_RequestDenied` at group create, and the
  error reads like a workspace role problem. **VERIFY** the message; it differs between the Graph and
  Fabric surfaces and that difference is the fastest diagnosis you will have.

## 4. Two ADO service connections

- **Create:** `sc-fabric-admin` and `sc-fabric-deploy`, both **Azure Resource Manager** with
  **Workload identity federation**. There is no Fabric service connection type; the Azure DevOps type
  connects to Azure DevOps, not Fabric ([ADO note §1](../research/ado-pipeline-mechanics.md#1-service-connections)).
- **Path:** Project settings → **Service connections** → **New service connection** → **Azure Resource
  Manager** → **Workload identity federation (manual)** → **App registration or managed identity
  (manual)** → environment `AzureCloud`, scope level Subscription, subscription and tenant IDs, Service
  Principal ID = the appId → name it → **save as a draft**. Copy the generated **Issuer** and **Subject
  identifier**; create the credential in §2; return to the connection and **Verify and save**.
  `creationMode` must be `Manual` — Azure DevOps cannot create an app for a non-user principal, which
  is the whole reason this order exists.
- **Before the SP can own anything:** a **Project Collection Administrator** adds each service
  principal to the ADO organisation with an access level and project membership. It is API-able
  (`serviceprincipalentitlements`) but only by someone who is already a PCA, so the first one is a
  person. **VERIFY** the access level — whether a Basic slot is consumed by an SP is not settled in the
  documentation ([Entra note Part B](../research/entra-and-ado-operations.md)).
- **Authorisation: per pipeline, never "grant to all pipelines".** After the pipeline first exists,
  Service connections → the connection → **Security** → **Pipeline permissions**: remove
  `Grant access permission to all pipelines`, add `fabric-sales-forecast-cicd` only. Expect the first
  run to raise a permission request for a resource — approve that one request explicitly rather than
  reaching for the blanket switch, which hands every pipeline in the project the same standing admin
  access.
- **Required permission:** Project Administrator (or connection Administrator) to edit permissions; PCA
  for the entitlement step.
- **Verify:** `Verify and save` succeeds for both; the Security page lists exactly one pipeline and
  `isShared` is false; then the §2 job logs in with `addSpnToEnvironment` for each alias in turn.
- **If skipped:** a missing grant fails at token exchange with `AADSTS70021`/`700213`; a blanket grant
  means a YAML change on any branch can use admin rights, and the merge-path controls in
  [ADR 0002](../adr/0002-two-service-principals-federated.md) no longer bound the blast radius. Also
  note: ADO may disable a connection unused for 100 days — check both before a quarter's first run.

## 5. Four ADO environments

- **Create:** `fabric-platform`, `fabric-dev`, `fabric-test`, `fabric-prod` — exactly, because
  environment names cannot be variables and a typo **creates a new environment with no checks** that
  gates nothing ([ADO note, sharp edges](../research/ado-pipeline-mechanics.md#sharp-edges-with-the-symptom)).
  Path: Pipelines → **Environments** → New environment, one at a time.
- **Checks on all four, in this order** (⋯ → **Approvals and checks**):
  - **Approvals** — approvers, instructions, Timeout, self-approval rule. On `fabric-prod`: at least
    two named humans as approvers, instructions naming the artefact ("apply the plan published by the
    Test stage's last job; compare resource count and any replacement"), a Timeout you can live with
    (1440 minutes is a working figure; 43200 is the maximum), and **"Allow approvers to approve their
    own runs" off**. That last one has a consequence worth stating to the team: the person who queued
    the run cannot approve prod, so a merge by the author needs a second person awake. A service
    principal cannot be listed as an approver — **VERIFY**, and the design does not want it.
  - **Branch control** on `fabric-prod` only: `refs/heads/main`, fully qualified, exact match. It
    **fails** the stage, which is the behaviour you want at a gate.
  - **Exclusive lock** on all four, so an admin apply and a content deploy cannot overlap in one
    environment. Pair it with `lockBehavior: sequential` on the stage, or a queued run cancels the
    in-flight one instead of waiting.
- **Also restrict who may use each environment** (Environment → Security → Pipeline permissions, and
  who may create environments). An environment that auto-creates on a typo is an ungated production
  path; a permission failure is a loud one.
- **Required permission:** Project Administrator to create environments and attach checks; the creator
  is added as environment Administrator by default.
- **Verify:** push a no-op commit (a YAML comment) to a branch, run it, and watch it **pause** at prod
  with an Approval record. Read the record — approver, `createdOn`, `minRequiredApprovers`,
  `instructions` — then **reject** it and confirm the stage **fails**; then run again and approve.
  Optionally set one environment's Timeout to a minute once, to see that expiry marks the stage
  `skipped` rather than failed. That is the failure this section exists to prevent.
- **If skipped:** the stage runs ungated the moment someone drops `environment:` in a refactor, and
  nothing complains; or an expired approval reads as "not deployed yet" and nobody investigates.

## 6. Tenant settings

- **Create:** three switches, in the Fabric admin portal (app.fabric.microsoft.com → **Admin portal** →
  **Tenant settings**):

  | Setting | Page | Value |
  | --- | --- | --- |
  | `Service principals can call Fabric public APIs` | Developer settings | on, scoped to a security group containing both SPs |
  | `Service principals can create workspaces, connections, and deployment pipelines` | Developer settings | on, same group |
  | `Create workspaces` | Workspace settings | one named platform group (`fabric-role-workspace-creators`), never `Everyone` |

  The first two are what let the pipeline call the public API at all; the third is
  [ADR 0010 §1](../adr/0010-delegation-and-administration-model.md)'s "one path creates a workspace".
  **VERIFY** whether the `Create workspaces` list is consulted for a service principal at all, as
  distinct from the SP-create switch — the documentation does not settle it, and the two fail alike.
  The two admin-API toggles stay off unless the access report runs from this principal; they are in
  [run-book 01 §2](01-work-tenant-checklist.md).
- **Required permission:** Fabric administrator. A tenant administrator who is not a Fabric
  administrator cannot see the page, which is a common hour lost.
- **Verify:** a **plan** that lists capacities succeeds. In the test stage's prod-plan job, or by hand
  with the SP's token, `GET https://api.fabric.microsoft.com/v1/capacities` returns the capacity with
  `state: "Active"`, and `terraform plan` on the workspaces root gets past
  `data "fabric_capacity"`. A token issued before the toggle changed can carry the old answer —
  **VERIFY** the propagation window, which is minutes to an hour rather than seconds.
- **If skipped:** authentication succeeds and the first Fabric call returns 401/403, which reads as a
  role problem and sends you to §7 for an hour.

## 7. Azure rights

- **Create:** `sp-fabric-admin` as a **capacity administrator** via `administration_members`, plus
  Contributor on the subscription or, better, a pre-created resource group.

  | Right | Where it is expressed | Why |
  | --- | --- | --- |
  | capacity administrator | `administration_members` in the platform state, fed by the state file's `capacity_admin_object_ids` | Create Workspace requires the caller to be a capacity contributor or admin; the provider documents the member as "an Entra user or a service principal" |
  | Contributor | subscription, or scoped to `rg-fabric-sales-forecast` | create the resource group and the capacity |
  | resource provider | `Microsoft.Fabric` registered on the subscription | **VERIFY** whether Contributor's `register/action` is enough, and check `az provider show --namespace Microsoft.Fabric --query registrationState` |

  The variable name is the contract's (`capacity_admin_object_ids`), and the example in
  [`terraform-capacity.tf`](../reference/terraform-capacity.tf) feeds `administration_members` from it.
  An earlier draft used `capacity_admin_upns` with the comment "never the service principals"; the
  design note deliberately reverses that — putting the SP in `administration_members` sidesteps the
  open question of whether an SP can hold capacity **Contributor** without answering it
  ([design note §3](../research/deployment-what-does-a-unified-terraform-pipeline-look-like.md#3-the-bands-in-order)).
  Record the breadth in the work repo: **every** entry in that list is a capacity administrator, and a
  group there would make every member one.
- **If the capacity already exists, import it** rather than recreating it. Recreating a capacity is
  the one step in this page whose blast radius is all three environments ([ADR 0004](../adr/0004-one-shared-capacity.md)).
- **Required permission:** Subscription Owner or capacity admin to grant; the pre-created-resource-group
  route needs whoever staged the group.
- **Verify:** `terraform plan` on `terraform/platform` **succeeds**, plans the resource group and the
  capacity, and shows the SP's object ID in `administration_members`. A plan proves read; only the
  first apply proves write, so treat a green plan as half the check.
- **If skipped:** plan is green and apply fails `403 AuthorizationFailed` on
  `Microsoft.Fabric/capacities/write`; or the capacity arrives without the SP as administrator and
  every workspace assignment in §8 fails one stage later, where the cause is less obvious.

## 8. First run order

Nothing before **Platform** may reference a service connection. Credentials start at Platform and change
hands once per environment, so each stage's check is also a check that the *right* principal ran it.

| Stage | What runs | Check after it | Do not continue if |
| --- | --- | --- | --- |
| Build | bundle content, `fmt -check`, `validate` — no credentials, no backend | the content artefact is published once, and the job contains no `azureSubscription` | any step logged in, or the artefact was rebuilt per environment |
| Platform plan | `plan` against `platform.tfstate` | the plan lists the resource group and the capacity; state backend reachable; the SP appears in `administration_members` | the plan wants to **replace** a capacity that exists — stop and import |
| Platform apply | apply that plan | capacity `state: "Active"`; the SP is an administrator; **write down the capacity GUID** | state is not `Active` |
| Dev plan/apply | control plane at `workspaces/dev.tfstate` | the `fabric_capacity` postcondition passes; workspace, identity, two groups (created or resolved), three role assignments | any count is zero, or the identity has no `service_principal_id` |
| Dev content | `fabric-cicd` as `sc-fabric-deploy` | item count matches the repo; no orphan deletions on a first run | a deletion is reported on an empty workspace |
| Test | same as Dev, at `workspaces/test.tfstate` | same counts as dev | counts differ from dev with no reason in the diff |
| Prod plan (**last job of Test**) | `plan` against `workspaces/prod.tfstate`, published as an artefact | the plan file is attached to the run and readable by the approver; the approver can see the resource count | the plan was made inside the Prod stage, or nobody can open it |
| Approve | a human, on the Approval record | the record names the approver and the time; the stage is not `skipped` | the stage is skipped, or the approver is the person who queued it |
| Prod apply | `apply <the saved plan>` — no re-plan | no replacement of, or destroy on, a workspace | the plan is stale: **re-plan and re-approve**, never `-refresh=false` |
| Prod content | the same artefact Build published | item count equals test | anything was rebuilt for prod |

Two rules the table hides. One `apply` per job, because the assertion dies after roughly an hour
mid-apply and the error names the token, not the step. And the prod plan is the approval: passing a
plan file is what `apply` acts on, so the approver's real job is reading it — a plan reviewed in
summary is a plan nobody approved.

## 9. Verification after the first full run

| Check | How | Good looks like |
| --- | --- | --- |
| Workspace exists and is Active on the capacity | workspace settings in the portal; admin API workspace list | the named workspace, capacity `fabric-sales-forecast-shared`, state `Active` |
| Workspace identity is Active and has Contributor | workspace → **Workspace identity**; `fabric_workspace.x.identity[0].service_principal_id` in state; the role-assignment list | status `Active`, one Contributor assignment to that SP |
| Groups exist, with the named human as **owner** | Entra → Groups → Owners; `az ad group owner list --group <group-object-id>` | the ADR 0010 owner is present — an ownerless group is the failure the create call hides |
| Role assignment resolves | `GET /v1/workspaces/{id}/roleAssignments` (Preview) and the admin API `…/users` | the group appears as `Contributor` with `principalType: Group`; no `Admin` held by a group |
| Audit log names the principal | Fabric/Purview audit log, filtered to the SP's display name | a create-workspace event attributed to `sp-fabric-admin` — **VERIFY** the ingestion lag before calling a silent log a failure |

Several of these read Preview endpoints and the audit entry is event-sourced, so none is proof of the
others. If the audit log is empty after 24 hours, suspect the diagnostic setting before the pipeline.

## 10. What stays manual forever

| Thing | Why it cannot move |
| --- | --- |
| Capacity overage, surge protection, pause/resume | not expressible in AzureRM, so it never appears in a plan and drifts invisibly ([run-book 01 §3](01-work-tenant-checklist.md)) |
| Sensitivity labels | default and mandatory labelling are not applied to service principals or APIs, and there is no API to label an existing item — only creation can carry one |
| Item-level sharing | the pipeline never sees it; it is the one grant path a Viewer holds, and the exception register is the control ([ADR 0010 §6](../adr/0010-delegation-and-administration-model.md)) |
| Graph admin consent | a Privileged Role Administrator, human, by design; no automation should be able to widen its own directory rights |
| Approving production | one person, every run; the Approval record is the audit trail and the last control that assumes a human read the plan |

If any of these five acquires an automation path, it needs an ADR, not a commit.

[tfbe]: https://developer.hashicorp.com/terraform/language/backend/azurerm

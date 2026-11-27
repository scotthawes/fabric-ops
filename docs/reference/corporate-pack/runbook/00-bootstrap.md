# Runbook 00 — Bootstrap

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

The human steps that must pass before the pipeline's first run, in order, for this shape: one ADO
project, three environments, two environments per domain (`nonprod`, `prod`), two capacities, N
domain repositories. Every step is a tenant setting, a directory permission, an Azure role or an ADO
object that the pipeline will never be able to create for itself.

Read `../spec/0002-contract.md` first: the names and state keys below are fixed there. Do not start
step *n+1* until step *n*'s verify passes. A step that was skipped does not fail where it was
skipped; it fails a stage later, where the cause is less obvious.

## Placeholders

| Written | Means | Never |
| --- | --- | --- |
| `00000000-0000-0000-0000-000000000000` | any GUID: tenant, subscription, object ID | commit a real one to a shared document |
| `PLACEHOLDER-region` | an Azure region chosen by the corporate landing zone | guess one from a sibling subscription |
| `PLACEHOLDER-…` | a name the corporate repo supplies | treat as a default |
| `SP_ADMIN_APPID` / `SP_ADMIN_OBJECTID` | the values you recorded in step 3 | type from memory; copy them |
| `SP_DEPLOY_APPID` / `SP_DEPLOY_OBJECTID` | same, for `sp-fabric-deploy` | swap with the admin pair |

Two IDs per principal, and they are not interchangeable. The **appId** is what a service connection
takes; the **object ID** is what Azure roles and `administration_members` take. Confusing them gives
a connection that verifies and a role assignment that grants nothing.

## Steps at a glance

| # | Step | Who | Once or repeatable |
| --- | --- | --- | --- |
| 1 | Prove you are a Fabric administrator | bootstrap lead | once |
| 2 | Both resource groups and state storage | subscription Owner | once |
| 3 | Two app registrations, no secret | Application Administrator | once; repeat on rotation |
| 4 | State data-plane grant | subscription Owner | once |
| 5 | Graph permissions and consent | Privileged Role Administrator (human) | once |
| 6 | Two service connections and federated credentials | Project Collection Administrator, then Project Administrator | once; repeat on rename |
| 7 | Three ADO environments and checks | Project Administrator | once; approvers repeatable |
| 8 | Three tenant switches | Fabric administrator | once; drifts, so re-check |
| 9 | Capacity administrator on both capacities | capacity admin or subscription Owner | once per capacity |
| 10 | The `fabric-self-hosted` agent pool and image | Project Administrator | once; repeat on image change |
| 11 | N repositories, the pipeline, and the Fabric Git connection | Project Administrator | once per domain |
| 12 | The domain rows, created in the portal | Fabric administrator or domain admin | once per domain |
| 13 | First run | pipeline plus the prod approver | every merge after |
| 14 | After the first apply: assignment, parameter file, overage | domain admin, content owner, capacity admin | once per domain / capacity |

## 1. Prove you are a Fabric administrator

- **Who.** The person who will run steps 8 and 9. Being a tenant administrator is not enough; a
  tenant administrator who is not a Fabric administrator cannot see the admin portal.
- **Do.** Open `https://app.fabric.microsoft.com` → **Admin portal**. Try to open **Tenant
  settings**.
- **Verify.** The Tenant settings page loads and the three switches in step 8 are visible. Write
  down who confirmed it and the date.
- **If skipped.** Steps 8 and 9 stall, and the first Nonprod apply fails on a Fabric call that looks
  like a role problem. Nothing earlier warns you.

## 2. Both resource groups and state storage

- **Who.** Subscription **Owner**, or Contributor **plus** User Access Administrator.
- **Do.** Two resource groups, fixed names, then one storage account and one container.
  ```bash
  az group create --name rg-fabric-tfstate --location PLACEHOLDER-region
  az group create --name rg-fabric-corporate --location PLACEHOLDER-region
  az storage account create --name stfabriccorp --resource-group rg-fabric-tfstate \
    --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false
  az storage container create --account-name stfabriccorp --name tfstate --auth-mode login
  ```
  `rg-fabric-tfstate` holds state and must **not** be `rg-fabric-corporate`: state has to outlive
  the root that reads it. `rg-fabric-corporate` holds the two capacities; `platform/main.tf` reads it
  with `data "azurerm_resource_group"` and never creates it. Both jobs of the Platform band read the
  same group, so a per-state resource group would race on create.
  `--allow-shared-key-access false` is deliberate — it removes the key fallback, so a wrong role
  fails loudly instead of silently working.
  Your own login needs a **data-plane** role on the account to create the container with
  `--auth-mode login`; subscription Owner is control-plane only. Grant yourself
  `Storage Blob Data Contributor` on the account for the ten minutes this takes, then remove it.
- **Verify.** `az group show --name rg-fabric-corporate` and `az group show --name rg-fabric-tfstate`
  both return a location, and they are different groups. With your own login,
  `az storage container show --account-name stfabriccorp --name tfstate --auth-mode login` returns a
  name, a null `publicAccess` and an etag. No key is used.
- **If skipped.** `terraform init` fails 403 at the blob endpoint, or Platform stops at
  `data.azurerm_resource_group.capacity` because `rg-fabric-corporate` does not exist. The tempting
  fix (a storage key) reintroduces the one secret the design removes.

## 3. Two app registrations, no secret

- **Who.** Entra **Application Administrator**, or an existing admin principal.
- **Do.** One registration per principal, each with a service principal. No client secret. The
  federated credential is created in step 6, because it needs the connection's issuer and subject.
  ```bash
  az ad app create --display-name sp-fabric-admin --sign-in-audience AzureADMyOrg
  az ad app create --display-name sp-fabric-deploy --sign-in-audience AzureADMyOrg
  az ad sp create --id SP_ADMIN_APPID          # the appId printed by the create above
  az ad sp create --id SP_DEPLOY_APPID
  az ad sp show --id SP_ADMIN_APPID --query id -o tsv    # object ID -> SP_ADMIN_OBJECTID
  az ad sp show --id SP_DEPLOY_APPID --query id -o tsv   # object ID -> SP_DEPLOY_OBJECTID
  ```
  Use the names in a table beside you; every later command copies them.
- **Verify.** `az ad app show --id SP_ADMIN_APPID --query "passwordCredentials"` and the same for
  deploy both return `[]`. Two apps, two service principals, zero secrets.
- **If skipped.** The connection saves and every job fails at login — or, with a secret created "just
  to test", nothing fails at all and the design is quietly defeated. Delete any secret you created.

## 4. State data-plane grant

- **Who.** Subscription Owner, or User Access Administrator at the container scope.
- **Do.** Grant `Storage Blob Data Contributor` **on the container**, not the subscription, to
  `sp-fabric-admin` only. The backend reads, writes and locks state; that is a data-plane role.
  ```bash
  az role assignment create \
    --assignee-object-id SP_ADMIN_OBJECTID \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" \
    --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fabric-tfstate/providers/Microsoft.Storage/storageAccounts/stfabriccorp/blobServices/default/containers/tfstate
  ```
- **Verify.** From a **pipeline job** using `sc-fabric-admin` (not your login):
  `az storage blob list --account-name stfabriccorp --container-name tfstate --auth-mode login -o table`
  returns an empty list, and `az storage container show … --auth-mode login` succeeds. An empty
  list is the correct first-run answer.
- **If skipped.** `terraform init` fails 403 in Platform. `ARM_ACCESS_KEY` must never be set in the
  pipeline as the workaround.

## 5. Graph permissions and consent

- **Who.** A **Privileged Role Administrator**, a human, by design. Application Administrator and
  Cloud Application Administrator cannot consent to Graph application roles.
- **Do.** On `sp-fabric-admin` only: **Microsoft Graph → Application permissions →
  `Group.ReadWrite.All` and `User.Read.All` → Grant admin consent**. Both, not the first alone:
  `Group.ReadWrite.All` is what lets the pipeline create a group **and** write its owner;
  `Group.Create` alone is not enough, and a group created without an owner cannot be modified.
  `User.Read.All` resolves the human owner you name.
  Portal: Entra admin centre → **App registrations** → `sp-fabric-admin` → **API permissions**.
  CLI, resolving the Graph app and role IDs from the tenant — never from memory:
  ```bash
  az ad sp list --display-name "Microsoft Graph" --query "[0].appId" -o tsv
  az ad sp show --id <graph-app-id> \
    --query "appRoles[?value=='Group.ReadWrite.All' || value=='User.Read.All'].{value:value,id:id}" -o table
  az ad app permission add --id SP_ADMIN_APPID --api <graph-app-id> \
    --api-permissions <Group.ReadWrite.All id>=Role <User.Read.All id>=Role
  ```
- **Verify.** In a pipeline job, request a Graph token as the SP and read `roles`: it contains both
  `Group.ReadWrite.All` and `User.Read.All`. Prove the read with
  `GET https://graph.microsoft.com/v1.0/users?$top=1`. Group create is proven by the first
  Nonprod apply, or by nothing — **do not create a scratch group to test it**.
- **If skipped.** The plan succeeds and apply fails `403 Authorization_RequestDenied` at group
  create, which reads like a workspace-role problem. This is [troubleshooting](troubleshooting.md)'s
  third entry.

## 6. Two service connections and federated credentials

- **Who.** **Project Collection Administrator** for the first principal (adding an SP to the
  organisation is a separate human step), then **Project Administrator**.
- **Do.** Both connections are **Azure Resource Manager** with **Workload identity federation**.
  There is no Fabric connection type. For each in turn:
  1. Project settings → **Service connections** → New → Azure Resource Manager →
     **Workload identity federation (manual)** → **App registration or managed identity (manual)** →
     environment `AzureCloud`, scope Subscription, the subscription and tenant IDs, Service
     Principal ID = the **appId**.
  2. Name it `sc-fabric-admin` or `sc-fabric-deploy`, save **as a draft**. `creationMode` must be
     `Manual`.
  3. Copy the generated **Issuer** and **Subject identifier** — copy, never construct.
  4. Create the credential on the app:
     ```bash
     # credentials.json — both values pasted from the draft connection
     # {"name":"ado-sc-fabric-admin","issuer":"<issuer>","subject":"<subject>",
     #  "audiences":["api://AzureADTokenExchange"]}
     az ad app federated-credential create --id SP_ADMIN_APPID --parameters @credentials.json
     ```
  5. Return to the connection, **Verify and save**.
  6. A Project Collection Administrator adds the service principal to the ADO organisation with an
     access level and project membership.
  Repeat for `sc-fabric-deploy` with `SP_DEPLOY_APPID`.
- **Verify.** `Verify and save` succeeds for both. A job with
  `azureSubscription: sc-fabric-admin`, `addSpnToEnvironment: true` prints `user.name` equal to
  `SP_ADMIN_APPID`; same for deploy. Connection *names are stable* — a rename silently breaks the
  federation until a token exchange fails.
- **If skipped.** Token exchange fails `AADSTS700213`; or, with "grant access to all pipelines", a
  YAML change on any branch carries admin rights. Per-pipeline authorisation happens in step 11,
  once the pipeline exists.

## 7. Three ADO environments and checks

- **Who.** Project Administrator.
- **Do.** Create exactly `fabric-platform`, `fabric-nonprod`, `fabric-prod`. Names cannot be
  variables, and a typo creates a **new environment with no checks** that gates nothing.
  On each: **Approvals and checks** →
  - **Approvals**: on `fabric-prod` at least two named humans, instructions naming the artefact
    ("apply the plan published by PlanProd; compare resource count and any replacement"), a Timeout
    you can live with, and **self-approval off**. The other two carry **no Approvals check**: their plans are made in the job, so an approval there would fire before anyone could read it.
  - **Branch control** on `fabric-prod` only: `refs/heads/main`, fully qualified, exact. It *fails*
    the stage, which is right at a gate.
  - **Exclusive lock** on all three, paired with `lockBehavior: sequential` so a queued run waits
    instead of cancelling the one in flight.
  - Environment → Security → **Pipeline permissions**: only this pipeline. Restrict who may create
    environments.
- **Verify.** Merge a comment-only commit to `main` and run it: it **pauses** at prod with an
  Approval record naming approver, `createdOn` and `minRequiredApprovers`. **Reject** it: the stage
  **fails**. Run again, approve: the stage runs. Once, also run from a feature branch and confirm
  prod **fails** the branch control rather than pausing — that is the static check doing its job.
  Optionally set a one-minute Timeout once and watch the stage go **skipped** — that is the failure
  this step prevents.
- **If skipped.** Prod runs ungated the moment a refactor drops `environment:`, and an expired
  approval reads as "not deployed yet" while nobody investigates.

## 8. Three tenant switches

- **Who.** **Fabric administrator** (proved in step 1).
- **Do.** Fabric admin portal → **Tenant settings**:

  | Setting | Page | Value |
  | --- | --- | --- |
  | Service principals can call Fabric public APIs | Developer settings | On, scoped to one security group holding both SPs |
  | Service principals can create workspaces, connections, and deployment pipelines | Developer settings | On, same group |
  | Create workspaces | Workspace settings | one named platform group, **never Everyone** |

  The scoping group (`PLACEHOLDER-sp-security-group`) is a corporate decision; the pack does not
  name it. The two admin-API toggles stay off unless an access report runs from this principal.
- **Verify.** A plan that lists capacities succeeds: with the SP's token,
  `GET https://api.fabric.microsoft.com/v1/capacities` returns both capacities with
  `state: "Active"`, and `terraform plan` on the workspaces root gets past `data.fabric_capacity`. A
  token issued before the toggle changed can carry the old answer for minutes to an hour.
- **If skipped.** Authentication succeeds and the first Fabric call returns 401/403, which reads as
  a role problem and sends you to step 9 for an hour.

## 9. Capacity administrator on both capacities

- **Who.** Subscription Owner to grant Contributor; a capacity administrator for the membership.
- **Do.** Two cases, and they are different. The capacities are `fabric-capacity-nonprod` and
  `fabric-capacity-prod`.
  - **Capacity does not exist yet** (the normal path): put `SP_ADMIN_OBJECTID` in
    `capacity_admin_object_ids` in **both** `terraform/platform/env/nonprod.tfvars` and
    `.../prod.tfvars` before the first Platform apply. The platform root feeds
    `administration_members` at create time.
  - **Capacity already exists**: import it rather than recreating it, then add the SP by hand in the
    Azure portal → the capacity → **Capacity administrators** → add `sp-fabric-admin`.
  Also: Contributor on the subscription or on `rg-fabric-corporate` (enough to write the capacity),
  and `Microsoft.Fabric` registered:
  `az provider register --namespace Microsoft.Fabric`.
- **Verify.** The Platform plan reads `rg-fabric-corporate` and lists the capacity, and shows
  `SP_ADMIN_OBJECTID` in `administration_members`; after apply, both capacities are `Active` and the
  portal's capacity-administrator list contains the SP on **both**. A green plan proves read only.
- **If skipped.** Apply fails `403 AuthorizationFailed` on `Microsoft.Fabric/capacities/write`, or
  the capacity arrives without the SP as administrator and every Nonprod workspace fails one stage
  later. Every entry in `capacity_admin_object_ids` is a capacity administrator — a group there
  makes every member one.

## 10. The `fabric-self-hosted` agent pool and image

- **Who.** Project Administrator, with whoever owns the build agents.
- **Do.** Create an agent pool named exactly **`fabric-self-hosted`** — the pipeline's
  `pool: name:` is that literal, and a typo queues every stage forever. Its image must carry:
  `terraform` (the version pinned in `versions.tf`), `python3` with `pip`, **PyYAML**, `az` CLI
  ≥ 2.30, and `git` ≥ 2.9.0; add `fabric-cicd` and `azure-identity` (pinned) for the content jobs.
  No credential is baked into the image: every job authenticates with its federated connection.
- **Verify.** Queue a trivial job on the pool that prints `terraform version`, `python3 -c 'import
  yaml'` and `az version`; all three succeed. The first Build run proves it end to end.
- **If skipped.** Every stage waits for an agent that will never pick the job — `No agent found` or
  an indefinitely queued run, not a pipeline error.

## 11. N repositories, the pipeline, and the Fabric Git connection

- **Who.** Project Administrator; the Fabric connection needs the workspace admin (or the SP).
- **Do.** One Azure Repos repository per nonprod workspace, named exactly
  `fabric-<domain>-nonprod` (contract §3), default branch `main`. Their content is what Build
  bundles, laid out per domain as `content/<domain>/`; each nonprod workspace binds to its
  own repo, and **prod is never bound**.
  Commit the pipeline at `pipelines/cicd.yml`. The ops repository that holds it is
  `PLACEHOLDER-ops-repo`: the contract does not name it. Record the choice in the corporate repo
  (the registry's header or its own README); it is not an open question in this pack.
  Create the pipeline from that file, then Service connections → each connection → Security →
  **Pipeline permissions**: remove "grant access to all pipelines", add this pipeline only.
  Create the Fabric **`ConfiguredConnection`** the Git binding uses: in the Fabric portal →
  **Settings → Manage connections and gateways → Connections → New**, add an Azure DevOps
  connection authenticated as `sp-fabric-admin`. Record its connection GUID as `git_connection_id`
  in `terraform/workspaces/env/<domain>/nonprod.tfvars`. The workspaces root sets
  `source = "ConfiguredConnection"`; the SP cannot bind any other way.
- **Owner object IDs.** `config/domains.yaml` carries three owner object IDs per workspace. Take
  each from Entra admin centre → **Users** → the person → **Object ID**, or
  `az ad user show --id <upn> --query id -o tsv`. A group owner is an object ID too; a UPN is not
  accepted. Do this before the first apply, because preflight rejects the all-zero placeholder.
- **Verify.** For every row of `config/domains.yaml` a repository of exactly that name exists and
  carries `content/<domain>/`; the pipeline's YAML path is `pipelines/cicd.yml`; each
  connection's Security page lists exactly one pipeline and `isShared` is false; a job logs in with
  each alias in turn; the Fabric connection appears in the portal and its GUID is in the nonprod
  tfvars.
- **If skipped.** Build has nothing to bundle, the first run raises an access request for every
  resource and someone reaches for the blanket switch — which hands every pipeline the same standing
  admin access — or the Git binding fails at apply with a 400 naming the connection.

## 12. The domain rows, created in the portal

- **Who.** Fabric administrator, or a domain admin for an existing domain.
- **Do.** For every row of `config/domains.yaml`, create the Fabric domain **in the portal** and
  record the date and the person. The display name is exactly `display_name`; the admins and
  contributors are the principals the tfvars name. This is the default path (`createDomains:
  false`), and it works whether or not the SP can hold Fabric administrator. Do **not** create the
  two workspaces: the pipeline does that, and a hand-made workspace beside the applied one is a
  duplicate.
  If `PROBE-ADMIN` returned 200 and the estate has chosen the Terraform path, skip the manual
  create, set `createDomains: true` and `fabric_administrator_confirmed = true` instead.
- **Verify.** One domain per YAML row, display names identical to `config/domains.yaml`, and the
  date/person recorded in the corporate repo.
- **If skipped.** The workspaces root has no domain GUID to attach to, the portal assignment has
  nothing to assign to, and the estate is a set of ungrouped workspaces.

## 13. First run

Nothing before **Probe** may reference a service connection. Credentials start there and change
hands once per environment, so each stage's check is also a check that the right principal ran it.

Follow [runbook 01](01-first-run.md): Build → Probe → Platform → Nonprod → PlanProd → Guard →
Prod-`<domain>` per domain. The `domains` job inside Platform is
skipped unless `createDomains=true`. Keep [troubleshooting](troubleshooting.md) open. The first prod
apply needs a second person awake — the person who queued the run cannot approve it.

## 14. After the first apply: assignment, parameter file, overage

Three things cannot exist before the first apply, because they need the workspace IDs or the
capacity:

- **Assign both workspaces, in the portal.** For each domain, open the domain → **Assign
  workspaces** → select `fabric-<domain>-nonprod` and `fabric-<domain>-prod`. This is the default
  path (`assignDomains: false`); record the date and the person. Only if `PROBE-ADMIN` was 200 and
  the estate chose Terraform do you set `assignDomains: true` and let the assign job do it.
- **Create `config/parameter.<domain>.yml`.** Copy the scaffold's `config/parameter.sales.yml` once per domain and
  fill that domain's workspace, lakehouse and connection IDs from the applied workspaces. This is
  why content cannot deploy on the very first run: `deploy_items.py` refuses a missing parameter
  file. Run the control applies, create the file, then re-run content and promotion.
- **Review overage in the portal.** For each capacity, open **Capacity settings → Overage** and set
  the policy decision 3 records: off on nonprod, capped below one-third of daily CU hours on prod.
  The default is on at 25% / 3×; the pipeline does not manage the setting and it never appears in a
  plan. Record what you set.

- **Verify.** Each domain lists exactly its two workspaces; each domain has its own
  `config/parameter.<domain>.yml`; each capacity's overage setting matches the recorded decision.
- **If skipped.** Workspaces exist ungrouped, the content step fails `parameter file not found`, and
  overage bills at 3× on a capacity nobody reviewed.

## What stays human forever

Capacity overage, surge protection and pause/resume; enterprise domains and their workspace
assignments; sensitivity labels; item-level sharing; Graph admin consent; approving production. If
any of these acquires an automation path, it needs an ADR, not a commit.

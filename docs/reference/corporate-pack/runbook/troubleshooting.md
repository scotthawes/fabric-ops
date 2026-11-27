# Troubleshooting

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

Symptom → cause → action, keyed by the thing you will actually see. Each entry names the pipeline
stage it appears in, because the same error in two stages has two causes.

Nothing comes back from the corporate tenant, so this page is the debugger. If an entry does not
match, capture the four carryable facts — **stage, run id, error code, failing address or state
key** — and stop; a pasted log is not a report.

| Key | Stage | One line |
| --- | --- | --- |
| `AADSTS700213` | any stage's first exchange | subject/issuer mismatch: rename or copied connection |
| `AADSTS700024` | a long apply | assertion expired, not the token |
| `403 Authorization_RequestDenied` | Nonprod apply | Graph consent missing at group create |
| stale saved plan | Prod-`<domain>` | prod state moved after PlanProd |
| paused capacity | Nonprod, PlanProd, Prod | resume, then re-plan |
| duplicate group name | Nonprod apply | two groups answer one name; resolve by ID |
| state lock held | any apply | a dead run left a blob lease |
| plan proposes replacement | Nonprod, Prod | stop before approval |
| `assert_plan` failure | Prod-`<domain>` (also Nonprod) | read the verdict; never bypass |
| domain assignment destroy | Prod-`<domain>` assign job | a workspace ID left the list |
| `PROBE-AUTH` | Probe | no ARM token: the assertion never exchanged |
| `PROBE-FABRIC` | Probe | `GET /v1/capacities` 401/403 — tenant switch or SP licence |
| `PROBE-PROVIDER` | Probe | `Microsoft.Fabric` not registered on this subscription |
| `PROBE-DOMAINS` | Probe | `GET /v1/domains` failed; domains root and assign job blocked |
| `PROBE-GRAPH` | Probe | `GET /groups` 403; group create will fail one stage later |
| `PROBE-ADMIN` | Probe | 403 selects the Core path; 200 permits the optional root |
| domain fallback | Probe → Domains (absent) → assign job | no Fabric administrator: human creates, pipeline assigns |
| build red before any credential | Build | `fmt`, `validate`, or parameter parity |

## Build

- **Stage.** Build. No service connection, no backend, no tenant access — so a failure here is always
  the repository, never the platform.
- **Symptom.** `terraform fmt -check -recursive` exits non-zero; `terraform validate` names a root;
  the parity step reports `config/domains.yaml` ≠ `parameters.domains` ≠ `parameters.matrix`.
- **Action.** Run `terraform fmt -recursive` in the corporate repo and commit the result. A validate
  error names the root and the attribute. A parity error is fixed in `config/domains.yaml` and the
  pipeline parameters together — never by editing the check.
- **Stop if** any step in Build authenticated to Azure: that is a YAML regression, not a build error.

## `AADSTS700213`

- **Stage.** The first job in a stage that exchanges the federated assertion — Probe, Platform, Nonprod,
  PlanProd or Prod-`<domain>`. Usually the first run after a connection or project rename.
- **Symptom.** `AADSTS700213: No matching federated identity record found for presented assertion`,
  or `AADSTS70021`. `Verify and save` may still be green from before the rename.
- **Cause.** The federated credential matches on **issuer and subject**. The subject binds
  organisation, project and connection identifiers, so a rename, a copied connection, or a
  credential created against the deprecated Azure DevOps issuer (retires 2027-07-01) breaks it. The
  error does not appear until a token exchange happens.
- **Action.** Open the connection; copy the **current** issuer and subject; replace the federated
  credential on the app (`az ad app federated-credential update` or delete and re-create). Keep
  connection names stable afterwards. If the credential uses the legacy issuer, reissue it on the
  Entra issuer now.
- **Do not.** Create a client secret "to get past it", and do not edit the YAML to a different
  connection. Both hide a rename that will break again.

## `AADSTS700024`

- **Stage.** A long `apply` — Platform, Nonprod, or Prod-`<domain>` — typically an hour in.
- **Symptom.** `AADSTS700024: Client assertion is not within its valid time range`, mid-apply, after
  earlier steps in the same job succeeded.
- **Cause.** The **assertion** (about one hour), not the access token, expired. Nothing is wrong
  with the app, the credential or the role.
- **Action.** Re-run the stage; the assertion is re-acquired at the start of the job. If it recurs,
  cut the job so one `apply` per job, and re-authenticate before any step expected to run long.
- **Do not.** Add a secret with a longer lifetime. The federation is the design.

## `403 Authorization_RequestDenied`

- **Stage.** Nonprod apply, at `azuread_group` create. On the Domains stage it means the SP is not a
  Fabric administrator, which is a different cause.
- **Symptom.** Graph returns `403 Authorization_RequestDenied` (or `Insufficient privileges`) while
  the plan succeeded. The message names the Graph call, not the workspace.
- **Cause.** `Group.Create` was never consented, consent was granted to the wrong app, or admin
  consent was granted by a role that could not grant it. `User.Read.All` alone also produces this at
  the owner binding.
- **Action.** Entra → App registrations → `sp-fabric-admin` → API permissions: both application
  permissions present and **Granted for <tenant>**. Re-consent as a Privileged Role Administrator.
  Prove it with a Graph token whose `roles` contains both, then re-run the stage.
- **Do not.** Grant `Directory.ReadWrite.All` or add the SP to a directory role as a shortcut. The
  pair is the consented set (contract, and `forbid.md` rule 2).

## Stale saved plan

- **Stage.** Prod-`<domain>`, at apply. Occasionally Nonprod if a saved plan was carried between
  jobs.
- **Symptom.** Terraform refuses the file: the saved plan is stale / the state serial changed.
- **Cause.** Prod state changed between PlanProd and the approved apply — another run, a manual
  repair, or a partially failed apply. The approval was for a plan of an older state.
- **Action.** Reject the approval if it has not fired; otherwise let the stage fail. Start a **new
  run**, which re-plans in PlanProd, then get a **new approval**. The artifact and the approval are
  a pair.
- **Do not.** Use `-refresh=false`, re-plan inside the prod stage, or approve the same plan again.
  `forbid.md` rules 5 and 6.

## Paused capacity

- **Stage.** Nonprod, PlanProd or Prod-`<domain>` — at `data.fabric_capacity`, or at the first
  workspace call. The postcondition on `state == "Active"` is what catches it at plan time.
- **Symptom.** The plan stops with the capacity postcondition unmet, or apply returns 400/409 saying
  the capacity is not active. The capacity shows `Paused` in the portal.
- **Cause.** A capacity administrator paused it, an auto-pause policy fired, or billing lapsed.
  Paused capacity is not expressible in the provider, so it never appears in a plan as a diff.
- **Action.** Resume it (Azure portal → the capacity → **Resume**; a capacity administrator or
  subscription Owner), confirm `state: "Active"`, then re-plan. Record who paused it and why.
- **Do not.** Set `skip_capacity_state_validation`, and do not let the plan recreate anything to
  "fix" it. Resuming is manual forever.

## Duplicate Entra group name

- **Stage.** Nonprod apply, at `azuread_group` create, or at the role-assignment step when a
  lookup returns two groups.
- **Symptom.** Create fails because the name exists, or two objects answer one
  `fabric-<domain>-<env>-<role>` name and the assignment lands on the wrong one.
- **Cause.** Entra display names are **not unique**. A hand-made group, a previous aborted run, or
  a group created "anonymously" with no owner (and therefore unmodifiable) is already there.
- **Action.** Stop. List the candidates by object ID, with owner and creation date. Decide with the
  identity owner whether to **adopt** the existing group (import it into the workspace state, with a
  reviewed plan) or to rename the intended group. Never delete a group that a workspace or role
  assignment references.
- **Do not.** Resolve groups by name at run time, and do not retry the apply hoping the second call
  picks the right one. The skeleton sets `prevent_duplicate_names = true` for this reason.

## State lock held

- **Stage.** Any apply — usually a second run after a killed or cancelled one; the environment's
  Exclusive lock prevents most overlaps but not a dead job.
- **Symptom.** `Error acquiring the state lock`, with a lock ID, an owner and a creation time. The
  blob has a lease.
- **Cause.** A run died mid-apply. Locks are **per blob**, so another domain or environment is not
  affected.
- **Action.** Confirm no run is live (ADO runs, the environment's deployment history, the
  `lockBehavior` queue). If none, take the lock ID from the error and run
  `terraform force-unlock <lock-id>` in a **pipeline job** with `sc-fabric-admin`, against the same
  state key. Then re-plan.
- **Do not.** Break the blob lease by hand, delete the state blob, or force-unlock while a run is
  live. The second is unrecoverable from the laptop; the third corrupts state.

## Plan proposes replacement

- **Stage.** Nonprod, or Prod-`<domain>` at `assert_plan`. Visible earlier in the plan file.
- **Symptom.** `-/+` on `fabric_workspace`, `azurerm_fabric_capacity` or `fabric_domain`; for a
  workspace that means a new ID, a new identity and lost grants.
- **Cause.** An immutable field changed: workspace display name, capacity SKU or region on a
  replacement path, group display name, or the resource vanished from state so the config no longer
  matches.
- **Action.** Stop before approval. Find the forcing diff in the plan; usually it is a rename. A
  rename of an existing object is not done by changing the config — decide with the architect
  whether to keep the name (contract §3, `naming.md` rule 8) or to migrate deliberately.
- **Do not.** Approve it, and do not remove the resource from state to make the plan quiet. A
  replacement of a workspace or capacity is a migration, not a change.

## `assert_plan` failure

- **Stage.** Prod-`<domain>`, before every apply. Nonprod runs the same script.
- **Symptom.** The job prints a one-line verdict and the offending addresses, then exits non-zero.
  The apply never starts — that is the gate working.
- **Cause.** One of the six rules in contract §7. Read the verdict, then the addresses:
  1. `replace` on workspace, capacity or domain → stop; never approve.
  2. `delete` on group, workspace or capacity → stop; a delete here is outside the design.
  3. fewer than three role assignments → configuration error in `groups`; fix tfvars, re-plan.
  4. capacity postcondition did not evaluate → see *paused capacity*.
  5. count differs from `checks/known-good/<phase>.json` → the baseline or the config moved;
     re-baseline only with a reviewer's sign-off, in its own change.
  6. an address outside the expected set for that root → stop; it is either a new resource that
     needs an ADR or a state leak between environments.
- **Action.** Fix the cause, then a new run: new plan, new approval. The verdict line is the thing to
  carry out if you cannot fix it here.
- **Do not.** Delete the check, weaken the rule, or apply with `-target` to "just get the workspace
  in". Rules 3 and 6 are the ones a weak model is tempted to route around.

## Domain assignment destroy

- **Stage.** Prod-`<domain>`, the assign job after content (`assignments/<domain>.tfstate`).
- **Symptom.** The plan shows a `destroy` of a domain assignment, or the assigned workspace list
  shrinks.
- **Cause.** `workspace_ids` in `terraform/domain-assignments/env/<domain>.tfvars` lost an entry —
  usually a row removed or renamed in `config/domains.yaml`, or a domain duplicated across rows.
- **Action.** Stop before apply. Compare the YAML's workspace IDs with the tfvars list, restore the
  missing ID, re-plan and confirm an **empty** diff. This root is preview: a human decides.
- **Do not.** Apply the destroy. It removes the domain label, not the workspace, but the estate's
  inventory then disagrees with reality and the next plan is unreadable.

## `PROBE-AUTH`

- **Stage.** Probe, the first job in the run that exchanges a federated assertion. It holds a
  connection but no state.
- **Symptom.** `probe.json` (or the log) reports `PROBE-AUTH` red: `az account show` returns nothing,
  or the step fails `AADSTS700213`/`AADSTS70021` before any Fabric call. Every later stage is
  blocked, by design.
- **Cause.** The Probe job names a connection that was renamed, or carries no `azureSubscription` at
  all; its federated credential was made against an old issuer or subject; or the app was never
  added to the project. `Verify and save` can still be green from before the change.
- **Action.** Compare the job's connection name with ADO; reissue the credential from the
  **current** issuer and subject (same repair as `AADSTS700213` below); confirm a job with
  `addSpnToEnvironment: true` prints `user.name` equal to the admin appId. Re-run Probe.
- **Do not.** Add a client secret, or start Platform to "see if it works". Nothing that follows can
  run without a token.

## `PROBE-FABRIC`

- **Stage.** Probe, `GET /v1/capacities` as the SP. The same call is the first Fabric call in
  Platform and every later stage, so a green probe is what makes their failures about something
  else.
- **Symptom.** Red with 401/403, or — after Platform has applied — a list missing one of the two
  capacities. AUTH is green, so the token itself is fine.
- **Cause.** The tenant switch **Service principals can call Fabric public APIs** is off, or is on
  but scoped to a security group the SP is not in ([00-bootstrap](00-bootstrap.md) §8); or a token
  issued before the switch changed is still cached; or the 403 names a licence, which is
  assumption A1 in [`../spec/0004-assumptions.md`](../spec/0004-assumptions.md).
- **Action.** Fix the switch and its group scope; wait out the cached token (minutes to an hour);
  re-run Probe. If the 403 names a licence, a human assigns Pro or PPU to the SP and records it —
  that is a licensing action, not a pack change.
- **Do not.** Turn on the two admin-API toggles as a shortcut. Both are scoped to a reason, and
  neither is what this call needs.

## `PROBE-PROVIDER`

- **Stage.** Probe, the `Microsoft.Fabric` resource-provider registration on the subscription the
  connection reads.
- **Symptom.** Red with `NotRegistered` or `Registering`. If ignored, Platform fails at capacity
  create with `MissingSubscriptionRegistration`.
- **Cause.** Never registered, registered on a different subscription than the one in the platform
  tfvars, or registered and still propagating.
- **Action.** `az provider register --namespace Microsoft.Fabric` on **that** subscription, poll
  `az provider show --namespace Microsoft.Fabric --query registrationState`, re-run Probe.
- **Do not.** Reach for the domains root or `azapi` to route around it. The provider is a
  prerequisite for the capacity, not an alternative to it.

## `PROBE-DOMAINS`

- **Stage.** Probe, `GET /v1/domains`. It gates the optional domains root and the prod assign job;
  it does not gate Platform or Nonprod.
- **Symptom.** Red (403/404) while AUTH and FABRIC are green. The probe carries the status, not a
  diagnosis.
- **Cause.** The SP can read capacities but not tenant domains: it holds no domain contributor or
  Fabric administrator role. The probe carries the status, not the cause; the permission it needs is
  granted by the Fabric administrator either way.
- **Action.** If the pipeline truly has no domains root and no assign job, delete this probe with
  them in the same change. Otherwise stop: the assign job needs the domain read. Resolve the role,
  then re-run Probe.
- **Do not.** Set `createDomains=true` to "see what happens", or let the assign job run on a guess —
  an assignment to a missing domain is a failed apply, not a test.

## `PROBE-GRAPH`

- **Stage.** Probe, `GET /groups?$top=1`. It gates group creation in the workspaces root: the
  Nonprod apply, and prod where groups are created.
- **Symptom.** Red with 403 `Authorization_RequestDenied` (or `Insufficient privileges`) while the
  capacity probe is green. Ignored, the plan succeeds and the Nonprod apply fails at
  `azuread_group` — the `403 Authorization_RequestDenied` entry above, one stage later.
- **Cause.** Consent never granted, granted to the wrong app, granted by a role that could not grant
  it, or `User.Read.All` missing while `Group.Create` is present. The owner binding needs both.
- **Action.** [00-bootstrap](00-bootstrap.md) §5: both application permissions, **Granted for the
  tenant**, by a Privileged Role Administrator; prove it with a token whose `roles` holds both;
  re-run Probe.
- **Do not.** Create a scratch group to test create rights, or grant `Directory.ReadWrite.All`. The
  probe proves the read; the first Nonprod apply is the only proof of create.

## `PROBE-ADMIN`

- **Stage.** Probe, `GET /v1/admin/domains`, expected 403. This probe blocks nothing; it **selects**
  the domain path.
- **Symptom.** 403 (the normal answer), 200 (the SP does hold Fabric administrator), or 401/5xx
  (which is not an answer at all).
- **Cause.** Assumption A6 assumes an SP cannot hold Fabric administrator; a 403 confirms it and the
  run uses the Core assignment path. A 200 means the optional Terraform domains root may be
  enabled; nothing depends on it.
- **Action.** 403 → `createDomains=false`, delete the `domains` job, take the fallback below. 200 →
  the root is optional: enable it only with `fabric_administrator_confirmed = true` and a named human
  who confirmed ([00-bootstrap](00-bootstrap.md) §1). Record which branch ran, in `probe.json`.
- **Do not.** Read 200 as "domains are now managed", or 403 as a failure to fix.

## Domain fallback — Core assignment instead of the Terraform root

- **Stage.** Probe (selection) → Domains (absent) → Prod-`<domain>` assign job.
- **Symptom.** No `fabric_domain` in any plan, no `domains.tfstate`, and the assign job is the only
  place a domain is named. `PROBE-ADMIN` is 403.
- **Cause.** The default path in [`../spec/0001-decisions.md`](../spec/0001-decisions.md) and
  `0004`: a human creates the domains; the pipeline assigns workspaces through the Core API. The SP
  needs workspace admin plus domain contributor — not Fabric administrator.
- **Action.** Confirm `createDomains=false` and that the `domains` job is **deleted**, not left to
  fail (contract §6). The Fabric administrator creates one domain per `config/domains.yaml` row,
  display name exactly as the YAML, and records the date and the name. Then the assign job runs
  against `assignments/<domain>.tfstate`; a second plan is empty.
- **Do not.** Enable the domains root on a hunch, create a domain the YAML does not name, or assign
  before the domain exists.

## When nothing here matches

Carry out: the stage, the run id, the error code, the failing address or state key, and the last
check that passed. Do not paste a log; do not retry more than once without a new fact. On the
fabric-ops side this becomes a dated finding in `spec/0003-open-questions.md`, and a new pack
version if a rule needs to change.

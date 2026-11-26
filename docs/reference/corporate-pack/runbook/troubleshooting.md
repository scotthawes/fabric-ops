# Troubleshooting

**Illustrative · Pack: 2026-11-26.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

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

## `AADSTS700213`

- **Stage.** The first job in a stage that exchanges the federated assertion — Platform, Nonprod,
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

## When nothing here matches

Carry out: the stage, the run id, the error code, the failing address or state key, and the last
check that passed. Do not paste a log; do not retry more than once without a new fact. On the
fabric-ops side this becomes a dated finding in `spec/0003-open-questions.md`, and a new pack
version if a rule needs to change.

# Runbook 01 — First run

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

The stage order, the check after each stage, the stop conditions, and the half-state a stop leaves
behind. Read `../spec/0002-contract.md` §6 first; the graph is fixed there and this page only adds
the checks.

**Before the first run:** the repository has been scaffolded (step 0), every verify in
[runbook 00](00-bootstrap.md) has passed, [runbook 02](02-readiness.md) is green, the capacity GUID
for each environment is written down, and the pipeline's plan stage exists as a separate stage
(never inside `Prod-<domain>`, or the approval would fire before the plan exists).

## 0. Scaffold the repository

The pack is copied into the corporate repo before the first run; nothing runs from `fabric-ops`:

```bash
bash skeletons/scripts/scaffold.sh.tmpl --target <corporate-repo>
```

The runnable name is `scaffold.sh.tmpl` until it is copied; only the copy becomes
`scripts/scaffold.sh`. It copies the tree, renames every `.tmpl` to the name the pipeline reads
(`pipelines/cicd.yml`, `scripts/probe.py`, …), copies `agents/`, `checks/known-good/README.md` and
the pack docs, and seeds `config/domains.yaml` from `skeletons/config/domains.yaml.tmpl`. Fill the
placeholders from [runbook 00 §Placeholders](00-bootstrap.md#placeholders), create the repositories
(§11) and add `content/<domain>/<project>/` for each domain before queueing anything.

- **Check after.** `find . -name '*.tmpl'` in the corporate repo prints nothing; `config/domains.yaml`
  has a `domains:` list; `scripts/report.sh` exists. [runbook 02](02-readiness.md) R0 makes this a
  gate row.
- **Stop if.** A `.tmpl` survives. The file the pipeline reads is that name minus the suffix, so a
  leftover template is a missing file — discovered a stage later, where it reads as a config error.

## The order

```
Build ──▶ Probe ──▶ Platform ──▶ Nonprod ──▶ PlanProd ──▶ Guard ──▶ Prod-<domain>
```

The `domains` job exists inside Platform and runs only when `sp-fabric-admin` holds Fabric
administrator and `createDomains=true` (contract §4, §6). Otherwise it is skipped, not failed — read
the job result, not the run colour. The same applies to the `assign` job when `assignDomains=false`.

| Stage | Environment | Jobs | Gate |
| --- | --- | --- | --- |
| Build | none | bundle one content tree per domain (`content/<domain>/<project>/`), `fmt -check`, `validate`, compare `parameters.domains`/`matrix` with `config/domains.yaml` | none — no connection, no backend |
| Probe | none | read-only checks; writes `probe.json`; fails `PROBE-*` | none — a probe that writes is a deployment |
| Platform | `fabric-platform` | `capacity-nonprod` ∥ `capacity-prod`, each plan-then-apply in the job, then the `domains` job (conditional) | none — never add an Approvals check; the plan is made in the job |
| Nonprod | `fabric-nonprod` | two jobs per domain: `control` (plan → apply) and `content` | none — the environment carries the lock and the record |
| PlanProd | **none** | one plan per domain, artifact `tfplan-<domain>` | none — read-only |
| Guard | **none** | credential-free `assert_plan` over every prod plan | none — fails closed |
| Prod-`<domain>` | `fabric-prod` | apply the guarded plan → content → assign (conditional) | **human approval** |

## Baselines: the first run prints `BASELINE-MISSING`

`assert_plan` compares each root's resource count with `checks/known-good/<phase>.json` when that
file exists (contract §7 rule 5). The first run has no baseline — only
`checks/known-good/README.md` — so it prints

```
BASELINE-MISSING root=<root> phase=<phase> counts=<n>
```

and continues — that line is the expected output, not a stage failure, and rules 1–4 and 6 still
fail closed on that run.

The run produces one `known-good-<phase>` artefact per root and phase. A human checks each against
the plan they just approved and commits it as `checks/known-good/<phase>.json`, in its own reviewed
change, **after** that run and **before** the next one — the procedure is in
[`../checks/known-good/README.md`](../checks/known-good/README.md). The next run compares against
those committed counts, so a difference becomes a finding instead of noise.

Never create a baseline to quiet a count, and never write one from a plan you did not see applied.

## Build

- **Runs.** Bundles content once, `fmt -check` and `validate` per root, asserts that every domain row
  in `config/domains.yaml` has matching tfvars and state keys. No credential, no backend.
- **Check after.** One content artifact is published for the run; the job contains no
  `azureSubscription` and never calls `login`.
- **Stop if.** Any step logged in, the artifact was rebuilt per environment, or the parity check
  found a domain with a tfvars entry and no YAML row (or the reverse).
- **Half-state.** Nothing applied, no state touched. Safe to fix and re-run; the run's artifact dies
  with the run.

## Probe

- **Runs.** Before any stage that holds state: ARM token and `az account show`, `GET
  /v1/capacities`, `Microsoft.Fabric` registration, `GET /v1/domains`, `GET /groups?$top=1`, and
  the admin read whose 403 selects the domain path. No environment, no state, no write in the
  tenant; it writes `probe.json` and publishes it.
- **Check after.** `probe.json` is attached to the run and shows AUTH, FABRIC and PROVIDER green;
  DOMAINS green if the domains root or the assign job exists; GRAPH green if the workspaces root
  creates groups; ADMIN 403 (Core path) or 200 (optional root), with the branch it selected.
- **Stop if.** Any of those is red, ADMIN is 401/5xx, or the job wrote anything in the tenant beyond
  `probe.json`. A red probe is re-run once with a new fact, never repeatedly.
- **Half-state.** Nothing exists to half-apply. `probe.json` belongs to the run; a fix is a tenant
  setting or a YAML change, then a new run. A token cached before the fix can repeat the answer for
  minutes to an hour.

## Platform

- **Runs.** Each job plans **and** applies its own capacity in the same job — `capacity-nonprod` and
  `capacity-prod` in parallel, each against its own state key (`platform/nonprod.tfstate`,
  `platform/prod.tfstate`), with `assert_plan` inline before the apply. There is no approval on this
  band: the plan is made in the job, so an approval here would fire before anyone could read it.
  The `domains` job sits inside this stage and is skipped unless `createDomains=true`. Overage is
  **not** set here or anywhere in the pipeline.
- **Check after.** The plan reads `rg-fabric-corporate` as a data source and creates only its
  capacity; the capacity is `Active`; `SP_ADMIN_OBJECTID` appears in `administration_members`. Write
  down both capacity GUIDs. A second plan for the same state is empty.
- **Stop if.** A plan proposes **replacing** an existing capacity (import it instead), a capacity is
  not `Active`, the plan would create the resource group, or one environment's job succeeded while
  the other failed — the pair is independent, so read both.
- **Half-state.** One capacity exists and is billed with no workspace on it; the other state key is
  untouched, so its job can be re-run alone. The split is deliberate: destroying nonprod cannot
  reach prod. Leaving one empty capacity is untidy, not dangerous — do not hand-delete it, because
  the other run may already reference it.

## Domains job (inside Platform)

- **Runs.** Only when `createDomains=true`, and applies `domains.tfstate`, the domain list from
  `config/domains.yaml`. When `createDomains=false` it is **skipped** — a human created the domains
  in the portal (runbook 00 §12), and a skipped job is green in the run view.
- **Check after.** One `fabric_domain` per row, names match the YAML exactly, and a second plan is
  empty. Count the rows before you look at the plan.
- **Stop if.** The plan proposes deleting a domain, the count differs from the YAML row count, or
  the SP is not a Fabric administrator (`createDomains=true` without `PROBE-ADMIN` 200).
- **Half-state.** Some domains exist and some do not; each is independent, and re-running is
  idempotent. A domain with no workspace is invisible to users and safe to leave for the next run.
  A **deleted** domain is not recoverable by re-apply — stop before that plan.

## Nonprod

- **Runs.** Per domain, plans and applies in the domain's own state key
  (`workspaces/<domain>/nonprod.tfstate`): groups, workspace, identity, a role assignment per group
  plus the identity's own, optional storage grant, Git binding, with `assert_plan` inline; then
  content with `sc-fabric-deploy` from `content/<domain>/<project>/` and
  `config/parameter.<domain>.yml`.
- **Check after.** One role assignment per group (three), plus the workspace identity's own
  Contributor; a workspace identity with a `service_principal_id`; workspace `Active` on its
  capacity; groups carrying `-viewers`/`-contributors`/`-members` and a named human owner; item
  count equal to that domain's content tree.
- **Stop if.** `assert_plan` fails (fewer than three role assignments is rule 3), a plan shows a
  replacement or a group destroy, the identity has no `service_principal_id`, the capacity
  postcondition fails, content reports `CONTENT-SCOPE` (content or parameter path does not carry
  the domain), or content reports an orphan deletion on a workspace that should be empty.
- **Half-state.** One domain may be applied and another not — they do not share a state key, so
  finish the applied one and re-run the other. A workspace may exist with no content: usable, empty,
  and safe to re-run. A workspace with **zero** role assignments must not be left in place; that is
  a configuration error, not an empty workspace, and access is broken for everyone but the SP.

## PlanProd

- **Runs.** One plan per domain against `workspaces/<domain>/prod.tfstate`, published as
  `tfplan-<domain>`. It reads prod state and changes nothing. **No environment**, so no approval can
  fire early.
- **Check after.** The artifact is attached to the run and openable by the approver; the plan adds
  the expected resources and replaces nothing; the resource count is what the approver will compare
  against nonprod.
- **Stop if.** The plan was produced inside a prod stage, the artifact is missing or unreadable, the
  plan already shows a replacement or a group delete, or a domain's prod plan is missing while its
  nonprod job passed.
- **Half-state.** Nothing applied. The artifact belongs to the run and expires with its retention —
  an old run cannot be approved later. If the plan is rejected, the next attempt is a **new run**,
  never a retry of the apply.

## Guard

- **Runs.** Credential-free `assert_plan` over every prod plan — the JSON `PlanProd` published — against
  contract §7. No `environment:`, no service connection, no state write.
- **Check after.** One verdict line per artifact, all passing; the artifacts it passed are the ones
  the prod stages may consume.
- **Stop if.** Any verdict is non-zero, an artifact is missing, or `Guard` was skipped — a skipped
  guard means no prod plan was asserted.
- **Half-state.** Nothing applied. Fix the cause, then a new run: a new plan, a new Guard, a new
  approval.

## Prod-`<domain>`

- **Runs.** Applies the **guarded** artifact (no plan, no `-var-file`), then content from that
  domain's Build tree, then the domain assignment **only if `assignDomains=true`**.
- **Check after.** The apply consumed the approved artifact; no replacement and no destroy on
  `fabric_workspace`, `azurerm_fabric_capacity`, `fabric_domain` or `azuread_group`; the workspace
  is `Active`; item count equals that domain's nonprod count; the assignment lists only the
  domain's two workspace IDs.
- **Stop if.** The plan is stale, `assert_plan` fails, the approval is `skipped` (timeout, not
  success), the approver is the person who queued the run, or the applied plan differs from the one
  that was read.
- **Half-state.** Before the apply: nothing changed; the previous prod state is intact, and the run
  is spent — a new run is needed. During a failed apply: state records what was created, so re-run
  and let the next plan finish the remainder; **never** re-apply the stale file. Across domains: a
  domain that succeeded stays; a domain that stopped is its own state key. One domain deployed and
  another not is a valid, auditable place to pause.

## Stop conditions that outrank the table

Stop the run, do not retry, and carry the finding out, when any of these is true:

1. `probe.json` carries a red code — `PROBE-ADMIN` 403 is not red, it keeps domains and
   assignments on the portal path; an ADMIN 401/5xx is red.
2. `assert_plan` exits non-zero — read its verdict line and the addresses; never bypass it.
3. A plan proposes replacement of a workspace, capacity or domain; or a destroy of a group,
   workspace or capacity.
4. A workspace plan has fewer than three role assignments, or an environment count differs from
   another environment with no tfvars difference.
5. A capacity is paused, or `data.fabric_capacity`'s postcondition did not evaluate.
6. A stage is **skipped** for any reason — read skipped as "did not run".
7. The plan is stale, or the artifact differs from what the approver read.
8. A value is still `PLACEHOLDER-…` or an all-zero GUID on a path that reaches an apply.

Condition 8 is the one a weak model misses: a placeholder that survived to an apply is not a
cosmetic problem, it is a resource named after a placeholder. Stop and ask for the real value.

## Approval discipline

- The prod approver reads the **plan artifact**, not a summary, and says in the approval comment
  what they compared: resource count, any replacement, any destroy.
- No agent approves its own prod run; no agent approves **any** prod run. The Approval record is the
  approval, and the pipeline's environment check is the audit trail.
- Two humans are listed as approvers; both do not have to approve unless `minRequiredApprovers`
  says so, but the roster must have a second person awake when the author queues the run.
- A rejected approval fails the stage. Fix the cause, then start a new run: the plan is remade, and
  so is the approval.

## After the last domain

Check the estate, not the pipeline: each workspace is `Active` and on its capacity, each identity is
`Active` with Contributor, each group has a named human owner, each role assignment resolves to the
group (`Viewer`, `Contributor` or `Member` — never `Admin`), and the audit log attributes the create
to `sp-fabric-admin`. If the audit log is empty after 24 hours, suspect the diagnostic setting
before the pipeline. If any of it fails, `scripts/report.sh` writes the archive to carry out — stage,
run id, error code, failing address, last check that passed.

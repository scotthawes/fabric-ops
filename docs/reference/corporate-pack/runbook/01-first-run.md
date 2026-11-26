# Runbook 01 — First run

**Illustrative · Pack: 2026-11-26.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

The stage order, the check after each stage, the stop conditions, and the half-state a stop leaves
behind. Read `../spec/0002-contract.md` §6 first; the graph is fixed there and this page only adds
the checks.

**Before the first run:** every verify in [runbook 00](00-bootstrap.md) has passed, the capacity
GUID for each environment is written down, and the pipeline's plan stage exists as a separate stage
(never inside `Prod-<domain>`, or the approval would fire before the plan exists).

## The order

```
Build ──▶ Platform ──▶ Domains ──▶ Nonprod ──▶ PlanProd ──▶ Prod-<domain>  (one per domain)
```

`Domains` exists only when `sp-fabric-admin` holds Fabric administrator and `domains.tfstate` is in
use (contract §4). If it does not, the stage is absent, not empty.

| Stage | Environment | Jobs | Gate |
| --- | --- | --- | --- |
| Build | none | bundle content, `fmt -check`, `validate`, parameter ↔ YAML parity | none — no connection, no backend |
| Platform | `fabric-platform` | `capacity-nonprod` ∥ `capacity-prod` | optional approval |
| Domains | `fabric-platform` | one apply against `domains.tfstate` | same optional approval |
| Nonprod | `fabric-nonprod` | one job per domain: control apply → content | none, or a reviewer |
| PlanProd | **none** | one plan per domain, artifact `tfplan-<domain>` | none — read-only |
| Prod-`<domain>` | `fabric-prod` | `assert_plan` → apply saved plan → content → assign | **human approval** |

## Build

- **Runs.** Bundles content once, `fmt -check` and `validate` per root, asserts that every domain row
  in `config/domains.yaml` has matching tfvars and state keys. No credential, no backend.
- **Check after.** One content artifact is published for the run; the job contains no
  `azureSubscription` and never calls `login`.
- **Stop if.** Any step logged in, the artifact was rebuilt per environment, or the parity check
  found a domain with a tfvars entry and no YAML row (or the reverse).
- **Half-state.** Nothing applied, no state touched. Safe to fix and re-run; the run's artifact dies
  with the run.

## Platform

- **Runs.** `capacity-nonprod` and `capacity-prod` in parallel, each against its own state key
  (`platform/nonprod.tfstate`, `platform/prod.tfstate`). The `domains` job is the next stage, not a
  job here.
- **Check after.** Each plan lists `rg-fabric-corporate` and its capacity and nothing else; the
  capacity is `Active`; `SP_ADMIN_OBJECTID` appears in `administration_members`. Write down both
  capacity GUIDs. A second plan for the same state is empty.
- **Stop if.** A plan proposes **replacing** an existing capacity (import it instead), a capacity is
  not `Active`, the plan contains anything beyond the group and the capacity, or one environment's
  job succeeded while the other failed — the pair is independent, so read both.
- **Half-state.** One capacity exists and is billed with no workspace on it; the other state key is
  untouched, so its job can be re-run alone. The split is deliberate: destroying nonprod cannot
  reach prod. Leaving one empty capacity is untidy, not dangerous — do not hand-delete it, because
  the other run may already reference it.

## Domains

- **Runs.** Applies `domains.tfstate`, the domain list from `config/domains.yaml`.
- **Check after.** One `fabric_domain` per row, names match the YAML exactly, and a second plan is
  empty. Count the rows before you look at the plan.
- **Stop if.** The plan proposes deleting a domain, the count differs from the YAML row count, or
  the SP is not a Fabric administrator (the stage should not exist in that case).
- **Half-state.** Some domains exist and some do not; each is independent, and re-running is
  idempotent. A domain with no workspace is invisible to users and safe to leave for the next run.
  A **deleted** domain is not recoverable by re-apply — stop before that plan.

## Nonprod

- **Runs.** Per domain, in the domain's own state key (`workspaces/<domain>/nonprod.tfstate`): the
  control apply (groups, workspace, identity, a role assignment per group plus the identity's own,
  optional storage grant, Git binding), then content with `sc-fabric-deploy`.
- **Check after.** One role assignment per group (three), plus the workspace identity's own
  Contributor; a workspace identity with a `service_principal_id`; workspace `Active` on its
  capacity; groups carrying `-viewers`/`-contributors`/`-members` and a named human owner; item
  count equal to the repo's.
- **Stop if.** `assert_plan` fails (fewer than three role assignments is rule 3), a plan shows a
  replacement or a group destroy, the identity has no `service_principal_id`, the capacity
  postcondition fails, or content reports an orphan deletion on a workspace that should be empty.
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

## Prod-`<domain>`

- **Runs.** `assert_plan` on the saved file, then apply **that file** (no plan, no `-var-file`), then
  content from the Build artifact, then the domain assignment.
- **Check after.** The apply consumed the approved artifact; no replacement and no destroy on
  `fabric_workspace`, `azurerm_fabric_capacity`, `fabric_domain` or `azuread_group`; the workspace
  is `Active`; item count equals nonprod; the assignment lists only the intended workspace IDs.
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

1. `assert_plan` exits non-zero — read its verdict line and the addresses; never bypass it.
2. A plan proposes replacement of a workspace, capacity or domain; or a destroy of a group,
   workspace or capacity.
3. A workspace plan has fewer than three role assignments, or an environment count differs from
   another environment with no tfvars difference.
4. A capacity is paused, or `data.fabric_capacity`'s postcondition did not evaluate.
5. A stage is **skipped** for any reason — read skipped as "did not run".
6. The plan is stale, or the artifact differs from what the approver read.
7. A value is still `PLACEHOLDER-…` or an all-zero GUID on a path that reaches an apply.

Condition 7 is the one a weak model misses: a placeholder that survived to an apply is not a
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
before the pipeline.

# Forbidden

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

Ten rules. Each is greppable: the **detect** line is what a reviewer or `checks/check-pack.sh`
looks for. Rules 1–4 and 9 are machine-checked; the rest are review rules, and a violation is a
blocked change, not a discussion.

## 1. No real IDs

- **Rule.** Tenant, subscription, capacity, workspace, group, connection and organisation IDs are
  `00000000-0000-0000-0000-000000000000` or a named placeholder (`PLACEHOLDER-…`). A real value is
  supplied by the corporate repo's tfvars, never by this pack.
- **Why.** The pack is copied by hand between organisations; an embedded ID is either wrong in the
  copy or a tenant fact leaking into a reference artefact.
- **Detect.** Any GUID that is not all-zero. `grep -rEo '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'`
  and read the distinct values; exactly one is allowed.

## 2. No secrets

- **Rule.** No credential of any kind in the pack or in the work repo: no `client_secret`, no
  `AccountKey`, no `PAT`, no `password=`, no `.env`, no variable group value. Both service
  principals are federated; Terraform reaches state with `ARM_USE_OIDC` and a data-plane role.
- **Why.** A secret would be the only thing in the design that cannot be rotated by re-running the
  pipeline, and it reintroduces the laptop credential ADR 0002 exists to remove.
- **Detect.** `client_secret`, `AccountKey`, a standalone `PAT` token, `password=`. The checker
  scans every file except this one and `checks/check-pack.sh`, which name the patterns by design.
- **If someone "temporarily" adds one:** delete it, rotate nothing (it never worked), and re-run
  `Verify and save` on the connection.

## 3. No `.tf` in the pack

- **Rule.** Terraform lives in `.tf.tmpl` skeletons. The only `.tf` files in existence are in the
  corporate work repo after a human copies and renames them.
- **Why.** A `.tf` here would be a runnable root in a research repo (ADR 0001) and would invite
  a local `terraform init` against a real backend.
- **Detect.** `find . -name '*.tf'` returns nothing.

## 4. No local `terraform apply`

- **Rule.** Every apply runs in the ADO pipeline. There is no credential on the corporate laptop and
  no local state. `import`, `state` and `force-unlock` are pipeline jobs with `sc-fabric-admin`. A
  read-only local `plan` is not decided by this pack; the default is no, because the pipeline's plan
  is the plan that gets approved.
- **Why.** The approval record and `assert_plan` are the controls; a laptop apply bypasses both.
  Issue #55: "the pipeline is the enforcement point".
- **Detect.** A run-book step, script or comment containing `apply` outside `pipelines/` or a
  pipeline job; a doc that says "run this on your machine".

## 5. No prod apply without an environment approval

- **Rule.** The `Prod-<domain>` stage targets `fabric-prod`, which carries an Approvals check with
  at least two named humans, instructions, a Timeout, and self-approval disabled. `isSkippable:
  false` on every prod stage.
- **Why.** The Approval record is the audit trail and the last control that assumes a human read the
  plan. A stage that lost `environment:` runs ungated and never complains.
- **Detect.** A prod stage with no `environment:`, an environment with no Approvals check, or a run
  whose prod stage is `skipped` — read skipped as "did not run".

## 6. No `-refresh=false`, no `-target`

- **Rule.** Neither flag appears in the pipeline, a run-book command or a troubleshooting recipe.
- **Why.** `-refresh=false` applies a plan against state the provider no longer believes; `-target`
  leaves the rest of the plan unapplied and makes the next plan unreadable. Both hide exactly the
  drift the gate exists to catch.
- **Detect.** `grep -rn -- '-refresh=false\|-target'`, allowed only in this file and in a "do not"
  sentence.

## 7. No editing ADRs to fit code

- **Rule.** An ADR records a decision. If the code disagrees, the code changes, or a new ADR
  supersedes the old one with a date. A decision is never rewritten to match what was built.
- **Why.** A silently amended ADR destroys the only record of why the constraint existed; the next
  reader then removes the control as noise.
- **Detect.** An ADR diff with no `Amended:` or `Superseded by:` line, in a change that also edits
  code or a skeleton.

## 8. No binding prod to Git

- **Rule.** `bind_git = true` only in a nonprod workspace tfvars. Prod workspaces are unbound; prod
  content arrives as the Build artefact, applied by the pipeline.
- **Why.** A Git-bound prod workspace lets a branch push change production outside the approval and
  outside `assert_plan`. `config/domains.yaml` names a nonprod repo per workspace for this reason.
- **Detect.** `bind_git` in `terraform/workspaces/env/<domain>/prod.tfvars`, or a
  `fabric_workspace_git` resource in a prod plan.

## 9. No copying a reference file as tenant fact

- **Rule.** A reference file (`docs/reference/…`, a skeleton, an example tfvars) is illustrative and
  dated. It becomes a tenant fact only when the corporate machine observes it and records the date
  and the observer, in `spec/0003-open-questions.md` or the work repo's own record.
- **Why.** Three capability verdicts in this repo were wrong because an illustrative shape was read
  as an observed one. A confident wrong answer about a tenant costs more than a gap.
- **Detect.** A `spec/0003` VERIFY closed without an observation, a date and a named owner; a claim
  sourced to a `.tmpl` file.

## 10. No item in Terraform state

- **Rule.** Terraform manages containers: capacity, resource group, groups, workspace, identity,
  role assignments, domain assignment. Items, schemas, schedules and shares are deployed by
  `fabric-cicd` and never entered into Terraform state or `terraform import`.
- **Why.** An item in state turns a content change into a control-plane plan, and a content rollback
  into a workspace replacement. It also makes `assert_plan`'s expected address set unmaintainable.
- **Detect.** A `fabric_*_item` (or any item-type resource) in a skeleton or a plan; an `import`
  of an item; a state key holding one.

## Applying these rules

- An agent that is asked to do any of the above **stops and asks**; it does not find a compliant-
  looking workaround (`agents/AGENTS.md`).
- A human who believes a rule must bend writes an ADR first. A commit is not a decision.
- The checker enforces what it can and is run before every hand-over; a green checker is a floor,
  not a review.

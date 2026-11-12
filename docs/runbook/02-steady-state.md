# Run-book 02 — Steady state

**Dated 2026-11-12.** [Spec 0002](../specs/0002-platform-operations.md) as procedures — written in the
form they would take if someone ran them, so that the shape of a healthy operation is legible to
whoever builds one elsewhere.

**A description, not a commitment.** This project is research-only and operates nothing
([ADR 0001, amendment 2026-11-12](../adr/0001-research-artefact-not-deployment-tool.md)); no stage in
this page is triggered here, and none of the escalation rules route to anyone in this repository. Four
recurring operations, each with an owner, an output and an escalation rule — owned, if at all, by a
platform team that is not this pack.

The test of this page: someone who has never run it can follow one operation and know whether the
result is good.

## 1. Deploy on merge — every merge

- **Trigger:** a pull request merges to `main`.
- **Steps:** the pipeline runs Terraform (containers) then `fabric-cicd` (definitions) then the schema
  stage, per environment. Prod waits for an approval on the ADO Environment.
- **Output:** stage results, the commit SHA deployed, and the item list per environment.
- **Good looks like:** all stages green, the SHA on prod equals the SHA on test.
- **Escalate if:** a stage is `skipped` rather than succeeded (an approval timeout looks like this),
  or the capacity state is not `Active` (see operation 4).
- **Detail:** [recommendation 03](../recommendations/03-deployment-and-environments.md).

## 2. Drift report — nightly

- **Trigger:** scheduled.
- **Steps:** for each environment, compare the deployed item definition with the committed one;
  record items present in the workspace but absent from the repo.
- **Output:** a stored artefact per environment, diffable week to week.
- **Good looks like:** zero differences on the morning after a deploy.
- **Interpretation:** one or two items is a portal edit that will be overwritten by the next deploy.
  More than five, or a whole folder, means someone is working outside the pipeline — that is a
  conversation, not a cleanup. **Corrected 2026-11-12:** an item that exists in the workspace but not in
  the repo is not overwritten, it is *deleted* by the standard `unpublish_all_orphan_items` call (into the
  recycle bin) on the next merge. Only items the repo defines are overwritten in place — see the
  [survey of the field](../research/operating-model-what-prior-art-supports-spec-0002.md).
- **Known noise:** item IDs, ordering and generated fields differ harmlessly; the report should
  normalise them before claiming a difference.
- **Escalate if:** a diff survives a redeploy. That means the deployer is not writing what the repo
  says, which is a fault in the pipeline rather than in the estate.

## 3. Access report — weekly

- **Trigger:** scheduled.
- **Steps:** read workspace role assignments from the admin API; expand every group through Entra to
  named people; list workspaces with no admin; carry forward the list of access paths the report
  cannot see.
- **Output:** principals per workspace with roles, plus an orphan list and an explicit "not visible to
  this report" section.
- **Good looks like:** every assignment traces to a group in the repo, or to a recorded break-glass
  exception; no orphans.
- **Known blind spots — state them in the report, do not omit them:** SQL `GRANT`s, OneLake security
  role membership (visible only from the item's own endpoint), shortcut credentials, and item sharing
  that was not created by the pipeline.
- **Escalate if:** a workspace has no admin, or a person appears with direct access rather than through
  a group.
- **Trap:** a role change only takes effect at the member's next Fabric sign-in, so a removal verified
  here may still be live in an open session.

## 4. Capacity review — weekly

- **Trigger:** scheduled, plus on any throttling complaint.
- **Steps:** read utilisation, interactive-delay and background-rejection percentages, and overage
  against the configured threshold; check the alert listener is still running and still owned.
- **Output:** one figure per measure, the overage threshold and its headroom, and alert health.
- **Good looks like:** peak smoothed usage comfortably under 100%, no carryforward, listener healthy.
- **Watch:** the overage default bills at three times pay-as-you-go; the threshold should stay below
  one-third of daily capacity hours.
- **Escalate if:** production is throttled by non-production load twice, or sustained usage exceeds the
  SKU — that is ADR 0004's documented trigger to split the capacity, and it is cheap to do.

## Quarterly reviews — decisions, not documents

| Review | Question it answers | Change it can produce |
| --- | --- | --- |
| Licence reconciliation | Who is a Viewer, and does the F64 entitlement still cover them? | Move people between Viewer and Contributor groups |
| Access recertification | Does every group member still need access? | Remove members in Entra; close break-glass exceptions |
| Capacity sizing | Is the SKU right for the last quarter's peak? | Resize, or split production onto its own capacity |
| Label coverage | Which items carry no label, and is that accepted? | Apply labels; record accepted risk |

## Escalation: symptom to first check

| Symptom | Check first | Owner |
| --- | --- | --- |
| Deploy fails on item creation | Capacity state, then workspace role | platform engineer |
| Report opens but will not refresh | Connection binding and credentials | data engineer |
| User cannot see a report | Workspace role, then item sharing, then app audience | security reviewer |
| Everything slow at 10am | Capacity throttling and concurrent background jobs | capacity owner |
| Nothing has alerted in a week | Alert listener ownership and state | capacity owner |
| Warehouse deployed but empty | Schema stage, not the item stage | platform engineer |

## What this run-book does not cover

Incident response beyond the first check, change advisory process, and staffing — organisational
facts the pack cannot supply. **For the regional-disaster case specifically (2026-11-12):** the documented
story is a read-only failover and a manual rebuild, not a recovery guarantee — see
[`business-continuity-what-does-fabric-guarantee.md`](../research/business-continuity-what-does-fabric-guarantee.md).
A capacity does not fail over; you create a new one. Where a symptom has no first check here, the gap is real: add it when it
is discovered, with the date.

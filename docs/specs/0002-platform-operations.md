# Spec 0002 — Operating the Fabric platform

- **Status:** synthesis — the plan of operations, for the work repo and the tenant team to execute
- **Date:** 2026-11-12
- **Derived from:** [guides/what-goes-where](../guides/what-goes-where.md),
  [guides/automation-coverage](../guides/automation-coverage.md), the eight ADRs, and the
  [run-book](../runbook/01-work-tenant-checklist.md)
- **Relationship to spec 0001:** 0001 described *how content gets deployed*. This one describes
  *how the platform is run* — including everything that happens when nobody is deploying.

## Problem Statement

The pack answers "how do we deploy this?" thoroughly and "what do we do on the first day?" partially.
It does not answer the question that decides whether the platform survives its second month:

- **Who does what, and when?** Capacity, access, content, connectivity and cost each need a different
  cadence and a different owner. Today that lives in eight ADRs and a run-book, which nobody reads
  on a Tuesday.
- **What happens between deployments?** Drift appears, people join and leave, a schedule quietly
  disables itself, overage accrues, a workspace loses its last admin.
- **What does "healthy" look like?** Without a defined steady state, every problem is discovered by a
  user rather than by us.

Without an operating model, the automation we designed becomes a machine that ships content into an
estate nobody is watching.

## Solution

A phased operating model with three parts:

1. **Bootstrap** — a one-time, ordered sequence to get from nothing to a deployed first environment.
2. **Steady state** — a small set of scheduled and on-merge operations, each with an owner, a cadence
   and a defined output.
3. **Review cadence** — periodic decisions that are neither incidents nor deploys: licence
   reconciliation, capacity sizing, access recertification, label coverage.

The model is deliberately small. Every recurring operation earns its place by producing something
that changes a decision or catches a failure; anything that only produces reassurance is cut.

## User Stories

1. As a platform engineer, I want an ordered bootstrap sequence, so that the first environment is
   built the same way every time rather than from memory.
2. As a platform engineer, I want each bootstrap step to say whether it is code, a pipeline run, or a
   human action, so that I know when I am blocked and on whom.
3. As a platform engineer, I want the two admin-consent steps identified up front, so that I request
   them before they block the build.
4. As a platform engineer, I want a merge to deploy dev automatically, so that routine change needs no
   ceremony.
5. As a platform engineer, I want prod to require an approval recorded against the commit, so that the
   change record is complete without extra paperwork.
6. As a platform engineer, I want a nightly job that tells me what has drifted, so that portal edits
   are found by us rather than by the next deploy overwriting them.
7. As a security reviewer, I want a weekly access report joining Fabric roles to Entra groups, so that
   I can answer "who can see this" without clicking through workspaces.
8. As a security reviewer, I want orphaned workspaces listed, so that a workspace whose admins have
   left is found before it becomes an incident.
9. As a capacity owner, I want a weekly utilisation and overage figure, so that I know whether the
   shared SKU is still sized correctly.
10. As a capacity owner, I want a monthly check that the overage threshold is still below one-third of
    daily capacity hours, so that a runaway workload cannot bill at three times the rate unnoticed.
11. As a capacity owner, I want a documented decision on whether production may be down out of hours,
    so that pause/resume is either available or ruled out rather than ambiguous.
12. As an operations engineer, I want the five capacity alerts to exist and be owned, so that
    throttling and unexpected pauses page someone.
13. As an operations engineer, I want a listener-ownership check, so that alerting cannot silently stop
    while the estate looks calm.
14. As an operations engineer, I want a runbook entry for a paused or throttled capacity, so that a
    failed deploy is diagnosed as capacity, not as a broken item.
15. As a data engineer, I want to know which item types cannot be deployed, so that I design within the
    platform's limits.
16. As a data engineer, I want a failed deploy to name the item and the environment, so that retrying
    is a decision rather than a guess.
17. As a data engineer, I want the schema step to fail loudly when it leaves an empty warehouse, so
    that a green pipeline is not mistaken for a working one.
18. As a data engineer, I want connection bindings applied per environment by the pipeline, so that a
    deployed model can actually refresh.
19. As a data engineer, I want a list of what remains manual after a deploy, so that go-live does not
    discover it.
20. As a platform owner, I want a licence reconciliation each quarter, so that the F64 viewer
    entitlement is checked against who is actually a Viewer.
21. As a platform owner, I want role assignments reviewed on a cadence, so that Contributor grants made
    "to unblock someone" do not become permanent.
22. As a platform owner, I want a single page listing what is automated and what is human, so that
    expectations are set before an audit rather than during one.
23. As an auditor, I want evidence that approvals happened and by whom, so that change control is
    demonstrable.
24. As a new joiner, I want access to arrive through group membership, so that my first day does not
    depend on a ticket.
25. As a leaver's manager, I want offboarding in Entra to end Fabric access, so that I do not need to
    know which workspaces exist.
26. As a security reviewer, I want the limits of the access report stated, so that I do not treat an
    incomplete answer as complete.
27. As a platform engineer, I want labels applied by a named process, so that "unlabelled" is a known
    state rather than an accident.
28. As a platform engineer, I want a documented rollback-or-forward decision per failure class, so
    that incidents do not become debates.
29. As a platform engineer, I want provider and preview-version upgrades as a scheduled task, so that
    an upstream breaking change is not discovered during a release.
30. As an architect, I want the operating model to name its own triggers for change — when to split the
    capacity, when to revisit the layout — so that the design does not calcify.

## Implementation Decisions

**Bootstrap is ordered, and two steps are other people's.**

Phase 0 (human, blocking): a Privileged Role Administrator consents the Graph application permissions;
a Project Collection Administrator adds the first service principal to the ADO organisation. Nothing
scriptable happens before these.

Phase 0 (confirmable, not built): network posture, the four service-principal tenant settings, the two
Git-export switches.

Phase 1 (Terraform): capacity root, then workspaces root with role assignments and the dev Git binding.

Phase 2 (pipeline): first items, then the schema stage, then promotion to test and prod.

Phase 3 (human, per environment): connections and datasource credentials, bindings, labels, sharing,
alerts.

**Steady state is four operations, no more.**

| Operation | Cadence | Output | Owner |
| --- | --- | --- | --- |
| Deploy on merge | every merge | dev; test; prod behind approval | pipeline |
| Drift report | nightly | items where deployed ≠ committed | platform engineer |
| Access report | weekly | principals per workspace, groups expanded, orphans flagged | security reviewer |
| Capacity review | weekly | utilisation, throttling, overage, alert health | capacity owner |

**Reviews are quarterly, and produce decisions, not documents.** Licence reconciliation (Viewer vs
Pro), access recertification, capacity sizing against the split trigger in ADR 0004, and label
coverage.

**Every operation names its failure mode.** A drift report that cannot read a workspace says so; an
alert listener that has lost its owner is itself an alert; a schema step that leaves an empty
warehouse fails the run.

**Ownership is explicit:** capacity owner (one named person), platform engineer (the pipeline and
Terraform), security reviewer (access), data engineers (content), tenant admin (settings, consents).

## Testing Decisions

An operating model is tested by whether it detects a planted fault, not by whether its documents
exist.

- **Bootstrap is verified once, end to end, in a throwaway workspace** before the real build: create,
  assign, grant, bind, deploy, read back. Anything that fails there fails in a controlled place.
- **Each steady-state operation is tested by planting its failure**: edit an item in the portal and
  confirm the drift report names it; remove a group member and confirm the access report changes; pause
  the capacity and confirm both the deploy failure and the alert.
- **The guards are tested too**: a push with a broken link must fail CI; a deploy missing its approval
  must not reach prod.
- **No test asserts a document's content.** A run-book entry is proven by a human following it once.

## Out of Scope

- Building the work repo, or any code in this repository (ADR 0001).
- Application features and data products; this is the platform underneath them.
- Capacity purchase and finance approval; the model consumes a decision, it does not make it.
- Tenant-wide administration beyond the settings the design depends on.
- Multi-tenant or sovereign-cloud variations.

## Further Notes

**The seams to confirm before this becomes tickets**, in preference order: (1) the pipeline's stage
gates, because they already exist and carry approval semantics; (2) the nightly jobs' outputs, which
are the only mechanism for noticing drift and access change; (3) the run-book, which is where a human
is genuinely in the loop. Recommended: 1 and 2 as gates, 3 as the human path.

**What this spec deliberately does not decide:** how many people are needed, which team owns the
capacity budget, and whether the security review is internal or delegated. Those are organisational
facts the pack cannot supply, and inventing them would make the plan look more finished than it is.

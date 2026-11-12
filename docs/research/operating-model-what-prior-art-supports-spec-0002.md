# What does the open-source field support in spec 0002's operating model?

- **Status:** answered · **Checked:** 2026-11-12
- **Blocks:** any refinement of [spec 0002](../specs/0002-platform-operations.md); a builder's
  expectations of which operations have a pattern to copy
- **Derived from:** [`pipeline-designs-what-open-source-examples-implement.md`](pipeline-designs-what-open-source-examples-implement.md)
  — fifteen repos read at recorded commits. This note reuses that evidence rather than re-reading it.

## Short answer

Of spec 0002's four steady-state operations, **one is well supported** (deploy on merge, with one
refinement the field earns), **one has a single implementation** (drift, and it is bespoke code rather
than a library feature), and **two have no prior art at all** in the sample (the weekly access report
and the weekly capacity review). The contact also exposes a conflict *inside* 0002: deploy-on-merge
deletes the evidence its nightly drift report is looking for, so the report is a record of what was
overwritten rather than a control that prevents it.

## Detail

### 0. What "supported by the field" can and cannot mean here

The sample is fifteen community and first-party repositories, read as code, against a platform that is
roughly two years into general availability. Three limits apply to every verdict below:

- **Absence is not impossibility.** These repositories exist to *ship content*, not to *operate an
  estate*. A missing access report may mean the operation is unwise, unavailable, or simply not what
  someone writes a demo repository to show.
- **Popularity is not evidence.** The most careful designs in the sample are among the least starred.
- **Nothing was executed.** Every verdict is read from YAML, Python and PowerShell at a named commit.

With those limits, "no prior art" is a claim about **what exists to copy and what has been shown to
work**, which is what a builder actually needs to know.

### 1. The four operations, against the field

| Spec 0002 operation | Field support | Evidence |
| --- | --- | --- |
| Deploy on merge | **Corroborated** — nine of the sample's fifteen deploy item definitions from the repo on a branch push; the dominant shape matches 0002 exactly | `fabric-cicd` full-deployment model; kevchant ADO/GitHub YAML; michaeldeongreen orchestrators |
| Drift report, nightly | **One implementation**, and it is not a library feature | gronnerup `engine/drift.py` + `engine/actions.py:_current_hash` |
| Access report, weekly | **None** in the sample | — |
| Capacity review, weekly | **None** in the sample, and 0002 does not name its data source | — |

Two further 0002 assumptions are corroborated by the field's shared shape: the workspace is
infrastructure (no example lets the deployer create one), and dev is the only Git-bound workspace.
Both are what 0002 places in Terraform and phase 1.

### 2. Deploy on merge — corroborated, with one refinement and one unstated risk

**Corroborated.** 0002 says the pipeline runs Terraform then `fabric-cicd` then schema, per
environment, with prod behind an approval. That is the dominant shape: repo → REST publish, workspace
pre-existing, full deployment each run. `microsoft/fabric-cicd`'s own overview states the stance
plainly: it "applies a full deployment on every run — it does not inspect commit history or compute
diffs … preventing environment drift"
(`docs/how_to/deployment_overview.md:16`).

**Refinement — where the approval's evidence lives.** 0002's user story 5 wants prod approval
"recorded against the commit". The sample shows why the obvious placement disappoints: ADO evaluates
an environment's checks when the *stage* begins, so anything in the prod stage runs after approval.
Only one repo designs around this — EvaluationContext puts a **prod plan as the last job of the test
stage**, so the approver reads a plan rather than a commit hash
(`.azure-pipelines/deploy-release.yml:19-23,72-93`). Everywhere else a gate either is unconfigured or
looks configured and isn't. This is a one-line improvement to 0002 and worth taking.

**Unstated risk — the deploy deletes what the repo does not contain.** Every `fabric-cicd` wrapper in
the sample calls `unpublish_all_orphan_items`, whose default exclude regex is `^$` — nothing is
excluded. It calls the Fabric Delete Item API on every item in the target workspace that the repo does
not define (`src/fabric_cicd/publish.py:298-380`). Deleted items land in the workspace recycle bin
unless the `enable_hard_delete` flag is on, which requires workspace Admin and is exactly what
[ADR 0002](../adr/0002-two-service-principals-federated.md) refuses the deploy identity. 0002 mentions
orphan handling nowhere. A reader would reasonably expect a portal-created item to be *reported*, and
would instead find it *deleted* by the next merge.

### 3. Drift report — one implementation, and it is custom code

gronnerup is the only repo that answers "is the tenant still what the repo says?" without deploying.
The design is worth copying in principle: there is no state file, the tenant is the source of truth, and
drift is the same code path as a dry run, so the check can never disagree with what a real run would do
(`automation/src/fabricops/engine/drift.py:1-12`). Implementation is export the definition, hash it,
compare (`engine/actions.py:431-443`).

Three consequences 0002 should absorb:

- **It is not a `fabric-cicd` feature.** The library refreshes deployed metadata to decide create vs
  update; it does not compare definitions. A nightly drift report is therefore a **third bespoke
  tool** alongside Terraform and `fabric-cicd`, and 0002 budgets for two.
- **It costs a full export per item per run.** That is the price of having no state file.
- **Its detection window is set by merge frequency, not by the schedule.** Because the next full
  deployment rewrites the workspace to match the repo, a portal edit survives only until the next
  merge. On a busy repository, a *nightly* report mostly reports what a deploy already reverted. The
  report is a record of change, not a control against it — and it should say so, or be gated before
  the deploy rather than after.

### 4. Access report — no prior art, and it inherits the consent gate

Nothing in the sample attempts this. The nearest things in the wider ecosystem index are rule-based
tenant testing (`NatVanG/fab-inspector`) and a metadata-only estate scan
(`microsoft/fabric-architecture-review`) — neither is a join of Fabric role assignments to Entra group
membership, which is what 0002 asks for.

Two dependencies 0002 does not state:

- **Graph is required to expand groups**, and Graph app-only access is one of the two consents in
  bootstrap phase 0. If that consent is refused, the report degrades to principal and group object ids
  with no people in it — still useful for "is a person directly assigned", useless for recertification.
  Say which of the two a reader is getting.
- **The read is rate-limited and partly Preview.** Roughly 200 requests/hour for the admin reader, and
  the per-workspace access endpoints are Preview (run-book 01, item 8). A weekly cadence is
  comfortable; the report must still handle a truncated run rather than presenting a partial estate as
  complete — which is the same honesty 0002's user story 26 asks for.

### 5. Capacity review — no prior art, and the spec does not name a data source

This is the sharpest gap. 0002 schedules a **weekly** review that reads "utilisation, throttling,
overage and alert health". None of the fifteen does anything like it. More importantly, the pack's own
research says the obvious source does not exist: there is **no Azure Monitor metric namespace for
`Microsoft.Fabric`**, and "creating alerts from the Fabric or Power BI Capacity Metrics app isn't
supported" ([`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md), lines 9-11, 86).

The machine-readable path is the Real-Time hub events — `Microsoft.Fabric.Capacity.Summary` every 30
seconds, `Microsoft.Fabric.Capacity.State` on change — which the same note already designs five alerts
around. So the weekly review is either:

- **an event pipeline** to a store that survives longer than the 14-day compute / 30-day storage
  windows the metrics app offers, or
- **a human reading a portal page**, which is what it silently is today.

0002 should name which, because "weekly, scheduled" implies the first and the pack elsewhere says the
second is the only thing that currently works. This note does not decide it; it records that the
operation as written has no stated mechanism.

### 6. Bootstrap — corroborated by the field's silence

No example touches Graph application permissions or ADO organisation membership; the two consent steps
in 0002's phase 0 have no counterpart in the sample at all. That absence is consistent with the census
finding that those operations are app-only capable but need an administrator: nobody has automated
them, because nobody who writes a sample repo has that role. 0002 treating them as human and blocking
is the field's implicit position, made explicit.

## What this settles

- **Deploy on merge is the one operation with real backing**, and the refinement worth taking is
  placing the prod plan in the prior stage, because of how ADO evaluates environment checks.
- **The deploy deletes orphans by default.** Any operating model that assumes drift detection will
  find portal-created items is wrong: the next merge deletes them into the recycle bin first.
- **Drift detection is custom code, not a library feature**, and needs a third tool plus a full
  export per item per run. 0002's cost and structure assume two tools.
- **Two of the four operations have no prior art.** That is not a reason to drop them; it is a reason
  to say plainly that a builder is designing them, with no pattern to copy and no evidence anyone has
  run them.
- **The capacity review has no named data source**, and the pack's own research says the obvious one
  is closed. As written, it is a human reading a portal page described as a scheduled job.

## What this does not establish

- **That the unsupported operations are wrong.** No prior art means no pattern; 0002's argument for
  the access report is a real security argument, not a fashion.
- **That the field is representative.** Fifteen repositories, skewed to demos; a mature platform team's
  internal pipeline is not on GitHub.
- **What any of it costs at scale.** Export-per-item drift, rate-limited access reads and event
  retention are all unmeasured here.
- **That 0002's schema stage is misplaced.** Only three repos have one at all, and their placement (in
  the same pipeline, after items) is consistent with 0002 rather than against it.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`pipeline-designs-what-open-source-examples-implement.md`](pipeline-designs-what-open-source-examples-implement.md) | The fifteen-repo sample, its commit SHAs and per-axis findings | 2026-11-12 |
| [`microsoft/fabric-cicd` @ v1.4.0](https://github.com/microsoft/fabric-cicd/tree/59a0fe8612dd90cd7d7c2021ee6bad71b08cf477) | Full-deployment stance (`deployment_overview.md:16`); `unpublish_all_orphan_items` semantics and recycle-bin default (`publish.py:298-380`) | read 2026-11-12 |
| [`gronnerup/FabricOps`](https://github.com/gronnerup/FabricOps/tree/e2d34a23204c0d97746a93f4ca1eaa4615c31d44) | Drift as a dry run; export-and-hash comparison; no state file | read 2026-11-12 |
| [`EvaluationContext/fabric-cicd-example`](https://github.com/EvaluationContext/fabric-cicd-example/tree/3f04b2898dfe9f92eb90fb021057ce278464a83d) | Prod plan in the test stage because of ADO check timing | read 2026-11-12 |
| [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) | No `Microsoft.Fabric` Azure Monitor metrics; metrics app cannot alert; events are the machine-readable path | 2026-11-12 |
| [`../specs/0002-platform-operations.md`](../specs/0002-platform-operations.md) | The operations, user stories and test decisions being checked | 2026-11-12 |
| [Run-book 01, item 8](../runbook/01-work-tenant-checklist.md) | Admin API rate limit and Preview status of per-workspace access endpoints | 2026-11-12 |

# 0001 — Closed decisions

Pack: 2026-11-26.2 · illustrative, not runnable from fabric-ops (ADR 0001)

Thirteen decisions, each closed on 2026-11-26 against wayfinder map
[#41](https://github.com/scotthawes/fabric-ops/issues/41). One section per decision: what was
decided, why, what it costs, and what it overrides. The interface those decisions produce is
[0002-contract.md](0002-contract.md); the facts still missing are
[0003-open-questions.md](0003-open-questions.md).

An ADR named here as superseded is not deleted. It is read as history: it explains the estate that
exists, and it is why the convergence in §11 has the shape it has.

---

## 1. Two environments only: `nonprod`, `prod`

**Decision.** Exactly two environments. No `dev`, `test`, `uat`, `staging` or fourth word. A
short-lived experiment is a suffixed workspace on `nonprod`, not a new environment. The environment
token is the last segment of every name.

**Why.** Three environments multiplied state blobs, approval stages and naming without buying
isolation: under ADR 0004 all three shared one capacity, so a runaway in `dev` already throttled
`prod`. Two is the minimum that gives a separate apply target and a separate capacity; a third tier
would add a stage and a state without a separate approver or a separate bill.

**Cost.** There is no soak tier between `nonprod` and `prod`. A change that needs a week of quiet
running soaks in `nonprod`, which has no production data and an F2 that throttles. Anything that
genuinely needs production-like volume has to be argued as a prod change with a prod approval.

**Supersedes/amends.** Supersedes ADR 0004's three workspace sets and ADR 0005's `dev`/`test`/`prod`
stage names. Amends naming rule 3, which currently permits `dev` and `test`.

---

## 2. One project per domain; two workspaces per domain

**Decision.** Each domain holds exactly one project and two workspaces, `fabric-<domain>-nonprod`
and `fabric-<domain>-prod`. The project token is part of the workspace name, so it is not part of the
state key. One Fabric domain holds both environments' workspaces; there is no subdomain per
environment.

**Why.** "One state per domain+environment" only closes if the project count per domain is fixed at
one. Naming rule 6 puts the project in the workspace name, which would multiply workspaces by
projects and leave the state key unable to identify one. Fixing the project at one keeps the state
key two-dimensional. Subdomains were rejected because they carry no own admins and no delegated
settings — they would be a third name level with no authority behind it.

**Cost.** A team that needs a second project inside a domain must add a domain, not a workspace; it
pays a new capacity share, three new groups and a new prod stage. Workspace names grow by the project
token, and the 40-character limit in naming rule 7 bites sooner.

**Supersedes/amends.** Resolves the gap flagged in #47 and naming rule 6. Amends ADR 0010 §2 and
naming rule 5, whose group-name contract is now `fabric-<domain>-<env>-<role>`.

---

## 3. Two capacities: F2 nonprod, F64 prod

**Decision.** One capacity per environment, shared across all domains:
`fabric-capacity-nonprod` at **F2**, `fabric-capacity-prod` at **F64**, same region, fixed at
creation. Overage **off** on nonprod and capped **below one-third of daily CU hours** on prod.
Nonprod is paused **manually**, not on a schedule, until open question #19 is answered. Capacity
admin is a named human with a named deputy; the admin SP is intended to hold Contributor, or to sit
on the capacity admin list if it cannot (OQ-02).

**Why.** F64 is the pack's only licence floor: at F64 and above a workspace Viewer can read on a
Free licence, below it every viewer needs Pro or PPU. Buying the floor on prod avoids re-imposing
Pro on every reader. F2 is the cheapest nonprod that runs the content path. Manual pause is chosen
over a window precisely because what a scheduled refresh does to a paused capacity is unverified;
automating an unverified behaviour is how a quiet estate looks like a working one.

**Cost.** F2 cannot host an Eventhouse path, so ADR 0009's monitoring store needs its own F4 — a
third capacity the "two capacities" sentence does not mention. Overage is not a cap: it bills at
roughly three times pay-as-you-go once crossed. It is not expressible in AzureRM, so it arrives only
through `azapi` at `2026-09-01-preview` and never appears in `terraform plan`. F2 will throttle a
runaway; that is the intent, and it must be stated to anyone who expects prod behaviour in nonprod.
No prices are recorded here.

**Supersedes/amends.** Supersedes ADR 0004 (one shared capacity). Amends ADR 0009, which assumed the
monitoring store could sit on the shared capacity.

---

## 4. Domains created by Terraform, with a human fallback

**Decision.** By default a named human creates each Fabric domain, and
`scripts/assign_domains.py` assigns workspaces through the Core API
`POST /workspaces/{id}/assignToDomain`, which needs workspace admin plus domain contributor or
admin. Terraform domain creation (`terraform/domains`) is **optional and off by default**; it is
enabled only when the read-only probe proves the admin SP holds Fabric administrator.

**Completed 2026-11-26.** The default is now the fallback itself. There is no channel back from the
corporate tenant, so the design cannot wait on the Fabric-administrator answer; the safe branch is
the one that works either way. The probe reports whether the optional root may be enabled, but
nothing depends on it.

**Why.** All three provider domain resources (`fabric_domain`,
`fabric_domain_role_assignments`, preview `fabric_domain_workspace_assignments`) go through the
admin API group, so through Terraform each one needs Fabric administrator. The Core path is
narrower and avoids the role entirely. One domain can hold both environments, so the fallback does
not fork the layout: a domain GUID enters the workspaces root as data either way.

**Cost.** Fabric administrator is tenant-wide: a principal that can create domains can also destroy
assignments across every domain in the tenant. That blast radius is the price of automating a
resource that only exists to delegate. The fallback is a second code path and makes a new domain a
run-book step rather than a YAML edit. Destroying the assignment resource **unassigns** the
workspace — a stop-on condition, never routine.

**Supersedes/amends.** Amends ADR 0007, which had no domains root. Recorded from #42 and #44.

---

## 5. Three groups per workspace; Admin stays a named human

**Decision.** Every workspace gets three Entra groups — `fabric-<domain>-<env>-viewers` (Viewer),
`-contributors` (Contributor), `-members` (Member). Workspace **Admin is never a group**: it is a
named human with a named deputy. Each group is owned by that workspace's Admin human. The pipeline
creates the groups; the human owns and edits membership.

**Why.** Member is not a convenience tier. It can add users, republish apps and edit OneLake
security, so owning it is an access-administration grant rather than ordinary membership. Keeping it
off every workspace was considered and rejected: the corporate design wants the same three tiers on
every workspace, and a conditional tier makes the access report explain two shapes. Admin stays
human because a group that can add admins makes the membership bound unenforceable.

**Cost.** Two or three domains produce 12–18 groups, each requiring an owner and a quarterly review.
One owner per workspace keeps recertification with the person who knows the work, but makes the
review self-review; a platform-team owner would fix continuity and hand that team effective Member
authority everywhere. The access report must separate group-Member from person-Member and fail on
direct per-user grants made below Admin, or the bound the design claims does not exist.

**Supersedes/amends.** Amends ADR 0006 (one group per workspace becomes three) and ADR 0010 §4–§5:
the closed suffix list gains `members`, a group **may** hold Member, and a group still may not hold
Admin. Amends naming rule 5.

---

## 6. One repository per nonprod workspace; prod unbound

**Decision.** Each nonprod workspace binds to its own Azure DevOps repository,
`fabric-<domain>-nonprod`, on its own branch. Prod is not Git-bound. The binding is a resource in
the workspaces root and the service principal authenticates by `ConfiguredConnection` only. Prod
receives the same commit through the pipeline.

**Why.** A binding is provider + organisation + project + repository + branch + folder, and two
workspaces on the *same folder* are replicas: the initial sync is destructive, there is no
cross-workspace merge, and commits are disabled until the workspace updates. One repository per
workspace removes the shared branch, the shared initial-sync blast radius and the shared review
policy. Prod stays unbound because a prod-authoring surface is the thing ADR 0005 exists to prevent.

**Cost.** N repositories to create, permission and later archive, and the service connection needs
access to every one. Every nonprod commit has one obvious home, which means a cross-domain change is
N pull requests. A portal edit in prod is invisible to the repo and is overwritten on the next
deploy; that must be said to every Contributor, not discovered.

**Supersedes/amends.** Amends ADR 0005 (dev-bound, test and prod unbound becomes nonprod-bound,
prod unbound). Recorded from #43 and #52.

---

## 7. Four Terraform roots; one state per domain+env

**Decision.** Four roots:

| Root | State | Owns |
| --- | --- | --- |
| `terraform/platform` | `platform/nonprod.tfstate`, `platform/prod.tfstate` | resource group, one capacity each |
| `terraform/domains` | `domains.tfstate` | `fabric_domain` — only if the SP holds Fabric administrator |
| `terraform/workspaces` | `workspaces/<domain>/<env>.tfstate` | groups, workspace, role assignments, nonprod Git binding |
| `terraform/domain-assignments` | `assignments/<domain>.tfstate` | preview assignment resources |

Platform is split by environment so destroying the nonprod capacity cannot reach the prod state.
There are no `modules/` — each root has one call site. `config/domains.yaml` in the corporate repo is
the matrix truth; adding a domain is a YAML entry plus two tfvars files, with no HCL edit.

**Why.** The capacity is an Azure resource that outlives every workspace and is applied by a
different principal; the workspaces root is applied per domain per environment with its own lock.
A shared state would make a nonprod failure able to block a prod apply. Keeping preview resources in
their own root stops `preview = true` — a provider-wide flag — from covering production containers.

**Cost.** Five to seven state blobs to back up, lock and restore, where ADR 0007 had two. The
capacity enters the workspaces root as `data "fabric_capacity"` by name, so the name is ambient and a
duplicate display name is ambiguous; `terraform_remote_state` would buy a declared output at the cost
of coupling to another root's output names. Under the §4 fallback the domains root disappears, and
when the assignment resource graduates the assignments root folds back in — both are layout changes
with state moves.

**Supersedes/amends.** Amends ADR 0007 (two roots become four; capacity root split per environment).
Records the two-capacity divergence from ADR 0004.

---

## 8. One ADO project, three shared environments

**Decision.** One Azure DevOps project holding three shared environments — `fabric-platform`,
`fabric-nonprod`, `fabric-prod` — two app registrations with federated credentials and no secret,
two service connections (`sc-fabric-admin`, `sc-fabric-deploy`), one state container, N repositories
(one per nonprod workspace) plus the pipeline repository. **Platform applies first.**

**Why.** Environment names cannot be variables, so a per-domain environment set would make every new
domain a bootstrap step, not a YAML entry. Shared identities keep the count flat as N grows: two app
registrations, two connections and three environments whether there are two domains or five. Platform
first means a delayed Graph consent cannot block the capacities.

**Cost.** One project is one permission boundary and one place to lose access; a second project is a
second bootstrap. Three environments is the most that stays legible — a fourth gate means a fourth
environment, which means a human step. Every domain's prod stage shares `fabric-prod`, so approval
policy is global even though approvals are per stage.

**Supersedes/amends.** Extends ADR 0002 (two federated service principals) with the environment and
connection set. Replaces run-book 03's four-environment precondition. Recorded from #49.

---

## 9. Environment-first promotion; N prod stages

**Decision.**

```
Build ──▶ Platform ──▶ Domains ──▶ Nonprod ──▶ PlanProd ──▶ Prod-<domain> (one stage each)
```

Fan-out happens inside each band; only the gate forces structure. `PlanProd` runs **outside** any
environment and emits one saved plan artifact per domain (`tfplan-<domain>`). Each `Prod-<domain>`
stage runs `assert_plan` → apply saved plan → content → assignment, and raises its **own human
approval**. One plan and one approval per domain: **N approvals per run**, plus at most two for
Platform and Nonprod. `isSkippable: false` on every prod stage.

**Why.** A matrix expands a *job*, a deployment job's strategy is `runOnce`, and `environment:` must
be a literal, so a matrix leg cannot be gated — matrix where there is no gate, explicit stages where
there is. The plan cannot be made inside the prod stage: ADO checks the environment at stage start,
so the approval would fire before the plan exists. One artifact per domain means applying the wrong
plan is not a typo away.

**Cost.** N prompts for N domains, and nothing binds an approval to reading the plan except the stage
boundary. The approver who clicks through N stages has approved N diffs they may not have opened.
A rejected approval is final for that stage; a stale prod apply fails only its own stage and needs a
new run and a fresh approval. A nonprod failure skips `PlanProd` by the default condition, which is
correct — the commit is the artefact — but it means one broken domain blocks every domain's
promotion in that run.

**Supersedes/amends.** Amends ADR 0005's single prod approval and pinned-commit promotion. Recorded
from #48.

---

## 10. The pack shape

**Decision.** `corporate-pack/` under `docs/reference/`, containing:

- `spec/` — these three documents;
- `skeletons/terraform/**` and `skeletons/pipeline/**`, every file with a `.tmpl` extension;
- `skeletons/scripts/`, the same;
- `runbook/`, `agents/`, `checks/check-pack.sh`;
- `VERSION`, the only place the pack version is written, and `forbid.md`, the greppable rules.

`check-pack.sh` fails on a real `.tf`, a non-placeholder GUID, a secret-shaped string, a broken
relative link, a file absent from the index, or a header that disagrees with `VERSION`.

**Why.** The corporate machine reads this repository and copies the pack. A `.tf` file here could be
consumed by `terraform init` and applied against a real subscription. A placeholder GUID copied as
truth targets the wrong tenant. A skeleton absent from the index is a file nobody reads, and an
unversioned edit is a change nobody can trace. The `.tmpl` suffix makes accidental execution
impossible rather than discouraged.

**Cost.** Every skeleton edit is a pack version bump, and a copy that diverges is a dated finding,
not a patch sent back. The pack cannot be tested by running it, so the checker is the only mechanical
gate and its own correctness is unverified until the corporate repo runs it once. The pack
deliberately does not decide tenant settings, approvers, region, prices or imports; those gaps are
visible in 0003 and in the README's "what this pack does not decide".

**Supersedes/amends.** None. Permitted by ADR 0001 as a labelled, dated reference artefact. From #50.

---

## 11. Converge on the existing estate, per object class

**Decision.** Mixed, by class:

| Class | Action |
| --- | --- |
| Resource group, capacity, Fabric domains, workspaces, Entra groups | **import** |
| Role assignments | **rebuild** by apply |
| Git bindings | **adopt last**, nonprod only, after content is committed out, `PreferWorkspace` |
| Items | **never import** — `fabric-cicd` owns definitions |

Freeze apply; inventory every workspace (ID, items, Git, grants, identity); write a live-ID →
state-key table **before** importing one workspace per key. Confirm `service_principal_id` is
non-null after a workspace import. Retire only with `removed { lifecycle { destroy = false } }`.

**Why.** Recreating a capacity detaches every workspace and is not restorable. A workspace import
records the container and no items, so the risk is a later destroy/replace, not a missing item in the
plan. Group object IDs churn under every reference, so grants are cheaper rebuilt than imported. A
Git-bound workspace cannot be adopted passively: Connect → InitializeConnection → commit-out can
overwrite the workspace, and `PreferRemote` makes that the default. A mismatched tfvars name creates
a **second workspace beside** the imported one, which is why the ID table comes first.

**Cost.** A convergence log per object class — live ID, state key, import command, post-import plan,
identity principal, item count, Git status, decision, owner, and the explicit not-imported list —
kept current until the estate is entirely one or the other. The estate is half-converged until then,
and two Terraform states claiming one workspace identity is the failure this order exists to avoid.
The two-capacity divergence from ADR 0004 is recorded as decision 3, not absorbed as import noise.

**Supersedes/amends.** None (new). Records ADR 0004's divergence explicitly. From #53.

---

## 12. Four agent roles

**Decision.** `architect`, `reviewer`, `bootstrap-guide`, `migration-assessor`, under one rule:
**agents plan, humans approve, the pipeline applies.**

| Role | May | Must return to a human |
| --- | --- | --- |
| architect | choose the pipeline row, read the spec, propose a pack change | any ADR change, name, SKU, approver, version bump |
| reviewer | read a plan, block a PR, demand a re-plan | every prod approval, any replacement, any group destroy |
| bootstrap-guide | run the human checklist, date a VERIFY | any tenant role, any credential, closing a VERIFY without output |
| migration-assessor | inventory, map, recommend a stop | deleting a source, passing a gate |

The prod plan is produced by the `PlanProd` stage's job, never by an agent; no agent approves its own
prod run. Briefs live in `agents/` — `AGENTS.md` for invariants, one file per role for the delta —
and are copied with frontmatter denying apply, skeleton writes and credentials. Each carries
`pack: <VERSION>`, and `check-pack.sh` fails on mismatch.

**Why.** The plan file *is* the approval. An agent that authored the configuration, generated the
plan and signed it has approved its own diff, and ADO already refuses a human approving a run they
queued; agents inherit that rule. Prod failures are the unrevivable ones, so the roles with the
least authority are the ones nearest the tenant.

**Cost.** Four documents to version and re-evaluate on every revision — scenario, forbidden-action
and stops-and-asks tests, recorded with transcript and date — and a revised brief voids its
evaluation until re-run. A failing brief blocks the session, not the pipeline. If the tenant cannot
enforce per-pipeline connection authorisation and self-approval-off on `fabric-prod`, the boundary is
unenforceable and the fallback is separate pipeline files with separate credentials.

**Supersedes/amends.** None. Roles are documents, revisable at the next pack version. From #51.

---

## 13. The pipeline applies; `assert_plan` gates every apply

**Decision.** The corporate machine reads this repository. Every change is applied by a DevOps agent
triggering the ADO YAML pipeline, which runs Terraform and `fabric-cicd`. **There is no local
`terraform apply`** and no credential on the corporate laptop. `assert_plan` sits between plan and
apply, fails closed, and blocks on any of: replacement of a workspace, capacity or domain; deletion
of a group, workspace or capacity; fewer than three role assignments in a workspace plan; a capacity
data source whose `Active` postcondition did not evaluate; a count that differs from
`checks/known-good/` when a baseline exists (the first run prints its counts for a human to record);
or an address outside the expected set for that root. The agent selects the pipeline and its
parameters, reads stage results, and stops on a named condition.

**Why.** There is no review loop and no report channel back: whatever protects production must live
inside the pack. The gate is mechanical, so agent judgement is not the control. Reducing the agent's
competence to selecting parameters and reading stages is what makes a weak model adequate.

**Cost.** A false positive in `assert_plan` blocks a legitimate change until the known-good counts
are updated in a separate, reviewed commit — so a deliberate replacement costs two commits, not one.
Read-only `terraform plan` on the laptop is **not permitted by default**; the pipeline's plan is the
plan, so one debugging cycle costs one pipeline run. Because nothing is carried back except what a
person physically takes, the pack must carry the symptom-to-fix index and a carryable report; we
cannot debug from a pasted log.

**Supersedes/amends.** Supersedes any run-book 03 step that assumes a local apply, and ADR 0002's
credential model narrows to federated credentials only. From #55.

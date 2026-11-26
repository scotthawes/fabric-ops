# 0003 — Open questions

Pack: 2026-11-26.1 · illustrative, not runnable from fabric-ops (ADR 0001)

Eleven tenant facts this design assumes but has not verified. Every row is **VERIFY** on 2026-11-26 and
stays open until someone produces output. None can be closed from `fabric-ops`: the tracker holds the
question, not the answer, and a plausible answer is not an output.

A row closes in the corporate repo's verification log with four things: the command or portal path
run, its output (redacted to placeholders), the date, and the name of the person who ran it. The
`bootstrap-guide` agent dates a row only against output; closing one without it is forbidden
(decision 12).

The decision each row blocks is named so a reader can see what changes when it is answered. A row
marked **sidestepped** has a design that does not depend on the answer — that is different from
answered.

| ID | Question | Why it blocks | How to check | Owner | State |
| --- | --- | --- | --- | --- | --- |
| OQ-01 | Does `sp-fabric-admin` need a Fabric licence (Free, Pro or PPU), and can a service principal hold one? | If a licence is required and an SP cannot hold one, decision 4's Terraform-created domain path is dead and every domain becomes a human step before first run. | Create a throwaway SP, get an app-only token, call `GET /v1/admin/workspaces`; check the licence column for the SP in the M365 admin centre. | Fabric administrator | VERIFY · 2026-11-26 |
| OQ-02 | Can the admin SP hold capacity **Contributor**, or is it only reachable through `administration_members`? | ADR 0004's design grants the SP Contributor to assign workspaces. If an SP cannot hold it, workspace assignment fails — unless the capacity admin list is used instead. | Read `azurerm_fabric_capacity.administration_members`; add the SP to a sandbox capacity's admin list through the portal and confirm Terraform accepts it. | Azure subscription Owner | VERIFY · 2026-11-26 — **sidestepped** by `administration_members`; the answer only decides which mechanism the platform root writes. |
| OQ-03 | What does a scheduled refresh do when its capacity is paused — fail, queue, or run at resume? | Decision 3 pauses nonprod manually and refuses a schedule until this is answered. If refreshes queue, a resume window runs a backlog against an F2 and throttles. | Pause a nonprod capacity with one scheduled refresh, observe across two windows, record item state and refresh history; confirm against Microsoft Learn's pause semantics. | Platform owner | VERIFY · 2026-11-26 |
| OQ-04 | Does an F SKU reservation or committed capacity keep billing while the capacity is paused? | Pause is the nonprod cost control. If the reservation bills regardless, pause buys throttling avoidance only and the saving in decision 3 is overstated. | Cost Management or a billing export over a paused day for the sandbox subscription; check the reservation's scope and unused-instance line. | Azure subscription Owner with finance | VERIFY · 2026-11-26 |
| OQ-05 | What overage setting does a capacity created by `azurerm_fabric_capacity` get, and can the provider express it? | Decision 3 requires overage off on nonprod. If the default is on and only `azapi` at `2026-09-01-preview` can change it, every nonprod capacity bills at roughly 3× until the patch applies. | Create a throwaway F2 in a sandbox, read the ARM resource at `2026-09-01-preview`, compare with the portal's overage setting. | Platform engineer | VERIFY · 2026-11-26 |
| OQ-06 | Can a service principal hold **Fabric administrator** at all? | Decision 4's primary path, and all three provider domain resources, assume it. The role test must run before the layout is fixed. | In the M365 admin centre or Fabric admin portal, search the role's assignable principals for the SP; if absent, that is the answer. | Fabric administrator | VERIFY · 2026-11-26 |
| OQ-07 | May a service principal create Azure DevOps repositories with the `sc-fabric-admin` connection? | Decision 6 needs N repositories. If not, repos are human-created from a template and the pipeline only binds — a run-book step per domain, not a YAML entry. | Call `POST /{org}/{project}/_apis/git/repositories` with the SP token and record the status; confirm the connection's repo permissions. | ADO Project Administrator | VERIFY · 2026-11-26 |
| OQ-08 | Are Graph `Group.Create` and `User.Read.All` granted and admin-consented for the tenant, and can this SP receive them? | Group creation moved into the workspaces root. A delayed consent lets Platform succeed and then fails nonprod at group create with `403 Authorization_RequestDenied`. | Entra → enterprise application → API permissions for the SP; then attempt one group create with an app-only token. | Privileged Role Administrator | VERIFY · 2026-11-26 |
| OQ-09 | Does the subscription have 64 CU of Fabric quota available in the chosen region? | Platform stage fails at capacity create otherwise, and 64 CU is a per-region subscription limit; F2 needs 2 CU from the same pool. | `az quota list` for `Microsoft.Fabric` in the region, or read the error from a deliberately oversized create in a sandbox. | Azure subscription Owner | VERIFY · 2026-11-26 |
| OQ-10 | Do prod and nonprod viewers hold Pro/PPU or a Free licence? | F64 is bought only to let a Free viewer read: if every viewer already has Pro, F64 buys nothing and the measured peak sets the SKU instead. | Export the Viewer group membership; check licences in the M365 admin centre; record counts by SKU, not names. | Platform owner with the identity team | VERIFY · 2026-11-26 |
| OQ-11 | What is the prod capacity's region and disaster-recovery posture? | Region is fixed at creation, migration is blocked while paused, and changing it later means recreating the capacity and detaching every workspace. | The business owner states RTO and RPO; check Fabric's supported region pairs and capacity failover behaviour against that statement. | Corporate platform owner with business continuity | VERIFY · 2026-11-26 |

## What the table does not cover

- **Prices.** Not recorded anywhere in the pack. The capacity decision is a shape (F2/F64, overage,
  pause), not a quote; a price belongs to the corporate subscription's agreement.
- **Measured peak CU.** Needed to confirm F64 is the right prod SKU and that F2 survives nonprod.
  It cannot be known before the estate runs, so it is a post-first-run review, not a bootstrap gate.
- **Whether the tenant enforces per-pipeline connection authorisation and self-approval-off.** If it
  does not, decision 12's boundary is unenforceable; the fallback is separate pipeline files with
  separate credentials.
- **What a domain delete does to workspace assignments.** Recorded as unestablished in #42. It
  matters only if a domain is ever destroyed, which decision 11 forbids.

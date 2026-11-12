# 0004 — One Fabric capacity shared by dev, test and prod

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott
- **Evidence:** [`capacity-provisioning-and-cost-control.md`](../research/capacity-provisioning-and-cost-control.md)
- **Overrides:** the research recommendation of one capacity per environment

## Context

Three environments need somewhere to run. Separate F SKUs isolate blast radius but multiply
the baseline spend; a single SKU is the cheapest arrangement and the easiest to reason about
while the estate is small. The counter-argument is that Fabric throttles by *capacity*, not by
workspace, so a runaway notebook in dev competes with a production refresh for the same
capacity units.

## Decision

One F SKU, created by Terraform as an Azure resource, with three workspace sets (`dev`,
`test`, `prod`) assigned to it. Capacity Admin stays with a named human owner; the admin
service principal holds capacity **Contributor** so it can assign workspaces.

## Consequences

- **Scheduled pause is largely unavailable.** Pausing stops everything on the capacity,
  including production. The cost control that motivated owning the pause/resume path only
  applies in windows where production may be down — so in practice the saving is smaller than
  the plan assumed, and it must not be automated on a timer that ignores production.
- **Applying Terraform against a paused capacity is not merely untidy.** The provider warns that
  it can remove workspace items from Terraform state, so "never apply while paused" is mechanical:
  resume first, and make the data source assert `Active` before anything else runs.
- Pause is an ARM action, not a Terraform property, so it sits outside state. Resume must be the
  first step of any deployment after a maintenance window, and Fabric Terraform must never run
  against a paused capacity (`fabric_workspace` will report drift).
- Capacity overage is enabled by default at a 25% threshold and billed at 3× the pay-as-you-go
  rate. AzureRM is pinned to API `2023-11-01` and cannot express the setting — but the ARM spec at
  `2026-09-01-preview` models it as `CapacityOverageProperties`, so it is automatable through
  `azapi_resource` even though it is not in `terraform plan`. See
  [`arm-fabric-operations.md`](../reference/arm-fabric-operations.md).
- There are no Azure Monitor metrics for `Microsoft.Fabric/capacities`, so alerting has to hang
  off the Capacity Metrics app and Real-Time hub events rather than a metric alert. The metrics app
  itself supports no alerts, so every alert is something to build, not configure — and an event
  listener whose owner loses permission pauses and holds events for 24 hours, which looks identical
  to a quiet estate.
- **The SKU is also a licensing decision, at F64.** At **F64 and above** — or on a P capacity —
  a user with the workspace **Viewer** role can read Power BI content on a Fabric (Free) licence.
  Below F64, every viewer still needs Pro or PPU. So the cheapest SKU that "runs the workloads" can
  raise the per-user cost of the whole estate, and sizing down to save capacity spend can re-impose
  Pro on everyone.
- **Our access model has to respect that cliff.** Groups carry `Contributor` by default, and any role
  other than Viewer requires Pro/PPU even on F64+. Granting Contributor to "help during launch" is a
  licensing decision as well as an access one — see
  [`powerbi-coexistence.md`](../research/powerbi-coexistence.md).
- Throttling is shared: sustained dev load degrades interactive queries and refresh in
  production. Mitigations to evaluate in the work tenant — surge protection, alerting on
  capacity utilisation thresholds, and moving heavy scheduled work outside business hours.
- Sizing is driven by the peak of the *largest* environment, so dev and test ride free but
  cannot be tuned or throttled independently.
- A capacity-level incident is a three-environment outage. The pipeline must treat a paused or
  throttled capacity as a normal failure mode with a clear error, not an unexpected one.
- **This is a cheap decision to reverse:** creating a second SKU and reassigning a workspace is
  an afternoon's work. Revisit it if production is throttled by non-production traffic twice,
  or when a single workload needs more than the shared SKU can smooth.

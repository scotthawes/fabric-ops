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
- Sizing is driven by the peak of the *largest* environment, so dev and test ride free but
  cannot be tuned or throttled independently.
- Throttling is shared: sustained dev load degrades interactive queries and refresh in
  production. Mitigations to evaluate in the work tenant — surge protection, alerting on
  capacity utilisation thresholds, and moving heavy scheduled work outside business hours.
- A capacity-level incident is a three-environment outage. The pipeline must treat a paused or
  throttled capacity as a normal failure mode with a clear error, not an unexpected one.
- **This is a cheap decision to reverse:** creating a second SKU and reassigning a workspace is
  an afternoon's work. Revisit it if production is throttled by non-production traffic twice,
  or when a single workload needs more than the shared SKU can smooth.

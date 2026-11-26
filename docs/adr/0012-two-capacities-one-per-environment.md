# 0012 — Two capacities, one per environment

- **Status:** accepted
- **Date:** 2026-11-26
- **Deciders:** Scott
- **Supersedes:** [0004](0004-one-shared-capacity.md) — one capacity shared by every environment
- **Evidence:** wayfinder map [#41](https://github.com/scotthawes/fabric-ops/issues/41),
  [`capacity-provisioning-and-cost-control.md`](../research/capacity-provisioning-and-cost-control.md),
  [`corporate-pack/spec/0001-decisions.md`](../reference/corporate-pack/spec/0001-decisions.md)

## Context

The corporate design settled on **two environments**, `nonprod` and `prod`, with one project per
domain and two workspaces per domain. That removes the assumption behind ADR 0004: a single capacity
was cheap because dev and test rode free, but it also meant a runaway notebook in nonprod competed
with a production refresh for the same capacity units, and pausing for cost control stopped
production too.

Two facts point the other way and are recorded rather than dismissed. F64 is the licence floor at
which a **Viewer** can read Power BI content on a Fabric (Free) licence; below it every viewer needs
Pro or PPU. And F2 is the smallest SKU, so it cannot host an Eventhouse path — ADR 0009's
event-sourced monitoring store would need a third capacity if it is adopted.

## Decision

- **`fabric-capacity-nonprod` — F2**, and **`fabric-capacity-prod` — F64**, in the same region, as
  two applications of one platform root with a state key each (`platform/nonprod.tfstate`,
  `platform/prod.tfstate`).
- **Overage** is off on nonprod and capped below one-third of daily CU hours on prod, set through
  `azapi` because AzureRM cannot express it.
- **Pause** is manual on nonprod and unavailable on prod, until the open question "what does a
  scheduled refresh do when its capacity is paused" (#19) is answered. No timer.
- The admin service principal is a **capacity administrator** through `administration_members`, not
  a Contributor. The provider documents the member as an Entra user or service principal, which
  sidesteps the unanswered "can an SP hold capacity Contributor" (#15) at the cost of a broader
  grant.

## Consequences

- **Isolation is bought, not free.** Two SKUs, two bills, two pause policies and two cost reviews.
  Nonprod load can no longer throttle production; production pause can no longer be used as a saving.
- **The F64 cliff applies only where it is needed.** Prod viewers can read on a Free licence; nonprod
  viewers are assumed to hold Pro or PPU already.
- **The platform root runs twice.** A destroy of F2 cannot reach F64; a change to one capacity is two
  applies, and the second must not assume the first succeeded.
- **ADR 0009's monitoring store is out of this decision.** If adopted, it is a third F4 capacity with
  its own state, not an argument for a shared one.
- **Unverified in a tenant:** measured peak CU, viewer licence holdings, whether the subscription has
  the 64-CU quota F64 requires, and whether a SKU resize is in place. These are run-book checks, not
  assumptions.

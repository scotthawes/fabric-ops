# 0009 — Observability is event-sourced, and monitoring gets its own capacity

- **Status:** proposed — the event-sourced architecture follows from the research; the second SKU is a
  spend decision for the owner, not the agent
- **Date:** 2026-11-12
- **Deciders:** Scott
- **Evidence:** [`monitoring-and-alerting-surface.md`](../research/monitoring-and-alerting-surface.md),
  [`operating-model-what-prior-art-supports-spec-0002.md`](../research/operating-model-what-prior-art-supports-spec-0002.md),
  [Configure workspace monitoring](https://learn.microsoft.com/en-us/fabric/fundamentals/enable-workspace-monitoring)
- **Amends:** [ADR 0004](0004-one-shared-capacity.md), which gains one named exception

## Context

[Spec 0002](../specs/0002-platform-operations.md) schedules a weekly capacity review that reads
utilisation, throttling and overage. The survey of fifteen open-source pipelines found **no prior art**
for it — nobody in the sample operates an estate, they ship content into one — and the research pack
already establishes that the obvious data source is closed:

- There is **no Azure Monitor metric namespace** for `Microsoft.Fabric`, so no metric alert, no action
  group.
- The **Capacity Metrics app** shows the right measures and "doesn't support alerts or notifications";
  its semantic model "is only supported for use by the reports provided in the app", so it is not a data
  source to build on. Retention is a 14-day compute and 30-day storage view.
- The only machine-readable path is **Real-Time hub capacity events** — `Capacity.Summary` every 30
  seconds, `Capacity.State` on change — which are best-effort, duplicated, and never backfilled.

So the review needs a store it does not currently have. Two facts constrain where that store lives.
First, workspace monitoring's KQL database defaults to **30 days** retention, configurable under
`Manage > Data policies` — less than a quarterly review cadence, so the default is wrong for this
purpose before anything else is decided. Second, and decisively, Microsoft's own recommended
architecture is explicit: *"Isolate a workspace on its own Capacity to host a central monitoring
Eventhouse… It also shields production workloads from excessive capacity usage by monitoring
workloads."*

That contradicts [ADR 0004](0004-one-shared-capacity.md), whose whole point is one shared SKU.

The alternatives were:

1. **No store — a human reads the app weekly.** Cheapest, and what the spec silently describes today.
   Rejected: history ends at 14 days, nothing is automated, and the review cannot answer a quarterly
   question at all.
2. **Eventhouse inside the shared capacity.** Cheap, and the Eventstream and Activator are already
   there. Rejected as the default: ingestion and Activator evaluation are themselves capacity
   workloads, and Activator alerts "respect the capacity state and can be throttled" — so the alerting
   path degrades exactly when the capacity is in trouble. Monitoring that fails under load is not
   monitoring.
3. **Eventhouse on its own capacity.** Microsoft's recommendation; isolates both directions — the
   estate cannot throttle the monitoring, and monitoring cannot burn the production SKU. Chosen.
4. **Ship events out via the Eventstream custom endpoint** to Event Hubs, Kafka or an Azure store.
   Rejected: it adds a second estate outside Fabric, the endpoint is preview and "can only be enabled
   at creation time", and it buys nothing the in-Fabric store does not already do.

## Decision

**Capacity observability is event-sourced**, and it is the one documented exception to ADR 0004's
single-capacity rule.

- `Capacity.Summary` and `Capacity.State` feed an **Eventstream**; the Eventstream writes to an
  **Eventhouse** for history and to **Activator** for alerting. The weekly review queries the
  Eventhouse; nobody reads the metrics app on a schedule.
- The Eventhouse lives in a **central monitoring workspace on its own F capacity**, the smallest SKU
  that can host an Eventstream and its ingestion — not on the dev/test/prod capacity.

## Consequences

- **A second SKU is now part of the design and its cost is real.** It is small and it can be paused
  whenever the estate is down, because nothing needs watching then — unlike the shared capacity,
  which holds production and therefore usually cannot be paused. This is a spend decision the pack can
  state but not make; if it is refused, take alternative 1 openly and label the operation **manual**,
  rather than letting a scheduled job imply automation that does not exist.
- **ADR 0004's revisit trigger gains a sibling:** production throttled by non-production traffic twice
  *or* an incident in which monitoring data or alerts lagged the capacity event. The second is the
  cheaper signal and the one this ADR exists to prevent.
- **Terraform gains one resource in the capacity root** ([ADR 0007](0007-terraform-layout-and-pinning.md)):
  a second `azurerm_fabric_capacity`, same subscription scope, same overage handling. It is a separate
  resource in the same root, not a separate root.
- **Retention must be set deliberately and outlive the slowest review.** The 30-day default cannot
  serve a quarterly review; set retention to at least a quarter plus a margin and say so where the
  review is defined, because the failure is silent — old windows simply disappear.
- **Topology is fixed at creation.** A Monitoring Item's Eventhouse destination "can't be changed after
  you configure workspace monitoring", and the sending workspace must be in the same region. Choose the
  central workspace, region and SKU before enabling collection anywhere.
- **One KQL database per sending workspace** lands in the central workspace, and each counts toward its
  1,000-item limit — so the central workspace is a scaling surface, not just a store.
- **Alerting is still not guaranteed.** Event delivery is best effort with duplicates and no backfill;
  a listener whose owner loses permission pauses and holds events for up to 24 hours, which looks like
  a calm estate. Every rule must dedupe on `windowStartTime, windowEndTime, capacityId`, and absence of
  events must be treated as unknown rather than healthy.
- **The metrics app keeps one job:** diagnosis, by a human, during an incident. It is no longer the
  basis of any scheduled operation.

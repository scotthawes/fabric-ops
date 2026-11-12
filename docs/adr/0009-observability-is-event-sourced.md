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
First, retention and caching are the store's main levers and both must be set explicitly: a KQL
database accepts **1 to 36,500 days** and defaults to **3,650**, and the caching default is the same,
which means ten years of hot cache at premium rates unless someone says otherwise — the failure here
is cost, not lost history. Second, and decisively, Microsoft's own recommended architecture is
explicit: *"Isolate a workspace on its own Capacity to host a central monitoring
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
- The Eventhouse lives in a **central monitoring workspace on its own F capacity — F4, not F2** — not on
  the dev/test/prod capacity. The floor is compute, not ingestion: an Eventhouse at its 2-CU default
  minimum plus an active Eventstream plus a listener is roughly **3 CU-hours per hour**, which is more
  than an F2 has and most of an F4.

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
- **Set retention long and caching short, deliberately.** Retention must outlive the slowest review —
  a quarter plus margin is trivial against a 3,650-day default — but the default that actually bites is
  **caching**, which is also 3,650 days and raises storage cost. Both travel inside the KQL database's
  deployable definition (`oneLakeStandardStoragePeriod`, `oneLakeCachingPeriod`), so neither is a
  portal chore; set them where the store is defined, not where the review is written.
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

## Correction 2026-11-12 — the retention rationale was wrong, and the SKU was too small

Checked against [`real-time-intelligence-what-can-be-retained-and-deployed.md`](../research/real-time-intelligence-what-can-be-retained-and-deployed.md).
The decision stands; two of its reasons did not.

- **The 30-day default belongs to the Monitoring Item, not to a KQL database.** A KQL database
  accepts **1 to 36,500 days** and defaults to **3,650**; the 30-day figure is the product-chosen
  default for the read-only database workspace monitoring creates for itself. A quarter of retention
  needs no rescue — it is far below the default.
- **The silent failure runs the other way.** The draft warned that "old windows simply disappear";
  with defaults left alone they never disappear, and the **caching** policy — also 3,650 days by
  default — keeps ten years of data in premium hot cache. The risk is spend, not loss.
- **"The smallest SKU that can host an Eventstream" is F4, not F2.** The Eventhouse's 2-CU default
  minimum plus an active Eventstream plus a listener is about 3 CU-hours per hour. An F2 is entirely
  consumed by the baseline before anything is stored.
- **Eventhouse over a Lakehouse table, on evidence rather than preference.** Retention and caching
  travel inside the KQL database's deployable definition, and tables and functions travel in its
  schema; a lakehouse table has no TTL (expiry becomes a `DELETE`/`VACUUM` job to own and to watch)
  and "schemas are not deployed" to a lakehouse. If the second SKU is refused, a Lakehouse is the
  cheaper degradation — roughly 1,460 CU-hours a month less — but it is a worse store, not an equal one.

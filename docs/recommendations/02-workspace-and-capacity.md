# 02 — Workspace and capacity model

**The decisions this supports:** [ADR 0004](../adr/0004-one-shared-capacity.md),
[ADR 0006](../adr/0006-access-through-entra-groups.md).
**Evidence:** [capacity note](../research/capacity-provisioning-and-cost-control.md).

## The shape

One F SKU, three workspace sets.

```
fabric-<domain>-<project>-dev   ─┐
fabric-<domain>-<project>-test  ─┼─►  one Fabric capacity (F SKU, one region)
fabric-<domain>-<project>-prod  ─┘
```

The capacity is an Azure resource — `Microsoft.Fabric/capacities` — created by `azurerm_fabric_capacity`
in the same subscription as the rest of the estate. The `microsoft/fabric` provider cannot create a
capacity; it only consumes one.

## What sharing one SKU actually means

- **Everyone shares one throttling budget.** Throttling is applied at capacity level, so a dev
  notebook consumes smoothed CUs against the 10-minute, 60-minute and 24-hour limits that prod
  users are also living inside. Dev is not throttled *instead of* prod.
- **Sizing is set by the largest environment's peak,** not by the sum of three comfortable ones.
  Prod should sit comfortably under 100% of the SKU on its own; dev and test then ride in the
  remaining headroom and cannot be sized independently.
- **Interactive work is delayed first, background work is rejected last.** Interactive operations
  smooth over a minimum of five minutes (up to 64); background — pipelines, Spark, and *all*
  warehouse operations — smooths over 24 hours. A long-running dev notebook therefore hurts
  prod's background jobs more than its clicks.
- **One capacity incident is a three-environment outage.** Pause, throttle, or a bad resize and
  everything on the SKU goes with it.

## Cost control is three levers, and only one is in Terraform

| Lever | Where | Note |
| --- | --- | --- |
| SKU size | Terraform (`azurerm_fabric_capacity`) | The only one in `terraform plan` |
| Capacity overage | Portal / API | **On by default at a 25% threshold, billed at 3× pay-as-you-go.** Not in AzureRM — API `2023-11-01` has no `overage` block |
| Surge protection | Portal | Rejects new background operations before deep throttling; never stops in-progress jobs |

The overage default is the one to fix on day one. Keep the threshold below one-third of the
capacity's daily CU hours; above that, overage costs as much as a larger SKU would have, without
buying the headroom.

## Pause is not a Terraform property

Pausing is an ARM action (`POST …/capacities/{name}/suspend`), exposed as
`az fabric capacity suspend`. It stops future compute billing, immediately bills the smoothed
usage already accrued, and makes the content unavailable until resumed.

With one shared capacity, **there is no safe scheduled pause**: the only pause windows are ones
where production may be down. Resume is therefore the first step of any deployment that might
follow a maintenance window, and Fabric Terraform must never run against a paused capacity —
`fabric_workspace` has a `skip_capacity_state_validation` flag precisely because a paused
capacity causes drift and lost state.

## Administration boundaries

- **Capacity administrator** (documented for users): assign workspaces, manage capacity
  permissions, manage workloads.
- **Capacity contributor** (grantable to "specific users or security groups"): assign workspaces
  to the capacity, but not change capacity settings or delete it. This is the lever for
  `sp-fabric-admin`.
- **Assigning a workspace** needs capacity Contributor **and** workspace Admin. Contributor on
  the workspace is not enough, and the error does not say so.
- Unverified: whether a service principal can hold capacity **Contributor** directly. Docs say
  Contributor is grantable to security groups; test with the group before assuming.

## Monitoring, because there are no Azure Monitor metrics

The Azure Monitor supported-metrics index has no `Microsoft.Fabric` entry as of 2026-11-03, and the
**Capacity Metrics app does not support alerts or notifications at all** — not a threshold, not a
subscription. Alerting has to be built on Real-Time hub events, and every one of these five is work:

| Alert | Source | Condition |
| --- | --- | --- |
| Capacity overloaded | `Microsoft.Fabric.Capacity.State` | state changes to `Overloaded` |
| Interactive delays | `Capacity.Summary` | `interactiveDelayThresholdPercentage` > 80 |
| Background rejections | `Capacity.Summary` | `backgroundRejectionThresholdPercentage` > 80 |
| Unexpected pause | `Capacity.State` | state changes to `Suspended` (or back to `Active`) |
| Job or refresh failure | `ItemJobEventLogs`, or the free schedule-failure emails | a run reports `Failed` |

Three traps sit under that table:

- **Silence is not health.** If the event listener's owner loses subscribe permission, the listener
  enters a paused state and holds events for 24 hours — alerting stops while everything looks calm.
  Give the listener an owner and monitor the listener.
- **A failing scheduler disables itself** after roughly ten consecutive failures, and schedules expire
  after 90 days without a login. Neither raises anything beyond the per-run email, so a schedule can
  simply stop being a schedule.
- **Deployment failures emit no Fabric event.** Only `DeployAlmPipeline` appears in the audit log, so
  that alert belongs in Azure DevOps, not in Fabric.

The Capacity Metrics app remains the place to *look* — Compute: Utilization, Throttling, Overages;
Health: at-risk views; 30-second windows with 10–15 minutes latency. It is a diagnostic surface, not
an alerting one.

## When to split the capacity
This is a cheap, reversible decision: create a second SKU and reassign a workspace. Split when
any of these happens:

1. Production is measurably throttled by non-production traffic, twice.
2. A single workload needs more headroom than the shared SKU can smooth.
3. You need a scheduled pause, which is only safe once production is elsewhere.
4. A prod incident is traceable to a dev deployment coinciding with it.

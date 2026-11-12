# With no Azure Monitor metrics for the capacity, what can actually be monitored and alerted on in Fabric?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's operational runbook and whatever `docs/specs/` says about alerting

## Short answer

Two machine-readable paths exist and neither is Azure Monitor. The **Capacity Metrics app** shows utilisation, throttling and
overage but is read-only: it "doesn't support alerts or notifications". The **Real-Time hub capacity events**
(`Microsoft.Fabric.Capacity.Summary` every 30 s, `Microsoft.Fabric.Capacity.State` on change) feed Eventstream for history and
Activator for alerting. Everything else — Monitor hub, refresh history, job scheduler, audit log — is a UI, a per-item email or
an API you poll. An operator reads the app to diagnose and builds rules on the events to alert; nothing fires on throttling out
of the box.

## Detail

### 1. The Capacity Metrics app

The app ships a **default report** (GA, opens by default) and a **preview report** (preview). Default pages: **Health**,
**Compute**, **Storage**, **Timepoint**, **Timepoint summary**, **Timepoint item detail**, **On-demand Compute for Spark**,
**Plan capacity**, **Monitor paused capacity**, **Calculations**. (metrics app, 2026-11-03)

Measures, exactly as named. Health cards: `# Capacities`, `Avg. utilization %`, `# Throttled capacities`, `# Interactive
rejected capacities`, `# Background rejected capacities`. Health states: `Healthy`, `Suspended`, `At Risk of Throttling`, `At
Risk of Overage Billing`, `Overage Billing Active`, `Throttling`, `At Risk of Interactive Rejection`, `Interactive Rejection`,
`At Risk of Background Rejection`, `Background Rejection` — "at risk" means one 30-second window above **90%**, the rest above
**100%**. (health page, 2026-10-12)

Compute cards: `SKU`, `Average utilization %`, `Peak utilization %`; ribbon `CU`, `Duration`, `Operations`, `Users`; utilisation
series `Background %`, `Interactive %`, `Background nonbillable %`, `Interactive nonbillable %`, `Autoscale CU % Limit`, `CU %
Limit`. `Overage (Carryforward)` uses `Add %`, `Burndown %`, `Cumulative %`; `Overage (Billed)` uses `Rolling cumulative 24 hour
billed overage CU (hr)`, `Overage billing limit CU (hr)`, `Overage (Billed) CUs (s)` and is populated only when overage is
enabled. System events: `Time`, `State`, `State Change Reason`, the reason being one of `Created`, `ManuallyResumed`,
`NotOverloaded`, `Deleted`, `AllRejected`, `InteractiveDelay`, `InteractiveDelayAndSurgeProtectionActive`,
`InteractiveRejected`, `InteractiveRejectedAndSurgeProtectionActive`, `SurgeProtectionActive`, `ManuallyPaused`. (compute page,
2026-10-12)

Cadence: usage "becomes available within 10 to 15 minutes"; the `capacities`, `workspaces` and `items` dimensions refresh at "a
scheduled semantic model refresh at midnight (local time)". Retention: compute is a **14-day** view, storage **30 days**;
anything longer is **not documented — could not establish**, and the semantic model "is only supported for use by the reports
provided in the app", so it is not a data source to build on.

Access: installing needs **capacity admin** and "a Power BI license (Pro, Premium Per User, or a Power BI individual trial)";
Health shows "only the capacities for which you have admin access"; sharing needs capacity admin. (install, 2026-10-12)

### 2. Real-Time hub capacity events — the only machine-readable source

| Event type | Cadence |
| --- | --- |
| `Microsoft.Fabric.Capacity.Summary` | "every 30 seconds"; one line per 30-second window per active capacity, suppressed when all values are 0, not emitted while paused |
| `Microsoft.Fabric.Capacity.State` | on change only — created, overloaded, paused, resumed, deleted; scaling and renaming are not state changes |
| `Microsoft.Fabric.CapacityOperationEvents.Operation` | one row per operation that consumes CU, not aggregated |

(overview events, 2026-09-29; operation events, 2026-10-14)

`Summary` fields a threshold rule reads: `capacityId`, `capacityName`, `capacitySku`, `windowStartTime`, `windowEndTime`,
`baseCapacityUnits`, `capacityUnitMs`, `interactiveDelayThresholdPercentage`, `interactiveRejectionThresholdPercentage`,
`backgroundRejectionThresholdPercentage`, `overageTotalCapacityUnitMs`, `overageAddCapacityUnitMs`,
`overageBurndownCapacityUnitMs`, `utilizationBackground`, `utilizationInteractive`, `capacityUnitUtilizationBreakdown`. The
three `…ThresholdPercentage` fields are the smoothed percentages of the next 10 minutes, 1 hour and 24 hours. `State` fields:
`capacityId`, `capacityName`, `capacitySku`, `transitionTime`, `capacityState`, `stateChangeReason`, `activationId`.

Semantics trap: "ManuallyResumed is treated as NotOverloaded", and a blank state table for an active capacity means
`NotOverloaded` — absence of events is not evidence of health. Delivery is **best effort, no backfill**: "events can either fail
to send, or duplicates might be received"; dedupe with `summarize take_any(*) by windowStartTime, windowEndTime, capacityId`.
Consuming means **Create eventstream** (to an eventhouse, or onward) or **Set alert** (straight to Activator); a REST
subscription needs **capacity administrator** on the source capacity, and the consumer needs workspace Contributor.

### 3. Activator as the alerting mechanism

**Set capacity alert** offers three templates: **Alert when capacity usage % exceeds a threshold** (tracks
`interactiveDelayThresholdPercentage`, default `80`), **Alert when a capacity metric exceeds a threshold** (any numeric field),
and **Alert when a capacity changes state** (`Any state change`, `Overloaded`, `Active`, `Suspended`, `Deleted`). Each pre-fills
a **numeric change condition grouped by `capacityId`**, so you "get a single alert when the measure crosses the threshold,
instead of a continuous stream of alerts". (templates, 2026-09-10)

Conditions also include `BECOMES`, `INCREASES`, `DECREASES`, `EXIT RANGE` and absence of events (heartbeat), state tracked per
object and firing on entry into a state. (introduction, 2026-10-13) Actions: **Send email**, **Teams → Message to individuals /
Group chat message / Channel post**, run a Fabric item, or **Create custom action**, which is a Power Automate flow. (rule
actions, 2026-05-12) There is no native webhook action: webhooks go through Power Automate, or out of Fabric via an Eventstream
**Custom endpoint** (Event Hubs, Kafka, AMQP).

Limits that change design: 10,000 events per second per rule and the rule **stops** above it; 500 rules per Activator item;
recipients must be internal — "Activator doesn't allow email notifications to be sent to either external email addresses or
guest email addresses"; and "Creating alerts from the Fabric or Power BI Capacity Metrics app isn't supported". (limitations,
2026-10-13)

**Unresolved conflict:** the limitations page says "Teams channels aren't currently supported", while the actions page documents
**Channel post**. I could not establish which is current; do not promise channel delivery without testing.

It is the only threshold engine on capacity data, but it is not a metric alert: no queryable alert history or alert-status page,
alerting does not survive an unhealthy capacity ("Power BI reports and Activator alerts that use the monitoring database respect
the capacity state and can be throttled"), and evaluation is billed — `0.000011111 CU Hour` per event operation per 64-KB chunk
plus an **event listener** at `0.0222 CU Hour` per hour while a consumer exists. (consumption, 2026-05-21)

### 4. Item-level monitoring

- **Monitor hub** — preview, five pages: Job runs, Applications, Capacity and cost, Agents, Alerts. "Any Fabric user can open
  the Monitor hub, but you only see activities for Fabric items you have permission to view", and Job runs summarises "the last
  five runs for each item". List retention is **not documented — could not establish**. (monitor hub, 2026-09-29; job runs,
  2026-10-06)
- **Job scheduler** — failure notifications are email only, set per item under **Failure notifications**, applying to all of
  that item's schedules and to scheduled runs only. A repeatedly failing scheduler is **auto-disabled** ("typically set to 10
  consecutive failed runs") and must be restarted by hand, and schedules **expire if a user doesn't log in to Fabric for 90
  consecutive days**. (job scheduler, 2026-10-30)
- **Refresh history** — per semantic model, automatic retries as separate attempts, Scheduled and OneDrive tabs, and a
  **Semantic Model Refresh Detail** page from the Monitor hub with execution metrics. Failures email the owner plus **Email
  these contacts when the refresh fails**; on-demand and programmatic refreshes send nothing. API: **Get Refresh History** and
  **Get Refresh Execution Details**. (refresh data, 2026-10-01)
- **Audit log** — now in Microsoft Purview; access needs the **Audit Logs** role in Exchange Online, not Fabric administrator.
  The Power BI **ActivityEvents** API pages one day per request; the deployment-pipeline operation is `DeployAlmPipeline`
  ("Deployed to a pipeline stage"). (track user activities, 2026-07-01; auditing, 2026-02-17; operation list, 2026-11-10)
- **Admin and item APIs** — `GET https://api.fabric.microsoft.com/v1/admin/items` returns `capacityId`, `workspaceId` and
  `creatorPrincipal` per item but is **Preview**, needs Fabric administrator or a service principal with `Tenant.Read.All`. Job
  runs are readable per instance (`get-item-job-instance`, `cancel-item-job-instance`) beside `list-item-schedules`; there is
  **no documented endpoint that enumerates all runs**, so a report means per-instance polling or the workspace-monitoring logs.
  (admin items, 2026-11-11)

### 5. Workspace monitoring

Each workspace gets one **Monitoring Item** holding an Eventhouse with a read-only KQL database, an Eventstream and an
Activator. Data goes to that Eventhouse or another Monitoring Item's — same region, and "You can't change the destination after
you configure workspace monitoring". Collection is off until enabled and "doesn't backfill earlier activity". (overview,
2026-11-10; configure, 2026-09-29)

Captured: pipeline activity run logs, Copy job and Dataflow Gen2 logs, Warehouse query execution logs, mirrored database
execution logs, semantic model operation logs, Eventhouse query, ingestion and capacity-throttling logs, Eventstream node status
and error metrics, and **job events** in `ItemJobEventLogs` — `JobStatus`, `JobType`, `JobInvokeType`, `DurationMs`,
`JobStartTime`, `JobEndTime` — the table that makes a job-failure rule possible. (job event logs, 2026-11-10)

Prerequisites: workspace on Fabric or Premium capacity; tenant settings **Workspace admins can turn on monitoring for their
workspaces** and **Users can create Fabric items**; workspace admin. Default retention **30 days**, changeable under `Manage >
Data policies`; the database is read-only, and Contributors and above can query it. Cost is capacity consumption for Eventhouse,
Eventstream and queries — hence the recommendation to host a central monitoring Eventhouse "on its own Capacity" so monitoring
survives throttling. (configure)

GA versus preview: the Monitoring Item experience carries no preview label as of 2026-11-10, with the **legacy** Eventhouse path
kept alongside it; the Eventstream **custom endpoint** to Event Hubs, Kafka or AMQP is preview ("Through the preview period,
this setting can only be enabled at creation time"). There is **no Log Analytics or storage sink** for workspace logs: storage
means Eventhouse plus OneLake availability or shortcuts. A Log Analytics destination could not be established.

### 6. What cannot be alerted on

- **No Azure Monitor metric or metric alert.** The supported-metrics index has no `Microsoft.Fabric` entry (2026-11-03), so no
  metric alert, no action group, no auto-scale hook.
- **Nothing fires when a capacity is throttled** unless you build it. The app "doesn't support alerts or notifications"; the
  State event exists, but no rule is created for you.
- **No central failed-refresh alert.** Default is an email to the semantic model owner plus whatever addresses someone typed
  into that model — none at all for on-demand or API-triggered refreshes; nothing warns when a scheduler auto-disables itself.
- **Nothing for deployment failures.** A failed deployment-pipeline step appears as `DeployAlmPipeline` in the audit log and as
  a failure in the Azure DevOps pipeline that called it; Fabric emits no event.
- **Silent consumer failure.** If the listener's owner loses subscribe permission the listener "enters a paused state", holding
  events for "up to 24 hours" — an alerting gap that looks like calm.

### 7. A practical minimal alert set

| # | Alert | Source | Condition | What a false positive looks like |
| --- | --- | --- | --- | --- |
| 1 | Capacity overloaded | `Microsoft.Fabric.Capacity.State` | state changes to `Overloaded` (template **Alert when a capacity changes state**) | one 30-second window over 100% nobody noticed; a pause pushing all smoothed usage into one window ("up to 288,000% of normal") |
| 2 | Interactive delay approaching | `Microsoft.Fabric.Capacity.Summary` | `interactiveDelayThresholdPercentage` > `80` | one heavy interactive query; with overage enabled the capacity is billed, not throttled |
| 3 | Background rejection approaching | `Microsoft.Fabric.Capacity.Summary` | `backgroundRejectionThresholdPercentage` > `80` | an overnight batch that burns down by morning; the 24-hour window decays slowly, so the alert outlives the incident |
| 4 | Capacity paused or resumed | `Microsoft.Fabric.Capacity.State` | `capacityState` → `Suspended` or `Active`, or `stateChangeReason` = `ManuallyPaused` | your own scheduled pause; the resume re-firing the rule |
| 5 | Scheduled job or refresh failed | job events / `ItemJobEventLogs`, or free **Schedule failure emails** | status `Failed` for a named pipeline or notebook | a retry that succeeded seconds later; a job expected to fail in dev; the same job repeating after auto-disable |

If cost matters more than latency, swap #3 for `overageTotalCapacityUnitMs` rising without matching
`overageBurndownCapacityUnitMs` — carryforward that is not paying down becomes a 3× rate bill.

## What this settles

Capacity is monitored in two places and neither is Azure Monitor: the **metrics app** to diagnose, and **Real-Time hub events**
as the signal path — Eventstream into an eventhouse for history, Activator for alerting. Items are monitored through **workspace
monitoring** (`ItemJobEventLogs` and workload logs) for queryable detail, the Monitor hub and job scheduler for presence, and
the audit log for who changed what. A team must therefore **build** an Activator rule set per capacity (none ship enabled), an
eventhouse sink with the dedupe query, a pause/heartbeat rule treating a missing `Summary` as ambiguous, a carryforward rule,
deployment-failure alerting from the Azure DevOps pipeline, a report over the eventhouse for windows past the app's 14 days, a
rule catching scheduler auto-disable, and a separate capacity for the monitoring Eventhouse if alerting must survive throttling.

## What this does not establish

- Metrics app retention beyond the 14-day compute and 30-day storage windows, or whether history survives an upgrade (the
  upgrade path deletes and recreates the workspace); likewise Monitor hub job-run retention and refresh-history retention.
- Whether **Channel post** works despite the limitations page saying Teams channels are unsupported.
- Whether `administration_members`-only identities receive `Summary` events, or how a Terraform-created capacity differs here —
  untested.
- Whether any Log Analytics or Azure Storage sink exists for Fabric capacity or workspace logs.
- End-to-end latency from event to email; the docs give sub-second rule evaluation, not delivery.
- How the `80` defaults behave on a real workload; the tutorial calls `80` an example.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Capacity Metrics app](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app), [health](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-health-page), [compute](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-compute-page), [install](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-install) | Pages, measure names, 10–15 min latency, 14/30 day views, permissions, no alerts | 2026-11-03 / 10-12 |
| [Capacity overview events](https://learn.microsoft.com/en-us/fabric/real-time-hub/explore-fabric-capacity-overview-events) and [operation events](https://learn.microsoft.com/en-us/fabric/real-time-hub/explore-fabric-capacity-operation-events) | Event types, 30 s cadence, schemas, duplicates, drops, no backfill | 2026-09-29 / 10-14 |
| [Create streams](https://learn.microsoft.com/en-us/fabric/real-time-hub/create-streams-fabric-capacity-overview-events) and [set alerts](https://learn.microsoft.com/en-us/fabric/real-time-hub/set-alerts-fabric-capacity-overview-events) on capacity events, [tutorial](https://learn.microsoft.com/en-us/fabric/real-time-hub/tutorial-monitor-capacity-threshold) | Eventstream path, capacity admin prerequisite, three templates, `80` default, grouped-by-`capacityId` condition | 2026-08-20 / 09-10 |
| [Subscribe permission](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-subscribe-permission), [events overview](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-overview), [capacity consumption](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-capacity-consumption) | Capacity administrator for REST subscriptions, paused listeners and 24 h retention, regions, event operation and listener rates | 2026-10-06 / 10-14 / 05-21 |
| [Activator introduction](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/activator-introduction), [limitations](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/activator-limitations), [rule actions](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/rule-actions) | Condition vocabulary, actions, rate limits, internal-only email, no alerts from the metrics app, channels conflict | 2026-10-13 / 05-12 |
| [Workspace monitoring](https://learn.microsoft.com/en-us/fabric/fundamentals/workspace-monitoring-overview), [configure](https://learn.microsoft.com/en-us/fabric/fundamentals/enable-workspace-monitoring), [item job event logs](https://learn.microsoft.com/en-us/fabric/fundamentals/item-job-event-logs) | Monitoring Item, telemetry, 30-day default, prerequisites, preview endpoint, `ItemJobEventLogs` schema | 2026-11-10 / 09-29 |
| [Monitor hub](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub), [job runs](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub-jobs), [job alerts](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub-alerts) | Preview status, pages, supported items, free failure emails vs Activator | 2026-09-29 / 10-06 / 10-01 |
| [Job Scheduler](https://learn.microsoft.com/en-us/fabric/fundamentals/job-scheduler), [refresh data](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-data) | Failure notifications, auto-disable ~10 failures, 90-day expiry, refresh history and APIs | 2026-10-30 / 10-01 |
| [Track user activities](https://learn.microsoft.com/en-us/fabric/admin/track-user-activities), [Power BI activity log](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-admin-auditing), [operation list](https://learn.microsoft.com/en-us/fabric/admin/operation-list) | Purview audit, Exchange Audit Logs role, `ActivityEvents` limits, `DeployAlmPipeline` | 2026-07-01 / 02-17 / 11-10 |
| [Items — List Items (Admin)](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-items), [Azure Monitor supported metrics index](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/metrics-index) | Preview admin API and rate limits; no `Microsoft.Fabric` metric | 2026-11-11 / 11-03 |




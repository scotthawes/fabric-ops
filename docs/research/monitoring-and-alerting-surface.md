# With no Azure Monitor metrics for the capacity, what can actually be monitored and alerted on in Fabric?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's operational runbook and whatever lands in `docs/specs/` about alerting

## Short answer

Two machine-readable paths exist and neither is Azure Monitor: the **Capacity Metrics app**, which is
read-only and explicitly "doesn't support alerts or notifications", and the **Real-Time hub capacity
events** (`Microsoft.Fabric.Capacity.Summary` every 30 s, `Microsoft.Fabric.Capacity.State` on change),
which feed Eventstream, an eventhouse for history, and Activator for alerting. Everything else —
Monitor hub, refresh history, job scheduler, audit log — is either a UI, a per-item email, or an API
you have to poll. An operator therefore reads the metrics app for diagnosis and builds rules on the
capacity events for alerting; there is no out-of-the-box alert for being throttled.

## Detail

### 1. The Capacity Metrics app

App version 3.0 ships two reports: the **default report** (GA, opens by default) and the **Fabric
Capacity Metrics app preview report** (preview). Default-report pages: **Health**, **Compute**,
**Storage**, **Timepoint**, **Timepoint summary**, **Timepoint item detail**, **On-demand Compute for
Spark**, **On-demand Compute for Spark detail**, **Plan capacity**, **Monitor paused capacity**,
**Calculations**. The preview report has **Health**, **Compute**, **Workspace Detail**, **Storage**,
**On-demand Compute for Spark**, **Help**. (metrics app, updated 2026-11-03)

Measures, exactly as named:

- Health cards: `# Capacities`, `Avg. utilization %`, `# Throttled capacities`, `# Interactive rejected
  capacities`, `# Background rejected capacities`. (health page, 2026-10-12)
- Health states: `Healthy`, `Suspended`, `At Risk of Throttling`, `At Risk of Overage Billing`,
  `Overage Billing Active`, `Throttling`, `At Risk of Interactive Rejection`, `Interactive Rejection`,
  `At Risk of Background Rejection`, `Background Rejection`. "At risk" means at least one 30-second
  window above **90%**; the non-at-risk states need a window above **100%**.
- Health columns: `Cumulative debt`, `Throttling (s)`, `P95 interactive delay`, `P95 interactive
  rejection`, `P95 background rejection`, `Usage variance`, `Blocked workspaces`.
- Compute cards: `SKU`, `Average utilization %`, `Peak utilization %`. Ribbon chart: `CU`, `Duration`,
  `Operations`, `Users`. (compute page, 2026-10-12)
- Utilization series: `Background %`, `Interactive %`, `Background nonbillable %`, `Interactive
  nonbillable %`, `Autoscale CU % Limit`, `CU % Limit`.
- Overages tab, view `Overage (Carryforward)`: `Add %`, `Burndown %`, `Cumulative %`. View `Overage
  (Billed)`: `Rolling cumulative 24 hour billed overage CU (hr)`, `Overage billing limit CU (hr)`,
  `Overage (Billed) CUs (s)` — populated only when capacity overage is enabled.
- Item matrix: `CU (s)`, `Duration (s)`, `Users`, `Billing type`; optional `Rejected count`,
  `Failed count`, `Invalid count`, `InProgress count`, `Successful count`, `Overloaded minutes`,
  `Performance delta`, `Item Size (GB)`.
- System events table: `Time`, `State`, `State Change Reason`, with reasons `Created`,
  `ManuallyResumed`, `NotOverloaded`, `Deleted`, `AllRejected`, `InteractiveDelay`,
  `InteractiveDelayAndSurgeProtectionActive`, `InteractiveRejected`,
  `InteractiveRejectedAndSurgeProtectionActive`, `SurgeProtectionActive`, `ManuallyPaused`.

Cadence and latency: "usage data becomes available within 10 to 15 minutes"; the `capacities`,
`workspaces` and `items` dimensions refresh with "a scheduled semantic model refresh at midnight
(local time)", so a new capacity or item does not appear until then unless you refresh manually.

Retention: the compute page is a **14-day** view and storage a **30-day** view. A longer retention
period for the underlying semantic model is **not documented — could not establish**. The docs also
say the app's semantic model is "only supported for use by the reports provided in the app", so it is
not a data source to build on.

Who can see it: installation needs **capacity admin** plus "a Power BI license (Pro, Premium Per User,
or a Power BI individual trial)"; the Health page shows "only the capacities for which you have admin
access"; sharing requires being a capacity admin; without sharing, even an invited B2B user sees
nothing. Emails are hidden by the tenant setting `Show user data in the Fabric Capacity Metrics app
and reports`. (install, 2026-10-12)

### 2. Real-Time hub capacity events — the only machine-readable source

Three event groups matter, and the third is easy to miss:

| Event type | Cadence |
| --- | --- |
| `Microsoft.Fabric.Capacity.Summary` | "every 30 seconds"; one line per 30-second window per active capacity, suppressed when every value is 0, and not emitted at all while paused |
| `Microsoft.Fabric.Capacity.State` | on change only — created, overloaded, paused, resumed, deleted; scaling and renaming are not state changes |
| `Microsoft.Fabric.CapacityOperationEvents.Operation` | one row per operation that consumes CU, not aggregated |

(all three: overview events, updated 2026-09-29; operation events, updated 2026-10-14)

CloudEvents envelope: `source` (tenant id for operation events), `subject`
(`/capacities/<capacity-id>`, or `/capacities/<id>/workspaces/<ws>/items/<item>`), `type`, `time`,
`id`, `specversion` `1.0`, `dataschemaversion` `1.0` (`1.1` for operation events).

`Summary` fields, which are what a threshold rule reads: `capacityId`, `capacityName`,
`capacitySku`, `windowStartTime`, `windowEndTime`, `baseCapacityUnits`, `capacityUnitMs`,
`interactiveDelayThresholdPercentage`, `interactiveRejectionThresholdPercentage`,
`backgroundRejectionThresholdPercentage`, `overageTotalCapacityUnitMs`,
`overageAddCapacityUnitMs`, `overageBurndownCapacityUnitMs`, `utilizationBackground`,
`utilizationInteractive`, `utilizationBackgroundPreview`, `utilizationInteractivePreview`,
`capacityUnitUtilizationBreakdown`, `tenantId`, `capacityRegion`,
`processedOverageCapacityUnitsMs`, `overageBillingLimitCapacityUnitsMs`. The three
`…ThresholdPercentage` fields are the smoothed percentages of the next 10 minutes / 1 hour / 24 hours,
so they are the alertable equivalent of "will I be throttled".

`State` fields: `capacityId`, `capacityName`, `capacitySku`, `transitionTime`, `capacityState`,
`stateChangeReason`, `activationId`. Note the semantics trap: "ManuallyResumed is treated as
NotOverloaded", and a blank state table for an active capacity means `NotOverloaded` — so absence of
events is not evidence of health.

Delivery is **best effort, no backfill**: "events can either fail to send, or duplicates might be
received". Duplicates are removed with
`summarize take_any(*) by windowStartTime, windowEndTime, capacityId`; missing events are handled by
sampling a max over five minutes. Consuming means **Create eventstream** (to an eventhouse for history,
or onward) or **Set alert** (direct to Activator). Capacity overview events are exempt from the
same-region rule that applies to operation and job events. Subscribing by REST needs **capacity
administrator** on the source capacity; creating the consumer needs Contributor on the workspace.

### 3. Activator as the alerting mechanism

The **Set capacity alert** dialog offers three templates: **Alert when capacity usage % exceeds a
threshold** (tracks `interactiveDelayThresholdPercentage`, default `80`), **Alert when a capacity
metric exceeds a threshold** (any numeric field, e.g. `backgroundRejectionThresholdPercentage`,
`interactiveRejectionThresholdPercentage`, `interactiveDelayThresholdPercentage`), and **Alert when a
capacity changes state** (`Any state change`, `Overloaded`, `Active`, `Suspended`, `Deleted`). Each
pre-fills a **numeric change condition grouped by `capacityId`**, so you "get a single alert when the
measure crosses the threshold, instead of a continuous stream of alerts". (alert templates, 2026-09-10)

Beyond thresholds, rules can use `BECOMES`, `INCREASES`, `DECREASES`, `EXIT RANGE` and absence of
events (heartbeat), with state tracked per object; rules fire on entry into a state. (Activator
introduction, 2026-10-13)

Actions: **Send email**, **Teams → Message to individuals / Group chat message / Channel post**, run a
Fabric item (pipeline, notebook, Spark job, dataflow, copy job, function, publish business event
(preview)), or **Create custom action**, which is a Power Automate flow. (rule actions, 2026-05-12)
There is no generic webhook action; webhooks and ticket systems go through Power Automate, or out of
Fabric via an Eventstream **Custom endpoint** using Event Hubs, Kafka or AMQP.

Limits that change design: 10,000 events per second per rule (the rule **stops** above it); 500 rules
per Activator item; email 500 messages per activator per hour and 30 per rule per recipient per hour;
Teams 100 messages per recipient per hour and 50 per tenant per second; recipients must be internal —
"Activator doesn't allow email notifications to be sent to either external email addresses or guest
email addresses"; and "Creating alerts from the Fabric or Power BI Capacity Metrics app isn't
supported". (limitations, 2026-10-13)

**Conflict, unresolved:** the limitations page states "Teams channels aren't currently supported",
while the actions page documents **Channel post**. I could not establish which is current; do not
promise channel delivery without testing it.

Is it a metric alert replacement? For signal, yes — it is the only threshold engine on capacity data.
It is not equivalent where a metric alert gives you: history and an alert-status page (Activator keeps
none you can query), alerting that survives the capacity being unhealthy (Activator runs on capacity,
and "Power BI reports and Activator alerts that use the monitoring database respect the capacity state
and can be throttled"), and cost-free evaluation — each event is billed as an event operation at
`0.000011111 CU Hour` per 64-KB chunk, plus an **event listener** at `0.0222 CU Hour` per hour while a
consumer exists. (events capacity consumption, 2026-05-21)

### 4. Item-level monitoring

- **Monitor hub** — preview, five pages: Job runs, Applications, Capacity and cost, Agents, Alerts.
  "Any Fabric user can open the Monitor hub, but you only see activities for Fabric items you have
  permission to view." Job runs covers Copy Job, Dataflow Gen2, Datamart, dbt Job, Experiment, Graph
  model, Lakehouse, Map, Notebook, Pipeline, Semantic model, Spark job definition, User data function
  and others, summarising "the last five runs for each item". Retention of the list is **not
  documented — could not establish**. (monitor hub, 2026-09-29; job runs, 2026-10-06)
- **Job scheduler** — failure notifications are email only, configured per item under **Failure
  notifications**, applying to all schedules of that item and to scheduled runs only (not manual).
  Recipients must be Entra users or groups including B2B guests; "Direct external email addresses
  aren't supported." Two behaviours matter operationally: a scheduler that fails repeatedly is
  **auto-disabled** ("typically set to 10 consecutive failed runs") and must be restarted manually,
  and schedules **expire if a user doesn't log in to Fabric for 90 consecutive days**. Schedule
  ownership is tracked separately from item ownership, so taking over an item does not transfer its
  schedules. (job scheduler, 2026-10-30)
- **Refresh history** — per semantic model, with automatic retries shown as separate attempts, tabs for
  Scheduled and OneDrive, and a **Semantic Model Refresh Detail** page reachable from the Monitor hub
  with execution metrics. Failures email the owner by default plus the addresses in **Email these
  contacts when the refresh fails**; on-demand and programmatically triggered refreshes send no
  notification. API: **Get Refresh History** and **Get Refresh Execution Details**, with the caveat
  that warnings are not returned by the API even though they appear in the UI. (refresh data,
  2026-10-01)
- **Audit log** — the Fabric/Power BI activity log now lives in Microsoft Purview; access needs the
  **Audit Logs** role in Exchange Online, not Fabric administrator. The Power BI **ActivityEvents** API
  returns at most one day per request, in batches of roughly 5,000–10,000 with a continuation token,
  and lags 30–60 minutes. Operations relevant here: `DeployAlmPipeline` ("Deployed to a pipeline
  stage"), `CreateAlmPipeline`, `ChangeCapacityState`, `RefreshDataset`, `RequestDataflowRefresh`.
  (track user activities, 2026-07-01; auditing, 2026-02-17; operation list, 2026-11-10)
- **Admin and item APIs** — `GET https://api.fabric.microsoft.com/v1/admin/items` lists items with
  `capacityId`, `workspaceId`, `creatorPrincipal`, but is **Preview**, needs Fabric administrator or a
  service principal with `Tenant.Read.All`, and is limited to 10 requests per minute and 200 per hour
  per tenant. Job runs are readable per instance (`get-item-job-instance`,
  `cancel-item-job-instance`) alongside `list-item-schedules` — there is **no documented endpoint that
  enumerates all runs**, so a "report instead of a UI click" is either per-instance polling or the
  workspace-monitoring logs. (admin items, 2026-11-11)

### 5. Workspace monitoring

A workspace gets one **Monitoring Item**, which contains an Eventhouse with a read-only KQL database,
an Eventstream, an Activator and optionally an Operations Agent. Data can go to that Eventhouse or to
another Monitoring Item's Eventhouse — same region, and "You can't change the destination after you
configure workspace monitoring". Only one Monitoring Item per workspace. Collection is off until you
turn it on, and it "doesn't backfill earlier activity". (overview, 2026-11-10; configure, 2026-09-29)

Captured, per workload: pipeline activity run logs, Copy job run details, Dataflow Gen2 logs, Warehouse
query execution logs, mirrored database execution logs, semantic model operation logs, Eventhouse
query/command/ingestion/capacity-throttling logs, Eventstream node status and error metrics, Activator
rule notifications, GraphQL and SQL database metrics, and **job events** in `ItemJobEventLogs`
(`JobStatus`, `JobType`, `JobInvokeType`, `DurationMs`, `ExecutingPrincipalId`, `JobStartTime`,
`JobEndTime` — the table that makes a job-failure rule possible). (overview; item job event logs,
2026-11-10)

Prerequisites: workspace on Fabric or Premium capacity; tenant setting **Workspace admins can turn on
monitoring for their workspaces**; **Users can create Fabric items**; workspace admin. Default
retention **30 days**, changeable via `Manage > Data policies` on the KQL database; the caching period
must not exceed retention. Contributors and above can query. Cost is capacity consumption for
Eventhouse, Eventstream and queries, which is why Microsoft recommends hosting a central monitoring
Eventhouse "on its own Capacity" to shield monitoring from throttling. (configure)

What is GA versus preview: the Monitoring Item experience is documented without a preview label as of
2026-11-10, with the **legacy** Eventhouse path kept as a separate, older option. The Eventstream
**custom endpoint** to Event Hubs/Kafka/AMQP is preview ("Through the preview period, this setting can
only be enabled at creation time"). There is **no Log Analytics or storage sink** for workspace logs;
storage means Eventhouse plus OneLake availability/shortcuts, and external systems mean the preview
custom endpoint. A Log Analytics destination could not be established.

### 6. What cannot be alerted on

- **No Azure Monitor metric or metric alert.** The supported-metrics index (2026-11-03) has no
  `Microsoft.Fabric` entry, so there is no metric alert, no action group, no Azure Monitor
  auto-scale hook. This is the premise of the question and it holds.
- **Nothing alerts when a capacity is throttled unless you build it.** The metrics app "doesn't
  support alerts or notifications"; the State event exists but no rule is created for you.
- **No central failed-refresh alert out of the box.** Default is an email to the semantic model owner,
  per model, plus whatever addresses someone typed into that model's settings — and none at all for
  on-demand or API-triggered refreshes.
- **No alert when a scheduler auto-disables itself.** You get one email per failed run, then silence.
- **Nothing for deployment failures.** A Fabric deployment pipeline pre-deploy/post-deploy step failing
  is visible as `DeployAlmPipeline` in the audit log and as a failure in the Azure DevOps pipeline that
  called it; Fabric emits no event and raises no alert for it.
- **No alert on unexpected capacity pause or resize**, beyond the State event you must subscribe to.
- **No alert on storage growth**; storage is a 30-day chart, not a signal.
- **Silent consumer failure.** If the owner of an event listener loses the subscribe permission the
  listener "enters a paused state", retaining events for "up to 24 hours" — an alerting gap that looks
  like calm. Workspace outbound access protection and workspace-level private links also block
  cross-workspace consumption by default.

### 7. A practical minimal alert set

| # | Alert | Source | Condition | What a false positive looks like |
| --- | --- | --- | --- | --- |
| 1 | Capacity overloaded | `Microsoft.Fabric.Capacity.State` | state changes to `Overloaded` (template **Alert when a capacity changes state**) | A single 30-second window over 100% interactive delay that no user noticed; a pause pushing all smoothed usage into one window (spikes "up to 288,000% of normal") |
| 2 | Interactive delay approaching | `Microsoft.Fabric.Capacity.Summary` | `interactiveDelayThresholdPercentage` > `80` | One heavy interactive query; with capacity overage enabled the capacity is not actually throttled, only billed |
| 3 | Background rejection approaching | `Microsoft.Fabric.Capacity.Summary` | `backgroundRejectionThresholdPercentage` > `80` | An overnight batch that burns down before morning; the 24-hour window falls slowly, so the alert stays on after recovery |
| 4 | Capacity paused or resumed | `Microsoft.Fabric.Capacity.State` | `capacityState` changes to `Suspended` or `Active`, or `stateChangeReason` = `ManuallyPaused` | Your own scheduled pause; a resume that fires the rule on the way back up |
| 5 | Scheduled job or refresh failed | job events / `ItemJobEventLogs`, or free **Schedule failure emails** | job status `Failed` for a named pipeline or notebook | A retry that succeeded seconds later; a job that is expected to fail in dev; the same job failing repeatedly after the scheduler auto-disabled |

If cost matters more than latency, replace #3 with `overageTotalCapacityUnitMs` rising without a
matching `overageBurndownCapacityUnitMs` — that is carryforward that is not paying itself down, which
is what becomes a 3× rate bill.

## What this settles

- **Monitoring architecture:** the **capacity** story is the metrics app for diagnosis plus Real-Time
  hub events for signal — Eventstream into an eventhouse for history, Activator for alerting. The
  **item** story is workspace monitoring (`ItemJobEventLogs` and workload logs) for queryable detail,
  the Monitor hub and job scheduler for presence, and the audit log for who changed what. Azure Monitor
  is in neither path.
- **A team must build, not configure:** one Activator rule set per capacity (none ship enabled); an
  eventhouse sink plus the dedupe query, because there is no backfill; a pause/heartbeat rule that
  treats a missing `Summary` as ambiguous; a carryforward/overage rule; a deployment-failure alert from
  the Azure DevOps pipeline, since Fabric emits nothing; a report over the eventhouse for any window
  longer than the metrics app's 14 days; a rule catching scheduler auto-disable; and a separate
  capacity for the monitoring Eventhouse if alerting must survive throttling.
- **Cost of monitoring is itself capacity consumption** — event operations, event listeners,
  Eventhouse and Eventstream all bill against a capacity, so alerting competes with the workload it
  watches.

## What this does not establish

- The metrics app's data retention beyond the 14-day compute and 30-day storage windows, or whether
  history survives an app upgrade (the upgrade path deletes and recreates the workspace).
- Whether **Channel post** works despite the limitations page saying Teams channels are unsupported.
- Monitor hub job-run retention, and refresh-history retention.
- Whether a capacity-created-with-Terraform behaves differently for events (e.g. whether
  `administration_members`-only identities receive `Summary` events) — untested here.
- Whether any Log Analytics or Azure Storage sink exists for Fabric capacity or workspace logs; the
  documented destinations are eventhouse, OneLake and the preview custom endpoint.
- Activation latency end to end from event to email — the docs describe sub-second rule evaluation but
  not delivery.
- Real behaviour of the `80` defaults against a real workload; the tutorial explicitly calls `80` an
  example.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [What is the Microsoft Fabric Capacity Metrics app?](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app) | Report list, 10–15 min latency, midnight dimension refresh, no alerts | 2026-11-03 |
| [Metrics app health page](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-health-page) | Health states, at-risk thresholds, cards and columns | 2026-10-12 |
| [Metrics app compute page](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-compute-page) | Measure names, carryforward/burndown, system event reasons, 14-day view | 2026-10-12 |
| [Install the metrics app](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-install) | Capacity admin + Power BI licence, sharing, B2B | 2026-10-12 |
| [Metrics app calculations](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-calculations) | Throttle limits and recovery formula | 2026-08-14 |
| [Explore Fabric capacity overview events](https://learn.microsoft.com/en-us/fabric/real-time-hub/explore-fabric-capacity-overview-events) | Event types, 30 s cadence, Summary/State schemas, duplicates and drops | 2026-09-29 |
| [Explore Fabric capacity operation events](https://learn.microsoft.com/en-us/fabric/real-time-hub/explore-fabric-capacity-operation-events) | `…CapacityOperationEvents.Operation` schema, same-region rule | 2026-10-14 |
| [Create streams for capacity overview events](https://learn.microsoft.com/en-us/fabric/real-time-hub/create-streams-fabric-capacity-overview-events) | Eventstream/Real-Time hub path, capacity admin prerequisite | 2026-08-20 |
| [Set alerts on capacity overview events](https://learn.microsoft.com/en-us/fabric/real-time-hub/set-alerts-fabric-capacity-overview-events) | The three templates, `80` default, grouped-by-`capacityId` condition | 2026-09-10 |
| [Monitor capacity health tutorial](https://learn.microsoft.com/en-us/fabric/real-time-hub/tutorial-monitor-capacity-threshold) | `backgroundRejectionThresholdPercentage` worked example | 2026-09-10 |
| [Subscribe permission for Azure and Fabric events](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-subscribe-permission) | Capacity administrator for REST subscriptions; paused listeners, 24 h retention | 2026-10-06 |
| [Introduction to Azure and Fabric events](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-overview) | Event groups and regional requirements | 2026-10-14 |
| [Events capacity consumption](https://learn.microsoft.com/en-us/fabric/real-time-hub/fabric-events-capacity-consumption) | Event operation and event listener rates | 2026-05-21 |
| [What is Fabric Activator?](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/activator-introduction) | Condition vocabulary, actions, state transitions | 2026-10-13 |
| [Activator limitations](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/activator-limitations) | No alerts from the metrics app, rate limits, internal-only email, channels conflict | 2026-10-13 |
| [Configure actions for Activator rules](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/rule-actions) | Email, Teams variants, Fabric items, custom action | 2026-05-12 |
| [Workspace monitoring overview](https://learn.microsoft.com/en-us/fabric/fundamentals/workspace-monitoring-overview) | Monitoring Item, supported telemetry, 30-day default, throttling caveat | 2026-11-10 |
| [Configure workspace monitoring](https://learn.microsoft.com/en-us/fabric/fundamentals/enable-workspace-monitoring) | Prerequisites, tenant settings, destination immutability, preview custom endpoint | 2026-09-29 |
| [Item job event logs](https://learn.microsoft.com/en-us/fabric/fundamentals/item-job-event-logs) | `ItemJobEventLogs` schema and job types | 2026-11-10 |
| [What is Monitor Hub](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub) and [Job runs](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub-jobs) | Preview status, pages, supported item types | 2026-09-29 / 2026-10-06 |
| [Job alerts in the Monitor hub](https://learn.microsoft.com/en-us/fabric/admin/monitoring-hub-alerts) | Free failure emails vs Activator rules, preview | 2026-10-01 |
| [Job Scheduler](https://learn.microsoft.com/en-us/fabric/fundamentals/job-scheduler) | Failure notifications, auto-disable at ~10 failures, 90-day expiry, schedule ownership | 2026-10-30 |
| [Data refresh in Power BI](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-data) | Refresh history, retries, failure emails, refresh history APIs | 2026-10-01 |
| [Track user activities](https://learn.microsoft.com/en-us/fabric/admin/track-user-activities) and [Power BI activity log](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-admin-auditing) | Purview audit, Exchange Audit Logs role, ActivityEvents limits | 2026-07-01 / 2026-02-17 |
| [Operation list](https://learn.microsoft.com/en-us/fabric/admin/operation-list) | `DeployAlmPipeline`, `ChangeCapacityState`, refresh operation names | 2026-11-10 |
| [Items — List Items (Admin)](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-items) | Preview admin API, permissions, 10/min and 200/hour limits | 2026-11-11 |
| [Azure Monitor supported metrics index](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/metrics-index) | No `Microsoft.Fabric` entry — no metric alert | 2026-11-03 |

# How should Fabric capacity be provisioned and cost-controlled per environment?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the work repo's Terraform layout for dev/test/prod and its pause/resume schedule

## Short answer

A Fabric capacity is a plain Azure resource — `Microsoft.Fabric/capacities` — so Terraform can create,
resize and tag it, but cannot pause it, cannot set capacity overage, and cannot assign workspaces to it.
Pausing works only on F SKUs: it stops billing for future compute but immediately bills the smoothed usage
already accrued, and makes the capacity's content unavailable. The evidence points to one capacity per
environment; ADR [0004](../adr/0004-one-shared-capacity.md) accepts a single shared capacity instead, which
makes scheduled pause impractical, and the trade-off is stated below.

## Detail

### 1. The Azure resource that *is* a capacity

- Type `Microsoft.Fabric/capacities`, deployable at **resource group** scope only, so every capacity has a
  subscription, resource group, region and name (3–63 chars, pattern `^[a-z][a-z0-9]*$`). Latest documented
  API version is `2026-09-01-preview`; the stable one AzureRM uses is `2023-11-01`. (ARM reference, updated 2026-10-20)
- Shape: `sku { name, tier }` where `tier` is always `Fabric`, `properties.administration.members`, and — from
  the preview API — `properties.overage { state: Disabled|Enabled, thresholdCapacityUnitHours }`. CUs per SKU:
  `F2`=2, `F4`=4, `F8`=8, `F16`=16, `F32`=32, `F64`=64, `F128`=128, `F256`=256, `F512`=512, `F1024`=1024,
  `F2048`=2048, `F4096`=4096, `F8192`=8192; `Trial`=64. Reserved/P-SKU parity is `F64`=P1, `F128`=P2,
  `F256`=P3, `F512`=P4, `F1024`=P5 — it stops at P5, and P SKUs are being retired in favour of F SKUs.
  (same; Licenses, updated 2026-11-10)
- Creation paths: portal, Bicep/ARM, `azapi_resource`, `az fabric capacity create` (extension
  `microsoft-fabric`, CLI 2.61.0+), or `azurerm_fabric_capacity`. Prerequisites: an Azure subscription
  **associated with the Entra tenant where you want to provision the capacity**, the `Microsoft.Fabric`
  resource provider registered, a region that supports the intended workloads, and enough CU quota in that
  subscription *and region* (an F64 needs 64 CUs). (Buy capacity, 2026-08-27)
- Placement: a capacity "resides in a tenant", and "you can assign any workspace — including *My workspaces* —
  to any capacity in the tenant". Cross-tenant use is therefore impossible: the subscription must be in the
  tenant that owns the workspaces. Region is fixed at creation — "Capacities can't be moved to different
  regions after they're created" — and "any workspaces created under it will have their content stored in that
  region". Serving a workspace in another region therefore means *assigning it to a capacity in that region* — a
  workspace migration, not a capacity move — and that migration is unsupported while either capacity is paused;
  non-Power BI items must be deleted first. (Licenses; Buy capacity; Real-Time hub events, 2026-08-18; Multi-Geo)

### 2. Pause and resume

- Supported, F SKU only: "To pause your capacity, you need: An **F SKU capacity**". A Trial capacity is a
  `Trial` SKU, so pause is out of scope there. (Pause and resume, updated 2026-08-14; Licenses)
- Mechanism is an ARM **action**, not a settable property:
  `POST .../Microsoft.Fabric/capacities/{capacityName}/suspend?api-version=2023-11-01`, matching `resume`,
  returning 202 + `Azure-AsyncOperation`; CLI `az fabric capacity suspend|resume`; SDK
  `FabricCapacityResource.SuspendAsync`. State is read-only: `properties.state` ∈ `Active`, `Provisioning`,
  `Failed`, `Updating`, `Deleting`, `Suspending`, `Suspended`, `Pausing`, `Paused`, `Resuming`, `Scaling`,
  `Preparing`. There is no writable paused flag. RBAC is `Microsoft.Fabric/capacities/read`, `/write`,
  `/suspend/action`, `/resume/action`, with the docs recommending a custom role on exactly those four rather
  than Owner/Contributor. (REST — Suspend and Get, 2026-10-23; Pause and resume; Buy capacity)
- Billing: "When you pause your capacity, the remaining cumulative overages and smoothed operations on your
  capacity are summed, and added to your Azure bill"; resuming "also resumes billing". Pausing is also the
  documented way to end throttling immediately, since a starting capacity "has zero future capacity usage".
  Content-wise, pausing "can prevent Microsoft Fabric content from being available" until resumed, and a
  paused capacity emits no Summary events. (Pause and resume; Throttling; Real-Time hub events)

### 3. Sizing, smoothing and cost control

- The unit is the capacity unit (CU); an F2 is "2 CUs, or 48 CU hours per day". **Bursting** lets an operation
  temporarily exceed provisioned compute; **smoothing** spreads its CU over future *timepoints* of 30 seconds,
  2,880 per 24 hours. Interactive operations smooth "over a minimum of five minutes, and up to 64 minutes";
  background operations smooth over **24 hours**. Throttle stages: ≤10 min = overage protection (10 minutes of
  future capacity free); 10–60 min = interactive delay of 20 seconds at submission; 60 min–24 h = interactive
  rejection; >24 h = background rejection. (Throttling, 2026-08-14)
- **Interactive vs background**: interactive work smooths over minutes and is delayed/rejected first; background
  (pipelines, Spark, and *all* Warehouse operations) smooths over 24 hours, so it fills the 24-hour limit, not
  the 10-minute one. Real-Time Intelligence skips the 20-second delay stage. In-flight operations are never
  throttled. Overages become *carryforward* CUs, paid down by unused timepoints (*burndown*). Read utilisation
  in the Capacity Metrics app (Compute: Utilization, Throttling, System events, Overages; Health: at-risk views),
  on 30-second windows with roughly 10–15 minutes latency. (Throttling; Metrics app scenarios, 2026-08-28)
- Azure Monitor: **could not establish a metric or metric alert for an F capacity.** The supported-metrics index
  (2026-11-03) has no `Microsoft.Fabric` entry — only `Microsoft.PowerBIDedicated/capacities` (A/EM). Documented
  alerting is email capacity notifications, Real-Time hub events (`Microsoft.Fabric.Capacity.Summary` every 30 s,
  `Microsoft.Fabric.Capacity.State` on change, including paused/resumed), and Activator alerts on those events.
- **Capacity overage** is the real cost lever and it is on by default: "When you create a new Fabric capacity,
  capacity overage is enabled by default", default threshold "25%", billed "at three times the pay-as-you-go
  rate" via a separate meter ("Capacity Overage Capacity Usage CU"). It is "not a hard spending cap"; keep the
  threshold "below one-third of your daily CU hours", where overage costs as much as scaling up. **Surge
  protection** is the complementary brake: it rejects new *background* operations at a configured `Rejection
  threshold` / `Recovery threshold` on the 24-hour background percentage, before deep throttling, never stopping
  in-progress jobs — and "To fully protect critical solutions, isolate them in a designated capacity." (Enable
  capacity overage, 2026-09-11; Overage overview, 2026-08-26; Surge protection, 2026-09-23)

### 4. Administration boundaries

- **Capacity administrator** — "Assign workspaces to the capacity", "Manage user permission to the capacity",
  "Manage workloads to configure memory usage". (Admin roles, 2026-04-21) **Capacity contributor** — "Set up the
  ability to add workspaces to the capacity", scoped to "The entire organization" or "Specific users or security
  groups"; "A **contributor** on a capacity can assign workspaces to that capacity but can't modify capacity
  settings or delete the capacity." (Manage your capacity, 2026-03-06)
- Assigning a workspace needs **either**: the same page says "you need to have a capacity **contributor** role,
  and a workspace admin role", while the Admin permissions row lists "Add or remove workspaces from the
  capacity". Both hold; Contributor is the narrower grant.
- Service principals: Fabric docs speak only of users — "Only **users** that belong to the tenant ... can be
  added as admins"; "B2B users can't be capacity administrators"; the ARM property is "administrator **user**
  identities". But the AzureRM provider docs say "The member must be an Entra user or a service principal. ...
  If the user is a service principal, use object ID", so an SP can hold capacity **Admin** in practice. Whether
  an SP can hold capacity **Contributor** is undocumented — could not establish.

### 5. Environment topology

- The docs assume isolation: "It's best practice to do development and testing on a **non-production capacity**"
  (singular — so dev+test on one non-prod capacity is in-pattern); "Use a dedicated workspace or capacity ... so
  you **don't impact any production systems**"; scale-out ("Create multiple smaller F SKUs") lists pros
  "Provides some isolation from noisy neighbors" and cons "Cost" and "High CU items have an increased chance of
  throttling". (Capacity planning, 2025-09-04)
- Blast radius is capacity-scoped by design: "Fabric applies throttling at the capacity level. While one
  capacity, or set of workspaces, might experience reduced performance from being overloaded, other capacities
  might continue running normally." On a shared dev+test+prod capacity, a dev notebook consumes smoothed CUs
  against prod's 10-minute, 60-minute and 24-hour limits and prod users take the delays — dev is not throttled
  "instead of" prod; a shared capacity also cannot be sized correctly, since prod should be sized from its own
  pilot data so peak usage sits "comfortably under 100 percent". (Throttling; Capacity planning)

### 6. Terraform specifics

- `azurerm_fabric_capacity` **exists** (Fabric subcategory). It manages `name`, `location`,
  `resource_group_name`, `sku { name, tier }`, `administration_members`, `tags`, timeouts, and supports import.
  `name`, `location` and `resource_group_name` force replacement. (AzureRM provider docs, checked 2026-11-11)
- Its documented `sku.name` values stop at **`F2`…`F2048`** — no `F4096`/`F8192`, despite the licensing page
  listing them. It is pinned to API **`2023-11-01`**, so there is no `overage` block, and it exposes no
  suspend/resume: pausing must be a pipeline step (`az fabric capacity suspend` or a raw ARM POST) outside
  Terraform state.
- `microsoft/fabric` (v1.15.1) explicitly cannot create a capacity: "Microsoft Fabric trial capacity is not
  supported. Only self-provisioned Fabric Capacity on Azure is supported." It consumes one — `data
  "fabric_capacity"` plus `fabric_workspace.capacity_id` — and exposes `capacity_region` read-only plus
  `skip_capacity_state_validation`, which warns that drift and lost state can follow if the capacity is
  inactive. (microsoft/terraform-provider-fabric docs, checked 2026-11-11)

## What this settles

- **Recommendation on the evidence: one capacity per environment.** Prod gets its own F SKU sized so peak
  smoothed usage sits under 100%; dev and test share a second small F SKU (F2/F4) in the same region, with
  separate workspaces per environment. Split them only when test needs protection from dev load or independent
  sizing. **ADR [0004](../adr/0004-one-shared-capacity.md) instead accepts one shared capacity**; its costs are
  shared throttling, a three-environment outage from one capacity incident, and sizing to the largest
  environment's peak.
- **Pause policy follows from that decision.** With one shared capacity there is no safe scheduled pause: the
  only pause windows are ones where production may be down, and the saving is therefore smaller than the
  per-second pricing suggests. If capacity is split (prod separate), pause the non-prod capacity outside working
  hours, resume as the *first* step of any deployment pipeline, never pause either side of a workspace
  migration, and never apply Fabric Terraform against a paused capacity.
- **Cost control is three settings, one of them in Terraform:** SKU size (Terraform), capacity overage threshold
  (portal/API, default 25% at 3× rate — cap at ≤ one-third of daily CU hours), surge protection (portal). None
  of the last two show up in `terraform plan`.
- **Trade-off stated:** a second capacity roughly doubles SKU spend to contain a dev runaway and permit pause;
  a single capacity is cheapest and simplest but makes every environment share one throttling budget and one
  outage domain, and gives up the scheduled saving entirely.

## What this does not establish

- That Azure Monitor has any metric or metric alert for `Microsoft.Fabric/capacities`; the supported-metrics
  index has no such entry as of 2026-11-03, and I could not tell "undocumented" from "does not exist".
- Whether an ARM/Terraform-created capacity starts with capacity overage enabled, and at what threshold — the
  "enabled by default" wording describes the creation workflow, and AzureRM cannot express the setting.
- Whether a service principal can hold capacity **Contributor** (ADR 0004 assumes it can), or whether an SP
  reached through a security group that is a contributor works in practice.
- What a *scheduled refresh* does when its capacity is paused (fail, queue or skip), whether an in-flight pause
  is deferred, and whether a prepaid "yearly capacity reservation" keeps billing or is forfeited while paused.
- Whether `administration_members` updates apply in place without replacing the capacity (implied, untested).

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Microsoft.Fabric/capacities — ARM/Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.fabric/capacities) | Resource type, scope, API versions, `administration.members`, `overage` | 2026-10-20 |
| [Fabric Capacities — Suspend](https://learn.microsoft.com/en-us/rest/api/microsoftfabric/fabric-capacities/suspend) and [Get](https://learn.microsoft.com/en-us/rest/api/microsoftfabric/fabric-capacities/get) | Suspend/resume action and URL; `properties.state` enum | 2026-10-23 |
| [Pause and resume your Fabric capacity](https://learn.microsoft.com/en-us/fabric/enterprise/pause-resume) and [monitor a paused capacity](https://learn.microsoft.com/en-us/fabric/enterprise/monitor-paused-capacity) | F-SKU prerequisite, RBAC actions, billing on pause/resume, Suspended vs Active | 2026-08-14 / 2025-06-19 |
| [Understand capacity throttling and smoothing](https://learn.microsoft.com/en-us/fabric/enterprise/throttling) and [metrics app scenarios](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app-monitor-capacity-throttling) | Bursting, smoothing windows, four throttle stages, interactive vs background, 30-second windows, 10–15 min latency | 2026-08-14 / 2026-08-28 |
| [Understand Fabric licenses and capacity](https://learn.microsoft.com/en-us/fabric/enterprise/licenses) and [buy Fabric capacity in Azure](https://learn.microsoft.com/en-us/fabric/enterprise/buy-capacity) | F2–F8192 and Trial CU table, P-SKU equivalence, tenant scoping, resource provider, CU quota, B2B exclusion | 2026-11-10 / 2026-08-27 |
| [Manage your Fabric capacity](https://learn.microsoft.com/en-us/fabric/admin/capacity-settings) and [Fabric admin roles](https://learn.microsoft.com/en-us/fabric/admin/roles) | Admin vs Contributor permissions, "only users" wording, capacity administrator tasks | 2026-09-29 / 2026-04-21 |
| [Enable capacity overage](https://learn.microsoft.com/en-us/fabric/enterprise/enable-capacity-overage), [overage overview](https://learn.microsoft.com/en-us/fabric/enterprise/capacity-overage-overview) and [surge protection](https://learn.microsoft.com/en-us/fabric/enterprise/surge-protection) | Default-on, 25% default, 3× rate, separate meter, one-third guidance, rejection thresholds | 2026-09-11 / 2026-08-26 / 2026-09-23 |
| [Azure Monitor supported metrics index](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/metrics-index) | Checked for a `Microsoft.Fabric` entry — none present | 2026-11-03 |
| [Explore Fabric capacity overview events](https://learn.microsoft.com/en-us/fabric/real-time-hub/explore-fabric-capacity-overview-events) | Summary/State events, 30-second cadence, immutable `capacityRegion` | 2026-08-18 |
| [Multi-Geo support for Fabric](https://learn.microsoft.com/en-us/fabric/admin/service-admin-premium-multi-geo) and [region availability](https://learn.microsoft.com/en-us/fabric/admin/region-availability) | Content stored in capacity region; migration blocked while paused; region support | 2026-08-13 / 2026-11-03 |
| [Plan your first Fabric deployment](https://learn.microsoft.com/en-us/fabric/enterprise/capacity-planning-plan-deployment) | Non-production capacity, isolation, scale-out pros/cons | 2025-09-04 |
| [az fabric capacity](https://learn.microsoft.com/en-us/cli/azure/fabric/capacity) and [azurerm_fabric_capacity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/fabric_capacity) | CLI suspend/resume surface; Terraform arguments, F2–F2048 only, API `2023-11-01` | 2026-09-01 / checked 2026-11-11 |
| [terraform-provider-fabric — provider docs](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/index.md) and [fabric_workspace](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/workspace.md) | Cannot create capacity; `capacity_id`, state-validation warning | checked 2026-11-11 |

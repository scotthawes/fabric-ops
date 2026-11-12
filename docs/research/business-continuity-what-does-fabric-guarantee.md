# What does Microsoft actually document about business continuity and disaster recovery for a Fabric estate, and what can a builder promise?

- **Status:** answered (with two named gaps and one unread primary source) · **Checked:** 2026-11-12
- **Blocks:** the run-book entry for "a region is gone", the recovery promise made to a customer, and whether DR is a capacity setting the pipeline must set or a design the estate must have
- **Sibling notes:** [`workspace-and-item-lifecycle.md`](workspace-and-item-lifecycle.md) covers what is reversible when *you* delete a workspace or an item, and `terraform-operating-model.md` §5 covers a mistaken `destroy`. This note is the layer above: what happens when the failing thing is a region, a service, or a capacity Azure took away, and it does not repeat the retention windows or the capacity-delete undo.

## Short answer

Microsoft documents a real DR story, but it is a **data-access and rebuild** story, not a recovery guarantee. Three pages carry it: a reliability article, an experience-by-experience recovery guide, and a OneLake data-protection page. What is promised is that OneLake data (if you opted into geo-replication, per capacity, on a paired region) stays readable — through APIs, not through the items — and that service failover "typically takes less than one hour". What is *not* promised is any RTO or RPO for Fabric, any point-in-time consistency ("the secondary region might not contain a point-in-time-consistent copy"), any durability for the **capacity resource** itself (it does not fail over; recovery step 1 is "create a new Fabric capacity"), or any SLA statement in the Fabric docs beyond one inherited 99.9% figure for pipelines. A builder can promise a **rebuild time they have measured themselves** and an **RPO equal to their own backup cadence** — nothing more can be read off Microsoft's pages.

## Detail

### 1. The surface table — every page searched, including the ones that said nothing

This is the evidence for every negative below. All rows read on **2026-11-12**; the date column is the page's own `ms.date` (and `updated_at` where it differs, which for Fabric docs often does).

| # | Surface (path) | What it says about continuity | Page date |
| --- | --- | --- | --- |
| 1 | [`fabric/security/reliability-fabric`](https://learn.microsoft.com/en-us/fabric/security/reliability-fabric) | The core article. Availability zones, the DR capacity switch, failover expectations, four recovery steps, home-region tethering. | ms.date 2025-09-19, upd. 2026-08-05 |
| 2 | [`fabric/security/experience-specific-guidance`](https://learn.microsoft.com/en-us/fabric/security/experience-specific-guidance) | Per-item recovery: what replicates, what must be rebuilt from Git, what must be copied by hand, what survives nothing. | ms.date 2026-11-11, upd. 2026-11-12 |
| 3 | [`fabric/onelake/onelake-disaster-recovery`](https://learn.microsoft.com/en-us/fabric/onelake/onelake-disaster-recovery) | LRS vs ZRS choice (made for you), 11/12-nines durability, geo-replication, and the data-loss admission. | ms.date 2026-03-11, upd. 2026-11-02 |
| 4 | [`fabric/onelake/onelake-overview`](https://learn.microsoft.com/en-us/fabric/onelake/onelake-overview) | Restates "built-in redundancy … ZRS where supported, otherwise LRS"; BCDR is opt-in per capacity. | ms.date 2026-03-09, upd. 2026-11-02 |
| 5 | [`fabric/admin/region-availability`](https://learn.microsoft.com/en-us/fabric/admin/region-availability) | Region/workload matrix only. One continuity cell: Sweden Central has "Not available by default for Power BI: Business Continuity Disaster Recovery (BCDR)". | ms.date 2026-11-03, upd. 2026-11-05 |
| 6 | [`fabric/admin/capacity-settings`](https://learn.microsoft.com/en-us/fabric/admin/capacity-settings) | One row in the Details table: "Disaster Recovery — Enable disaster recovery for the capacity". Nothing on what a capacity does when its region fails. | ms.date 2026-03-06, upd. 2026-09-29 |
| 7 | [`fabric/enterprise/buy-capacity`](https://learn.microsoft.com/en-us/fabric/enterprise/buy-capacity) | The create flow is Subscription, Resource group, name, **Region**, Size, administrator. No redundancy option, no zone choice. | ms.date 2026-08-27 |
| 8 | [`azure/templates/microsoft.fabric/capacities`](https://learn.microsoft.com/en-us/azure/templates/microsoft.fabric/capacities) | The whole `Microsoft.Fabric/capacities` schema: `location`, `properties.administration.members`, `properties.overage`, `sku`, `tags`. **No** zones, replicas, geo-pair or failover property in any API version listed. | ms.date 2024-12-09, upd. 2026-10-20 |
| 9 | [`fabric/onelake/onelake-consumption`](https://learn.microsoft.com/en-us/fabric/onelake/onelake-consumption) | What DR costs: separate "BCDR Storage", and BCDR writes at 3,056 CU-s per 4 MB/10k versus 1,626 without. | ms.date 2026-09-21, upd. 2026-09-29 |
| 10 | [`power-bi/enterprise/service-admin-failover`](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-admin-failover) | The only page with numbers: ~15-minute regional failover, ~30-second zone failover, "15-minute targeted point-in-time sync", and "Power BI can't guarantee a timeframe". | ms.date 2026-06-02, upd. 2026-06-03 |
| 11 | [`power-bi/support/service-planned-maintenance`](https://learn.microsoft.com/en-us/power-bi/support/service-planned-maintenance) | Planned maintenance takes the whole service offline for all SKUs; notice via Microsoft 365 Message center; recovery is automatic. | ms.date 2025-10-01, upd. 2026-10-07 |
| 12 | [`fabric/data-factory/data-factory-overview`](https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-overview) | The only SLA figure anywhere in Fabric docs: pipelines inherit Azure Data Factory's 99.9%. | ms.date 2026-08-05 |
| 13 | [`power-bi/support/service-support-options`](https://learn.microsoft.com/en-us/power-bi/support/service-support-options) | Support response commitments, explicitly not resolution: "doesn't provide a direct SLA for support request resolution". | undated |
| 14 | [`microsoft-365/enterprise/view-service-health`](https://learn.microsoft.com/en-us/microsoft-365/enterprise/view-service-health) | Names Office on the web, Teams, Exchange Online, Dynamics 365 as the services on the Service health page. **Does not name Fabric, OneLake or Power BI.** "Planned maintenance events aren't shown in service health." | ms.date 2026-02-09, upd. 2026-10-30 |
| 15 | [`azure/service-health/overview`](https://learn.microsoft.com/en-us/azure/service-health/overview) | Explains Service Health, Resource Health and the status page. Zero occurrences of "Fabric", "OneLake" or "Power BI". | ms.date 2025-10-31 |
| 16 | [`azure.status.microsoft/en-us/status`](https://azure.status.microsoft/en-us/status) | Live Azure status. Seven occurrences of "Fabric", **all of them "Azure Service Fabric"** — a different product. Microsoft Fabric is not a listed service. | live, undated |
| 17 | [`support.fabric.microsoft.com/support/`](https://support.fabric.microsoft.com/support/) | Titled "Microsoft Fabric service status"; the page the reliability article sends you to for failover notification. | live, undated |
| 18 | [`fabric/release-plan/`](https://learn.microsoft.com/en-us/fabric/release-plan/) → `roadmap.fabric.microsoft.com` | Roadmap items only; zero occurrences of "disaster" or "zone-redundant". | live, undated |
| 19 | `fabric/fundamentals/known-issues` and `fabric/troubleshoot/known-issues` | **No page.** Both return HTTP 404. No Fabric "known issues / outages" page exists under either path. | — |
| 20 | [`licensing/docs/view/Service-Level-Agreements-SLA-for-Online-Services`](https://www.microsoft.com/licensing/docs/view/Service-Level-Agreements-SLA-for-Online-Services) | The SLA *hub*, not the SLA: "The Service Level Agreements (SLA) describe Microsoft's commitments for **uptime and connectivity** for Microsoft Online Services." Current edition November 2026, delivered as a `.docx`. | November 2026 edition |
| 21 | [`licensing/terms/product/ForallOnlineServices/EAEAS`](https://www.microsoft.com/licensing/terms/product/ForallOnlineServices/EAEAS) | "Previews are not included in the SLA for the corresponding Online Service"; points all SLA detail at `aka.ms/CSLA`. | undated |
| 22 | `aka.ms/CSLA` → item 20 | Same landing page. No HTML rendering of the agreement. | — |

**What could not be read.** The SLA itself is a Word download (`OnlineSvcsConsolidatedSLA(WW)(English)(November_2026)(CR).docx`). The licensing host returns 403 to scripted clients and this environment cannot download or unzip a binary, so **the Fabric SLA's actual clauses are not quoted below** — only Microsoft's own one-line description of the document in row 20. That is the note's largest gap and is listed again in §8.

**What "the Fabric docs" means as a surface.** Rows 1–13 are the pages that Fabric's own continuity articles link to or are linked from. Two URL aliases resolve to the *same* document: `/azure/reliability/reliability-fabric` and `/fabric/security/reliability-fabric` return identical metadata (`document_id 1182b6bb-…`), and `/fabric/security/disaster-recovery-guide` also resolves to it. So "three DR pages" is three *documents*, not five, and a search that counts URLs will over-count.

### 2. Does a capacity have any redundancy?

Split the question in two, because the answers differ.

**Fabric resources (what runs on the capacity): yes, zone redundancy, automatic and not configurable.**

> "Fabric uses Azure availability zones to protect Fabric and Power BI items and data from datacenter failures. The service automatically distributes Fabric resources across multiple zones without requiring any customer configuration."

> "During a zone-wide outage, no customer action is required. Fabric capabilities self-heal and rebalance automatically … In some cases, in-progress operations might need to restart."

Note the caveats in the same section: Spark jobs "might fail if the primary node is in the failed zone. In such a case, you need to resubmit the jobs", warehouse/SQL analytics endpoint queries "might fail … you need to safely restart the query", and capacities in regions with "higher customer demand fluctuations might experience higher than normal latency". Self-healing is not the same as no impact.

**The capacity *resource*: no. It does not fail over, and nothing in its contract offers to.**

- The ARM/Bicep schema (row 8) has no zone, replica, geo-pair or failover property in any listed API version. The only thing a template can declare about continuity is nothing.
- The create flow (row 7) asks for one **Region**. There is no "zone-redundant" or "geo-redundant capacity" choice to make.
- The recovery runbook's step 1 is: **"Create a new Fabric capacity in any region after a disaster. Given the high demand during such events, select a region outside your primary geo to increase the likelihood of compute service availability."** A resource that must be recreated in a new region on another continent is not a resource with failover; it is a resource with a rebuild instruction.
- The capacity is also tethered to the tenant's home region: "the core service functionality is tethered to the home region", and "For customers affected by a disaster and whose home regions don't have an Azure paired region that supports Fabric, the ability to utilize Fabric capacities might be compromised, **even if the data within those capacities is replicated**."

That last sentence is the crux of "capacity survives region loss": **no**. Data may survive; the capacity is gone and the home region gates your ability to stand a new one up.

### 3. OneLake durability — documented, and fixed for you

- **Redundancy is chosen by region, not by you.** "OneLake uses zone-redundant storage (ZRS) where that storage type is available … Elsewhere, OneLake uses locally redundant storage (LRS)." Replicated verbatim in the OneLake overview. There is no setting, no SKU, no template property.
- **The durability numbers are about hardware, not regions.** "LRS provides at least 99.999999999% (11 nines) durability of objects over a year. This durability helps protect against server rack and drive failures, **but not against datacenter disasters**." ZRS is "12 nines" and survives a datacenter failure — still inside one region.
- **Cross-region copy exists but is opt-in, per capacity, and time-locked.** "If your capacity has DR enabled, your data is duplicated and stored in two geographic regions so that it's geo-redundant. The standard region pairings in Azure determine the choice of the secondary region. **You can't modify the secondary region.**" The switch is capacity-admin only, capacity-granular, "doesn't influence your data stored outside OneLake", and "Once you change the disaster recovery capacity setting, you must wait 30 days before you can alter it again."
- **It is not available everywhere.** "some regions don't have an Azure pair region, or the pair region doesn't support Fabric. For these regions, data replication isn't available." The region matrix (row 5) shows the same hole from the other direction for Sweden Central.
- **The copy is not point-in-time.** "Data replication to the secondary region is asynchronous and occurs at the file level. As a result, a regional failover **can result in data loss and inconsistencies between files**. The secondary region might not contain a point-in-time-consistent copy of the data. For example, a newer file might be present while an older file that didn't yet replicate is missing."

So OneLake's answer to "what happens if the region is lost" is: 11 or 12 nines *within* a region depending on where you happen to be, plus an asynchronous, possibly-inconsistent, opt-in copy — and only if geography cooperates.

### 4. Service-level commitments

| Commitment | Exists? | Exact text | Covers |
| --- | --- | --- | --- |
| Fabric estate SLA percentage | **Not in any Fabric page I read** | — | — |
| SLA document | Yes, as a `.docx` | "describe Microsoft's commitments for uptime and connectivity for Microsoft Online Services" (row 20) | uptime and connectivity |
| Pipeline SLA | Yes | "The SLA for pipelines in Fabric is equivalent to the SLA for pipelines in Azure Data Factory: 'Microsoft guarantees that it successfully processes requests to perform operations against Data Factory resources at least 99.9 percent of the time. It also guarantees that all activity runs initiate within four minutes of their scheduled execution times at least 99.9 percent of the time.'" | operation processing and start latency, per pipeline |
| Support response time | Yes | "Microsoft commits to an initial response time … but doesn't provide a direct SLA for support request resolution" | how fast a human replies |
| Previews | Excluded | "Previews are not included in the SLA for the corresponding Online Service" | — |
| RTO | **Only one soft sentence** | "The time it takes for failover to complete can vary, although it **typically takes less than one hour**." | service-side failover only |
| RPO | **None** | OneLake: "can result in data loss and inconsistencies"; no number, no bound | — |

**Is there a documented RTO/RPO?** No. And the negative has a wide base: the strings `RTO`, `RPO`, `recovery time objective` and `recovery point objective` do not appear in rows 1, 2, 3 or 5 at all (checked by full-text search of the rendered pages on 2026-11-12). What exists instead, and is easy to mistake for an RTO:

- **"typically less than one hour"** — failover *of the service*, not recovery of your estate. It is followed immediately by a description in which Lakehouse, Warehouse, Notebook, Spark job definition, ML model, Dataflow, Pipeline, Eventstream and KQL items are all unavailable.
- **Power BI's numbers** — "approximately 15 minutes to become operational again after the decision is made", and "Such replications usually have a return point of 15 minutes, however, **Power BI can't guarantee a timeframe**." These are Power BI's, not Fabric's, and the page that carries them has no Fabric equivalent.
- **"15-minute targeted point-in-time sync for any content uploaded or changed in Power BI"** — the nearest thing to an RPO anywhere, scoped to Power BI metadata/content, hedged with "targeted".

The honest reading: **the only recovery time Microsoft commits to is the time for its own failover, and the only recovery point it commits to is none.**

### 5. What a customer must do — the pattern *is* documented

This is the part that contradicts the assumption that the note would be made of absence. There is a documented runbook, and it is detailed per item type (row 2 is 9,010 words). The shape:

**Prepare** — "Activate the disaster recovery capacity settings"; "Create data backups: Copy critical data stored outside of OneLake to another region". Note what is *not* in that list: nothing about the capacity resource, nothing about workspace IDs, nothing about permissions.

**During failover** — you wait, and cannot get in: "You can't access the Fabric portal until the failover is complete. A notification is posted on the Microsoft Fabric support page." Then: portal read-only, writes paused; Power BI reads work, refreshes and publishes do not; Lakehouse/Warehouse "you can't open these items, but you can access files through OneLake APIs or tools"; Notebooks "code content isn't saved after the disaster"; KQL databases and querysets inaccessible.

**Recover** — four documented steps: create a capacity "in any region"; create workspaces, "If necessary, use the same names as the old workspaces"; create items with the same names; then restore each item per its own section.

The per-item reality, from row 2, is the part a builder needs:

| Item | After failover | Documented recovery route |
| --- | --- | --- |
| Lakehouse | "remain unavailable to customers" | custom Scala/notebook copy from the original OneLake path, or Azure Storage Explorer; Delta metadata travels with the data, non-Delta tables need their DDL re-run |
| Warehouse | "You can't access warehouses from the original region" | interim lakehouse + T-SQL `INSERT INTO` / `SELECT INTO` / `CTAS`; code "versioned and saved in a safe location, such as Git" |
| Notebook | code "doesn't replicate to the secondary region" | Git integration ("Update all"), or import from a local copy; resource-explorer files and snapshots are *not* in Git |
| Spark job definition | main/reference files replicate; "Historical runs … aren't recovered" | recreate the item, copy `Libs`/`Mains`/`Snapshots`, re-enter command-line arguments by hand |
| Semantic model / report / dashboard | Power BI items readable in the paired region | read-only until the region returns; "export and backup operations don't work" during failover |
| Dataflow Gen2 | settings "don't replicate" | export `.pqt` template, import into a new item |
| Pipeline / Copy job / Airflow | configuration "isn't replicated" | Git, or rebuild by hand; "Build your critical pipelines in multiple workspaces across different regions" |
| KQL database / queryset | stored outside OneLake, so the switch does not cover it | "Configure two or more independent KQL databases … across two different Azure regions", mirror every management action, dual-ingest |
| Activator | trigger definitions don't replicate | "The standard Fabric failover process doesn't apply to Activator items"; Git only |
| Eventstream | no loss "as long as the destinations support disaster recovery" | rely on the destination; or active/active in two regions |
| SQL database in Fabric | "periodically export their data" | `.bacpac` via SqlPackage, stored in a *different* region |
| Mirrored catalog | no table data in OneLake, so DR does not apply | recreate the catalog in another region; no backfill of earlier data |
| Workspace identity, shares, schedules, run history, monitoring data, agent sessions | not replicated | recreate |

Two sentences from row 2 that bound the whole plan:

> "This recovery plan assumes that the tenant home region remains operational. If the tenant home region experiences an outage, the steps outlined in this article are contingent on its recovery, **which must be first initiated and completed by Microsoft**."

> "Before you start creating your disaster recovery plan …" — the article's own advice is to plan, not to expect.

**Is there a documented runbook for "capacity is gone, restore the estate"?** Not as a single artefact. What exists is a service-initiated regional-failover runbook plus a per-item catalogue. "Capacity deleted" is a different case with a different, narrower answer already established in [`workspace-and-item-lifecycle.md`](workspace-and-item-lifecycle.md) §4: items come back only if a workspace is reassigned to a same-region capacity within seven days, and the capacity resource itself is not recoverable.

### 6. Planned versus unplanned

They are documented on different pages, owned by different teams, and announced through different channels.

| | Planned maintenance | Regional disaster |
| --- | --- | --- |
| Documented in | row 11 (Power BI support) | rows 1–3 |
| Scope | "the service is temporarily unavailable for **all users and workloads across all license and SKU types**, including Power BI Embedded" | read-only portal, most items unavailable, OneLake data readable |
| Notice | "Microsoft 365 administrators … receive advance notification through the **Microsoft 365 Message center**" | "A notification is posted on the Microsoft Fabric support page" after the fact |
| Duration | a communicated start and end window; "often completed sooner" | "typically takes less than one hour" for failover, then unbounded rebuild |
| Customer action | refresh browsers, re-sign-in to mobile, re-run interrupted refreshes | the full recovery runbook in §5 |
| Appears in service health? | **No** — "Planned maintenance events aren't shown in service health" (row 14) | Not on Azure status or Service Health either (§7) |

The distinction matters operationally: maintenance is the only case with advance warning, and the warning arrives in a channel (Message center) that is not the one an on-call data engineer watches (Fabric support page / Azure status). Nothing in the Fabric docs promises a maintenance window at a particular time of day, only that Microsoft schedules "outside of standard business hours whenever possible".

### 7. Where an outage appears, and whether it is machine-readable

- **Fabric's own surface** is `support.fabric.microsoft.com/support/` — page title "Microsoft Fabric service status". The reliability article names it as *the* place a failover notice is posted. Observed on 2026-11-12: it is a Power Pages site whose notifications load from an internal `/fabric-json-subgrid/?serviceNotificationId=…` endpoint. **No Learn page documents an API, RSS/Atom feed or webhook for it.** This is a negative on the documented surface, not on the page's internals.
- **Azure Service Health does not cover Fabric on paper.** Row 15 never mentions Fabric, OneLake or Power BI. Row 14 lists the services in the Microsoft 365 admin center's Service health page and doesn't include Fabric either. Whether `Microsoft.Fabric/capacities` appears in **Resource Health** is unverified — no page I read lists it among supported resource types, and the ARM schema (row 8) offers no health signal beyond the resource itself.
- **Azure status does not list Fabric.** Row 16 contains seven "Fabric" strings, all "Azure Service Fabric". Anyone grepping a status feed for "Fabric" will match the wrong product and conclude the platform is healthy.
- **No Fabric known-issues page exists** at the two conventional paths (row 19, both 404). The roadmap (row 18) discusses features, not outages.

Conclusion: an outage is announced **after** the fact, on a community-style support site, in prose, with no documented machine-readable feed. Any alerting design has to treat "can't reach Fabric" as the signal, which is exactly what [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) already established for the metric surface.

### 8. What a builder can promise

| Promise | Safe to make? | Basis |
| --- | --- | --- |
| "Data at rest survives a disk or rack failure" | Yes | 11 nines LRS / 12 nines ZRS (row 3) |
| "Data survives a datacenter failure" | Yes, in ZRS regions | row 3; not in LRS-only regions |
| "Data survives region loss" | **Only if** DR was enabled, the region is paired, the pair supports Fabric, and you accept asynchronous loss | rows 1–3 |
| "We will lose no more than N minutes of data" | **No** — you cannot derive N from Microsoft; state your own backup cadence instead | §4 |
| "The estate is back within N hours" | **Only** if N comes from your own measured rebuild, not from the "less than one hour" sentence | §4, §5 |
| "The capacity keeps running if its region fails" | **No** | §2 |
| "Items keep working after failover" | **No** — only OneLake data over APIs keeps working | §5 |
| "Notebooks, pipelines, KQL and Activator are covered by the DR switch" | **No** — explicitly outside it | §5 |
| "We get an alert when Fabric is down" | Only by probing it yourself | §7 |
| "The SLA pays us back for an outage" | Only per the SLA document, which is uptime/connectivity and per-service | row 20; §4 |

Practical reading for this repo's operating model: the DR switch is **a capacity setting a pipeline could set** (it is capacity-admin gated, capacity-granular, and re-toggleable only every 30 days), but the rest of continuity is **not automatable** — item recovery is a per-type human procedure, and the pipeline's real contribution is keeping the Git side complete enough that "rebuild from Git" is possible. That is a design constraint on [`terraform-operating-model.md`](terraform-operating-model.md), not a new Terraform resource.

### 9. Contradictions worth quoting side by side

1. **"Guarantees data access" vs "data loss and inconsistencies".** Reliability: "In a regional disaster scenario, Fabric **guarantees data access**, with certain limitations." OneLake: failover "can result in data loss and inconsistencies between files … might not contain a point-in-time-consistent copy". Both can be true — *access* to whatever replicated, not *completeness* — but the first sentence alone will be read as a durability promise, and it is not one.
2. **"Might initiate a regional failover" vs "Microsoft Fabric initiates a regional failover".** OneLake: "OneLake **might** initiate a regional failover." Reliability: "When a major disaster makes the primary region unrecoverable, Microsoft Fabric initiates a regional failover." The modal verb differs between two pages about the same event; plan for either.
3. **Power BI BCDR always on vs not available.** Reliability: "BCDR for Power BI is always supported, regardless of whether the switch is on or off." Region matrix, Sweden Central: "Not available by default for Power BI: Business Continuity Disaster Recovery (BCDR). Power BI is supported in the region but not in its paired region." The second is the truthful one for that region.
4. **"Tenant setting" vs capacity setting.** The DR switch is described as capacity-granular and capacity-admin gated, but its screenshot is captioned "Screenshot of the disaster recovery **tenant** setting." Automation must target the capacity, not a tenant switch; the caption is a documentation slip that a reader could act on.

## What this settles

- A capacity has **zone redundancy for the workload** and **no failover for the resource**. There is no property, SKU or portal option that makes a capacity survive region loss; the documented recovery is to create a new one elsewhere.
- OneLake redundancy is **fixed by region** (ZRS where available, else LRS) and **not customer-selectable**; cross-region copy is an **opt-in per-capacity switch** limited to Azure-paired, Fabric-supported regions, with a 30-day re-toggle lock and separately billed storage and operations.
- **No Fabric page publishes an RTO or an RPO.** The only duration is "typically takes less than one hour" for the service's own failover. Power BI publishes ~15 minutes and explicitly "can't guarantee a timeframe"; those numbers are not Fabric's.
- The only SLA *number* in Fabric docs is **99.9% for pipeline operation processing and 4-minute start**, inherited from Azure Data Factory. The estate SLA lives in a `.docx` that Microsoft describes as covering "uptime and connectivity".
- A documented **per-item recovery runbook exists** and is 9,000 words deep — but it recovers *data and definitions*, assumes the home region is alive, and leaves notebooks, pipelines, KQL, Activator, mirrored catalogs and all identity/permission state to the customer.
- **Planned maintenance and regional disaster are different products' pages** with different notice channels; neither appears in Azure Service Health, and Microsoft Fabric is not on the Azure status page at all.
- A defensible customer promise is: measured rebuild time, own backup cadence, and DR switched on for regions where it exists — with the failure modes named.

## What this does not establish

- **The text of the Fabric SLA.** The agreement is a Word document behind `aka.ms/CSLA`; the host returns 403 to scripted clients and this environment cannot unzip a binary. Whether it names Fabric separately, what percentage applies, and whether it contains any durability or recovery clause are **unread**. Treat any statement here about the SLA as being about Microsoft's one-line description of the document.
- Whether `Microsoft.Fabric/capacities` appears in **Azure Resource Health**, and therefore whether a capacity-level health signal exists at all. No page I read lists it.
- Whether the **DR switch is available in the work tenant's capacity region** — it depends on the region pair and on Fabric's presence in the paired region, both tenant facts.
- The **actual replication lag** for a given estate. The docs say asynchronous and file-level; they give no bound, and the Power BI "15-minute targeted" figure is not stated to apply to OneLake.
- Whether a **restored/rebuilt workspace keeps its ID**, and what happens to workspace identity, shares and Git binding after a regional rebuild. §5 says recreate and re-share; it does not say what survives.
- **Cost of BCDR at a given volume.** The rate table (row 9) is public; the estate's write volume is not.
- Whether the **Git-integration coverage** matches this estate's item mix — [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) answers that for deployment, and DR leans on the same mechanism.
- Any statement about **failback**. The docs describe returning to normal ("Power BI service instances return to their original region when the issue … is resolved") but give no runbook for reconciling data written in the recovery region; the SQL and HorizonDB sections say only that you must "manually reconcile".

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [rel] | zones, DR switch semantics, failover expectations, four recovery steps, home-region tethering, "less than one hour" | ms.date 2025-09-19, upd. 2026-08-05 |
| [exp] | per-item replication and recovery, Git-only items, KQL/Activator exemptions, home-region dependency | ms.date 2026-11-11, upd. 2026-11-12 |
| [oldr] | LRS/ZRS choice, 11/12 nines, geo-replication, non-point-in-time admission, soft delete | ms.date 2026-03-11, upd. 2026-11-02 |
| [olo] | restatement of built-in redundancy and BCDR opt-in | ms.date 2026-03-09, upd. 2026-11-02 |
| [reg] | region matrix, Sweden Central BCDR gap | ms.date 2026-11-03, upd. 2026-11-05 |
| [caps] | "Disaster Recovery" row in capacity Details; capacity-delete soft delete | ms.date 2026-03-06, upd. 2026-09-29 |
| [buy] | create flow has Region and Size only | ms.date 2026-08-27 |
| [arm] | `Microsoft.Fabric/capacities` schema; no redundancy property | ms.date 2024-12-09, upd. 2026-10-20 |
| [cons] | BCDR storage and transaction billing | ms.date 2026-09-21, upd. 2026-09-29 |
| [pbf] | 15-minute sync, ~15 min regional failover, "can't guarantee a timeframe", read-only mode | ms.date 2026-06-02, upd. 2026-06-03 |
| [pm] | full-service maintenance window, Message center notice | ms.date 2025-10-01, upd. 2026-10-07 |
| [df] | pipeline SLA = ADF 99.9% and 4-minute start | ms.date 2026-08-05 |
| [sup] | support response vs resolution | undated |
| [m365sh] | M365 service health scope; planned maintenance not shown | ms.date 2026-02-09, upd. 2026-10-30 |
| [ash] | Azure Service Health overview; no Fabric mention | ms.date 2025-10-31 |
| [status] | Azure status lists only "Azure Service Fabric" | live 2026-11-12 |
| [fabsupport] | "Microsoft Fabric service status"; failover notice surface | live 2026-11-12 |
| [rm] | roadmap has no outage/disaster content | live 2026-11-12 |
| [slahub] | SLA described as "uptime and connectivity"; November 2026 `.docx` | November 2026 |
| [terms] | previews excluded from SLA; `aka.ms/CSLA` | undated |

[rel]: https://learn.microsoft.com/en-us/fabric/security/reliability-fabric
[exp]: https://learn.microsoft.com/en-us/fabric/security/experience-specific-guidance
[oldr]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-disaster-recovery
[olo]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-overview
[reg]: https://learn.microsoft.com/en-us/fabric/admin/region-availability
[caps]: https://learn.microsoft.com/en-us/fabric/admin/capacity-settings
[buy]: https://learn.microsoft.com/en-us/fabric/enterprise/buy-capacity
[arm]: https://learn.microsoft.com/en-us/azure/templates/microsoft.fabric/capacities
[cons]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-consumption
[pbf]: https://learn.microsoft.com/en-us/power-bi/enterprise/service-admin-failover
[pm]: https://learn.microsoft.com/en-us/power-bi/support/service-planned-maintenance
[df]: https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-overview
[sup]: https://learn.microsoft.com/en-us/power-bi/support/service-support-options
[m365sh]: https://learn.microsoft.com/en-us/microsoft-365/enterprise/view-service-health
[ash]: https://learn.microsoft.com/en-us/azure/service-health/overview
[status]: https://azure.status.microsoft/en-us/status
[fabsupport]: https://support.fabric.microsoft.com/support/
[rm]: https://learn.microsoft.com/en-us/fabric/release-plan/
[slahub]: https://www.microsoft.com/licensing/docs/view/Service-Level-Agreements-SLA-for-Online-Services
[terms]: https://www.microsoft.com/licensing/terms/product/ForallOnlineServices/EAEAS

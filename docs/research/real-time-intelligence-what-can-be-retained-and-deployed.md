# What can be retained and deployed as code in Real-Time Intelligence, and what does a capacity-observability store actually require?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** [ADR 0009](../adr/0009-observability-is-event-sourced.md)'s retention and store choice; the capacity review's data source in [spec 0002](../specs/0002-platform-operations.md)

## Short answer

A quarter is not merely feasible, it is *well below the default*: a KQL database's data retention
policy accepts **1 to 36,500 days** and defaults to **3,650 days**, and — unlike a Lakehouse table —
the retention period, the caching period and the table schema all travel inside the deployable item
definition. The Eventhouse is the right store for this shape, but **not for the reason ADR 0009
gives**: 30-second summaries are a couple of thousand rows a day, so ingestion volume is irrelevant.
What a second capacity actually pays for is the *continuous baseline* — a trickling stream keeps an
autoscaled engine active and an Eventstream charged by the hour — about **3 CU-hours per hour**, which
is more than one F2 and most of an F4.

## Detail

### 0. Surface, and how far these claims go

Everything below is read from Microsoft Learn on 2026-11-12; each page's own last-updated date is in
[Sources](#sources). Two limits apply throughout:

- **Nothing was executed.** Where a value is documented but not shown in a tenant (SKU minimums,
  whether a policy command survives a definition round-trip), it is marked as unestablished rather
  than stated.
- **"Not possible" claims name the surface searched.** Where a page is absent rather than negative,
  the note says which pages were read.

### 1. Retention: exact names, permitted values, defaults

Two different policies are in play, and ADR 0009 mentions only the first.

| Policy | Object and property | Permitted | Default |
| --- | --- | --- | --- |
| **Data retention policy** | database- or table-level `RetentionPolicy` with `SoftDeletePeriod` (+ `Recoverability`) | portal: **minimum 1 day, maximum 36,500 days**, or **Unlimited**; engine default policy object is `365000.00:00:00` (1,000 years) | **3,650 days** in the KQL database UI; `SoftDeletePeriod` "defaults to 1,000 years" per the Kusto reference |
| **Caching policy** | database-, table- or materialized-view-level; UI field is the caching period, engine property is `DataHotSpan` in the `CachingPolicy` object | must be **lower than or equal to** the retention period | **3,650 days** in the UI; engine default is `null`, "which means that all the data is considered **hot**" |

Exact UI path, so automation targets the real thing: **KQL database → Manage → Data policies**, with
**Retention** and **Caching** panes, each offering a toggle to **Unlimited** or a duration. Management
commands are `.alter policy retention` / `.show policy retention` and the caching equivalents
`.alter-* cache policy`; the database-level form is
`.alter-merge database <db> policy retention softdelete = 90d`.

Three consequences that matter more than the numbers:

- **The ADR's premise is about the wrong database.** "Workspace monitoring's KQL database defaults to
  30 days" is true of the **Monitoring Item** created by workspace monitoring — a product-chosen
  default for a read-only telemetry database. A KQL database you create in an Eventhouse defaults to
  **ten years**. The capacity-events store is the second kind, so a quarter needs no rescue.
- **The real risk is the opposite direction.** "The failure is silent — old windows simply disappear"
  describes a retention set too short. With the defaults left alone the silent failure is that old
  windows *never* disappear, at premium cache rates (§2). Deploying an explicit retention is still
  right, but the reason is cost, not data loss.
- **Retention alone is the wrong knob.** Retention sets what is *queryable*; caching sets what is on
  local SSD. Leaving caching at its default keeps effectively every retained byte hot, and cache size
  is one of the inputs that sizes the cluster (§3).

**Documented contradiction, recorded rather than resolved.** The Fabric page gives a 3,650-day default
and a 36,500-day maximum; the Kusto reference (same page family, Fabric moniker) gives a 1,000-year
default and shows `365000.00:00:00` as the default policy object; the KQL-database definition example
uses `P365000D` (1,000 years) for `oneLakeStandardStoragePeriod`. The likely reading is that the
Fabric portal caps and pre-fills differently from the engine default, but no page says so. For a
90-day target the ambiguity is harmless — every reading permits it — and it is the ambiguity, not the
limit, that a tenant would settle.

### 2. What retention actually costs

Storage and compute are metered separately, and the split is the whole answer.

- **Storage is not CU.** Fabric bills OneLake storage in **GB per month**, outside capacity units, on
  separate meters: `OneLake Storage (Hot, Cool, Cold)`, `OneLake BCDR Storage (Hot, Cool, Cold)`,
  `OneLake Cache`. KQL data occupies two of these tiers: **OneLake Standard Storage** (persist and
  store all queryable data; "when you set the retention policy, you affect this storage tier") and
  **OneLake Cache Storage** (premium, SSD-backed; "when you set the cache policy, you affect this
  storage tier", "comparable to the Azure ADLS premium tier").
- **Compute is CU, and retention barely moves it.** The only Eventhouse operation in the billing
  tables is **`Eventhouse UpTime`** — "the number of seconds that your eventhouse is active in
  relation to the number of virtual cores used". There is no per-GB ingestion meter for Eventhouse;
  ingestion shows up as UpTime.
- **So a long retention is cheap and a long *cache* is not.** With caching pinned to, say, 30 days and
  retention to 400, the extra 370 days sit in standard storage at single-digit GB (see §6) and cost
  pennies; with caching left at its default, every retained byte is premium cache *and* can force a
  larger cluster to hold it. That is the sentence ADR 0009 is missing.
- **Capacity Planner changes the arithmetic.** With a scheduled minimum configured, "you aren't
  charged for *OneLake Cache Storage*" — cache cost is folded into the guaranteed baseline. That
  makes Capacity Planner the sane configuration for an always-fed monitoring Eventhouse, and it makes
  the "2 CU minimum" in §3 a real number rather than a floor on top of cache charges.

### 3. Cost shape of the whole path, and why a second capacity is still right

Operations and rates as documented (CU-hours):

| Item | Operation (as named in the metrics app) | Rate |
| --- | --- | --- |
| Eventhouse | `Eventhouse UpTime` | virtual cores × seconds active; **default minimum 2 CUs** when a minimum is scheduled, minimum capacity is 2 CUs / 25 GB SSD |
| Eventstream | `Eventstream Per Hour` | **0.222 CU hours per hour**, "charged only when it's active (that is, events are flowing in or out)"; no charge after two hours with no traffic |
| Eventstream | `Eventstream Processor Per Hour` | **starts at 0.778 CU hours** per hour at `Low` throughput, autoscales |
| Eventstream | `Eventstream Data Traffic Per GB` | 0.342 CU hours per GB (irrelevant at this volume) |
| Activator | `RTI Event Listener and Alert` / event listener | 0.0222 CU hour per hour per listener (from the existing monitoring note) |
| Lakehouse (alternative) | OneLake write operations | per-transaction CU; no always-on engine |

Arithmetic for one capacity's events on one monitoring capacity, per month (730 h):

- Eventstream flat + processor at `Low` ≈ **1.0 CU-hour/hour → ≈730 CU-hours/month**, and a
  30-second stream means traffic never stops long enough for the two-hour idle exemption.
- Eventhouse at its 2-CU default minimum ≈ **1,460 CU-hours/month**.
- Activator listener ≈ **16 CU-hours/month**.
- **Total ≈ 2,200 CU-hours/month ≈ 3 CUs continuously.**

Set that against the SKUs: F2 = 2 CUs, F4 = 4 CUs. **An F2 cannot hold this path** — the Eventhouse
baseline alone is the entire SKU — and **F4 is the practical floor**, leaving roughly one CU of
headroom for the weekly review's queries before smoothing pushes the capacity into throttling. This is
the correction ADR 0009 needs: "the smallest SKU that can host an Eventstream and its ingestion" is not
F2. The docs also disagree on the floor — the Eventstream overview says "use the Fabric eventstreams
feature with at least four capacity units: F4", while the Eventstream consumption page says
eventstreams "can operate with the smallest *F* capacity" — so F4 is the only figure consistent with
both pages, and the tenant is the last word.

The ADR's *conclusion* survives this: monitoring that consumes a continuous 3 CUs would be a third of
a shared F8 and would be throttled at exactly the moment the estate is throttled, so isolating it is
right. Its *reason* does not: the cost is a fixed baseline, not ingestion volume. Which also means the
cost is not reducible by keeping less data or ingesting less often — only by not running the store, or
by choosing a store with no always-on engine (§5).

One more lever worth naming: an Eventhouse "is designed to optimize cost by suspending the service when
not in use" but reactivation costs "a few seconds", and Capacity Planner mode ("previously known as
*Always-on*") exists to stop that suspension. A 30-second feed will keep the engine active by
construction; **whether the engine ever suspends between windows is not documented** — that is an
inference from the suspension design, not a stated inactivity threshold.

### 4. Deployment as code: what each definition actually carries

This is where Eventhouse beats every other candidate store, and the answer is unusually clean.

| Item | Definition parts | What it carries | Gap |
| --- | --- | --- | --- |
| **Eventhouse** | `EventhouseProperties.json`, `.platform` | **nothing** — "There aren't any properties described in the Eventhouse, so an empty object is given" (`{}`) | none in practice: the container holds no configuration |
| **KQL database** | `DatabaseProperties.json`, `DatabaseSchema.kql`, `.platform` | `databaseType` (`ReadWrite` only), `parentEventhouseItemId`, **`oneLakeCachingPeriod`**, **`oneLakeStandardStoragePeriod`** (ISO 8601 spans, e.g. `P36500D`); the `.kql` part "defines the tables, functions, materialized views, and more" | whether `.alter … policy retention` statements survive inside `DatabaseSchema.kql` is implied by "and more" and **not established** |
| **Eventstream** | `eventstream.json`, `eventstreamProperties.json`, `.platform` | full topology: `sources`, `destinations` (Lakehouse, Eventhouse, Reflex, others), `operators`, `streams`; `retentionTimeInDays` **1–90**, default 1; `eventThroughputLevel` `Low`/`Medium`/`High` | connection references (`dataConnectionId`) are environment-specific; whether the **capacity overview events** source is representable in `eventstream.json` is **not established** |
| **Activator (Reflex)** | definition API ✅ per the deployment-coverage note | rules | **service principal ❌**, so the alerting half is not headlessly deployable today |
| **Monitoring Item** (workspace monitoring) | *none* | — | a workspace setting, destination fixed at creation, not an item definition |

Practical consequences:

- **The store is deployable with its policy and its schema.** Retention and caching are two ISO-8601
  strings in `DatabaseProperties.json`; table DDL is a text file applied as management commands. This
  is strictly better than Warehouse and Lakehouse, where the repo has already established only the
  shell deploys.
- **`fabric-cicd` supports all three items**, with two caveats worth writing into the work repo: the
  `exclude_path` variable "is required when deploying an **Eventhouse** that is attached to a **KQL
  Database** (common scenario)", and a KQL database "is not a standalone item… its source control files
  are located within a `.children` folder under the directory of the attached eventhouse". A naive
  item-type-in-scope list deploys the database twice or not at all.
- **The Eventhouse item being empty is not a gap.** It is the KQL database that owns schema and policy,
  so there is nothing the container should carry.

### 5. The alternative store, honestly compared

Eventstream destinations, confirmed on the overview page: **Custom endpoint (custom app)**, **Eventhouse**,
**Lakehouse**, **Spark Notebook (preview)**, **Derived stream**, **Activator**. So "Eventstream → Lakehouse
table (Delta)" is a first-class, GA-looking destination — the wiring is not the obstacle.

| Dimension | Eventhouse | Lakehouse table |
| --- | --- | --- |
| **Retention control** | a policy: one value, enforced by the engine, deployable in the definition | **no retention or TTL policy documented.** Expiry is a `DELETE` + `VACUUM` + `OPTIMIZE` job you write and schedule; `VACUUM`'s default threshold is 7 days and portal/API maintenance "fail by default for retention intervals under seven days" |
| **Schema as code** | yes — `DatabaseSchema.kql` | **no** — `fabric-cicd`: "Schemas are not deployed"; table schemas and folder structure are not source-controlled at all |
| **Query ergonomics** | KQL window functions and `summarize … by windowStartTime` are the natural shape for 30-second windows | SQL analytics endpoint (billed as `SQL Endpoint Query`, Data Warehouse CU) or Spark (Memory Optimized CU); both fine, neither cheap per query |
| **Dedupe** | one clause: `summarize take_any(*) by windowStartTime, windowEndTime, capacityId` | duplicates land as rows; dedupe at read or a `MERGE` you maintain |
| **Ingestion latency** | direct ingestion, near-real-time | batched by **minimum rows** / **maximum duration** (**1 minute to 2 hours**), producing many small files that need compaction |
| **Steady compute cost** | UpTime floor — ~2 CUs continuous | no engine floor; OneLake write operations + storage only |
| **Failure mode during an incident** | engine throttles with the capacity it sits on | nothing to throttle, but an Eventstream writing into it still occupies the shared capacity |

**Verdict: keep the Eventhouse, but argue it on the right axis.** For a store whose job is to be
*trustworthy while the estate is unhealthy*, three properties are worth more than two continuous CUs:
retention that cannot be forgotten, a schema that cannot drift, and dedupe that is one clause rather
than a job. A Lakehouse would save the UpTime baseline (≈1,460 CU-hours/month) and pay for it with a
second thing to operate — an expiry job and a compaction job, both of which are exactly the kind of
"silent when it stops working" automation that this whole ADR exists to avoid.

What *would* change the decision is a refusal of the second SKU rather than a technical fact: if the
store must live on the shared capacity, a **Lakehouse destination is the cheaper degradation** — no
engine floor, no second SKU, at the cost of retention and schema becoming code, and a write path that
still consumes the shared capacity's Eventstream CU.

### 6. Volumes — is this trivial?

`Capacity.Summary` is one row per 30-second window per active capacity, suppressed when all values are
zero and not emitted while paused:

| Horizon | Rows per capacity | At ≤1 KB/row, uncompressed |
| --- | --- | --- |
| Day | 2,880 | ~3 MB |
| Quarter (91 days) | ~262,000 | ~260 MB |
| Year | ~1,051,000 | ~1 GB |
| 10 years (the UI default) | ~10.5M | ~10 GB |

Trivial for both candidates, and KQL's columnar compression cuts this by roughly an order of
magnitude. The useful conclusion is the *negative* one: at every horizon a capacity review cares
about, **storage is a rounding error and compute is the entire bill** — so "keep a quarter" versus
"keep a year" is not a cost decision, while "run an always-on engine" versus "do not" is.

## What this settles

- **A quarter of retention is feasible, unremarkable, and cheap.** Permitted range 1–36,500 days,
  default 3,650 days, or `Unlimited`. A 90-day target needs one value in one deployable file.
- **The retention risk in ADR 0009 is mis-stated.** The 30-day figure belongs to the workspace
  monitoring Monitoring Item; a self-created KQL database defaults to ten years. The silent failure to
  guard against is ten years of *premium cache*, not ninety days of vanished history. Set **both**
  retention (long) and caching (short), and prefer Capacity Planner so cache becomes part of the
  baseline.
- **Retention costs storage (GB-month, outside CU); compute costs CU.** `Eventhouse UpTime` is the only
  Eventhouse compute operation, billed per virtual-core-second while active.
- **The second capacity is justified by a ~3 CU continuous baseline**, not by ingestion volume —
  Eventstream flat + processor ≈1 CU-hour/hour, Eventhouse minimum ≈2 CU, Activator ≈0.02 CU. That
  makes **F4 the practical floor** and F2 unusable for this path, whatever the ADR's "smallest SKU"
  phrasing implies.
- **Deployment as code covers this store almost completely**: the KQL database definition carries
  schema *and* `oneLakeCachingPeriod`/`oneLakeStandardStoragePeriod`; the Eventhouse definition carries
  nothing and needs nothing; the Eventstream definition carries the destination topology. The gaps are
  Activator (no service principal) and any hope of deploying the Monitoring Item, which is a workspace
  setting.
- **Eventhouse is the right store for this shape** — chosen for retention-as-policy, schema-as-code and
  one-clause dedupe — and a Lakehouse is the cheaper but more fragile fallback if the second SKU is
  refused.

## What this does not establish

- **Whether `.alter table … policy retention` survives inside `DatabaseSchema.kql`.** The definition
  page says the `.kql` part defines "tables, functions, materialized views, and more"; it does not
  enumerate policies, and no page shows a policy command in a deployed schema script. Database-level
  periods in `DatabaseProperties.json` are the documented lever; table-level policies are not.
- **The true default retention of a freshly created KQL database.** Three pages give three answers
  (3,650 days / 1,000 years / `P365000D` in an example). All permit a quarter; which one a tenant
  actually gets is a one-command check (`.show database <db> policy retention`).
- **Whether an F2 genuinely hosts this path.** The docs conflict on the Eventstream floor (F2 vs F4),
  and nothing documents the Eventhouse's inactivity threshold before it suspends. F4 is the defensible
  planning figure, not a measured one.
- **Real CU consumption of a 30-second trace.** The ~3 CU/hour figure is arithmetic from published
  rates and a documented 2-CU minimum, not a measurement; autoscale size, cache size and query load all
  move it.
- **Whether the capacity overview events source can be expressed in `eventstream.json`.** The definition
  schema lists `sources` generically and shows an Azure Event Hub example; the capacity-events source
  type is not shown, so assume the Eventstream is created once by hand in flow 1 and only *re-deployed*
  once its shape is known.
- **Whether the OneLake copy made by OneLake availability ages out with the retention policy.** If it
  does not, "write to Eventhouse, read Delta from a Lakehouse shortcut" would give cheap long-term
  history without a second store — a possibly better architecture that this note cannot confirm.
- **Cool/cold OneLake tiers for KQL data.** The storage meters include `OneLake Storage (Cool, Cold)` and
  a `OneLake Data Retrieval` meter, but no page states that a KQL database's standard storage can be
  tiered, or what retrieval costs on a query.
- **Anything about this tenant's actual SKU behaviour, throttling smoothing, or OneLake spend** — all
  four need a tenant.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Change data policies in Real-Time Intelligence](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-policies) | Retention 1–36,500 days, default 3,650, `Unlimited`, caching ≤ retention, `Manage > Data policies` | 2026-03-22 |
| [Retention policy (Kusto, Fabric moniker)](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/retentionpolicy?context=/fabric/context/context&pivots=fabric) | `SoftDeletePeriod` / `Recoverability`, 1,000-year default, `365000.00:00:00`, `.alter`/`.show` commands, imprecise deletion | 2026-05-10 |
| [Caching policy (hot and cold cache)](https://learn.microsoft.com/en-us/kusto/management/cache-policy?view=microsoft-fabric) | `DataHotSpan`, default `null` = all data hot, independence from retention, SSD sizing | 2026-03-17 |
| [Eventhouse and KQL database consumption](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/real-time-intelligence-consumption) | `Eventhouse UpTime` definition and example, OneLake Cache vs Standard Storage, storage billed separately | 2026-06-16 |
| [Eventhouse cost per GB ingested](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/pricing-cost-drivers) | Retention/cache as cost drivers, cache size sizing the cluster, streaming vs queued ingestion | 2026-02-25 |
| [Schedule Eventhouse capacity](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/eventhouse-smart-capacity-control) | 2-CU default minimum, 25 GB per 2 CU, Capacity Planner mode and cache charges | 2026-10-08 |
| [Eventhouse overview](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/eventhouse) | Suspends when not in use, few-seconds reactivation, Capacity Planner | 2026-11-08 |
| [Fabric operations](https://learn.microsoft.com/en-us/fabric/enterprise/fabric-operations) | Billing operations per item: `Eventhouse UpTime`, four Eventstream operations | 2026-10-29 |
| [Eventstreams capacity consumption](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/monitor-capacity-consumption) | 0.222 / 0.778 / 0.342 rates, two-hour idle exemption, "smallest F capacity" | 2026-09-29 |
| [Azure billing for a Fabric capacity](https://learn.microsoft.com/en-us/fabric/enterprise/azure-billing) | Storage meters in GB/month (`OneLake Storage`, `OneLake Cache`, `OneLake Data Retrieval`) vs consumption meters in CU | 2026-10-13 |
| [Eventstreams overview](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/overview) | Destination list, F4 note, 90-day maximum event retention, at-least-once | 2026-11-11 |
| [Add a lakehouse destination](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/add-destination-lakehouse) | Delta output, schema enforcement on first record, minimum rows / maximum duration 1 min–2 h, small-file optimisation | 2026-06-15 |
| [Delta table maintenance](https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-table-maintenance) | No TTL: `VACUUM` threshold 7 days, `OPTIMIZE`/V-order, maintenance via notebook/pipeline | 2026-09-09 |
| [Eventhouse item definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/eventhouse-definition) | `EventhouseProperties.json` is `{}` | 2024-11-13 |
| [KQL database item definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/kql-database-definition) | `DatabaseProperties.json` fields incl. `oneLakeCachingPeriod`, `oneLakeStandardStoragePeriod`; `DatabaseSchema.kql` | 2024-11-13 |
| [Eventstream item definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/eventstream-definition) | `sources`/`destinations`/`operators`/`streams`, `retentionTimeInDays` 1–90, `eventThroughputLevel` | 2025-05-18 |
| [`microsoft/fabric-cicd` — Item Types](https://microsoft.github.io/fabric-cicd/latest/reference/item_types/) | Eventhouse/KQL Database/Eventstream caveats: `exclude_path`, `.children` folder, Lakehouse "schemas are not deployed" | undated; read 2026-11-12 |
| [Understand Fabric licenses](https://learn.microsoft.com/en-us/fabric/enterprise/licenses) | SKU-to-CU table: F2 = 2 CU, F4 = 4 CU | 2026-11-10 |
| [`monitoring-and-alerting-surface.md`](monitoring-and-alerting-surface.md) | Workspace monitoring 30-day default, event cadence and fields, Activator listener rate | 2026-11-12 |
| [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) | Which of these items deploy through which route; Activator service-principal gap | 2026-11-11 |

# If the organisation already runs Power BI, what does adopting Fabric change and what does the estate inherit?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work tenant's launch sequencing, and the viewer-licence decision at cutover

## Short answer

Fabric does not migrate Power BI; it re-parents it. Workspaces, reports, semantic models, apps and refresh schedules stay where they are, and only three things genuinely move: the capacity a workspace is attached to, the billing behind that capacity, and the licence arithmetic of the people who *view* it. That last one is the surprise, because "view Power BI content with a Microsoft Fabric (Free) license" holds only on an **F64 or larger** capacity (or a **P** capacity) and fails on **F2** through **F32**. Authoring does not change on any SKU: creating Power BI items outside *My workspace* needs **Pro** or **PPU**.

## Detail

### 1. Workspaces

- "License mode is now called workspace type. This is a terminology change only; functionality remains the same" (licenses, ms.date 2026-06-15). **"Classic workspace" is not a term in the current documentation** — the documented axis is workspace type, split into *Power BI workspace types* (**Power BI Pro**, **Power BI Premium Per-User (PPU)**, **Power BI Embedded** (A SKUs)) and *Fabric workspace types* (**Fabric** (F SKUs), **Fabric Trial**, **Power BI Premium** (P SKUs)). Could not establish what "classic workspace" maps to.
- By default workspaces are created in the tenant's shared capacity, which "hosts all *My workspaces* and workspaces that use the Power BI Pro or Power BI Premium Per-User (PPU) workspace types". Any workspace — including *My workspaces* — can then be assigned to any capacity in the tenant (licenses).
- **What a workspace needs to host a Fabric item:** assignment to a capacity that supports Fabric workloads, which is an F SKU, a Trial capacity, or a P SKU with the Fabric switch enabled — on a P capacity "Microsoft Fabric items aren't enabled. To enable support for Microsoft Fabric items on your Power BI capacity, enable Microsoft Fabric" (licenses; fabric-switch, 2026-08-27). The tenant gate is **Users can create Fabric items**, which a capacity admin can override per capacity on **Delegated tenant settings** (fabric-switch).
- **Assigning a capacity does not move content.** Reassignment re-parents the workspace and its items as a unit: "The migration happens at the workspace level. Reassign each workspace from a P SKU capacity to an F SKU capacity. There's no tenant-wide flip" (premium-migration-how-to, 2026-07-22). Nothing is exported, re-uploaded or re-shared.
- **The reverse direction is restricted.** From Premium/Fabric back to Power BI Pro or PPU "you must remove all non-Power BI items and any Power BI items that can't be moved first"; Org app and Exploration cannot go to Pro or PPU, Datamart cannot go to Pro (portal-workspace-capacity-reassignment, 2026-01-30).
- **A deliberate asymmetry:** a **P** capacity admin "can effectively 'claim' any workspace in the organization", while an **F** capacity admin "**must** also be a **Workspace Admin** of that specific workspace" (same page). A migration run entirely by capacity admins works on P and stalls on F.

### 2. Licences — the viewer surprise

Exact per-user capability table (licenses):

| Capability | Free | Pro | PPU |
| --- | :-: | :-: | :-: |
| Access Microsoft Fabric web application | ✅ | ✅ | ✅ |
| Create Fabric capacity workspaces | ✅ | ✅ | ✅ |
| Create Power BI Premium / Pro workspaces | ❌ | ✅ | ✅ |
| Create, update, delete or manage Power BI items outside *My workspace* | ❌ | ✅ | ✅ |
| Create non-Power BI Fabric items in Fabric / Trial / Premium capacity workspaces | ✅ | ✅ | ✅ |
| Share non-Power BI Fabric items | ✅ | ✅ | ✅ |
| View Power BI items in Pro workspaces or Fabric workspaces below **F64** | ❌ | ✅ | ✅ |
| View in a **P** capacity or **F64+** with a workspace **Viewer** role | ✅ | ✅ | ✅ |

- **Viewer, moving Pro/PPU → Fabric:** on an **F64 or larger** capacity a **Fabric (Free)** licence plus the **Viewer** role is enough, so Pro licences can be removed. On **F2–F32** they cannot: "On **F2 through F32**, every viewer needs a Power BI Pro or PPU license" (premium-migration-faq, 2026-09-11). The troubleshooting table in premium-migration-how-to names the symptom exactly: "**Free users can't view reports anymore** — The new F SKU is F32 or smaller".
- **Viewer, moving P → F:** unchanged **only** if you keep the CU class. P1→F64, P2→F128, P3→F256, P4→F512, P5→F1024 (premium-migration-faq). Sizing down to save money is what breaks viewer access, not Fabric itself.
- **`Viewer` is load-bearing.** On a P or F64+ capacity, "If you have any other role on the workspace, you need a Pro or a PPU license" (licenses). Granting **Contributor** so someone can edit re-imposes the Pro requirement. Same rule in apps: "F SKUs smaller than F64 and all A SKUs require each consuming user to have a Pro, Premium Per User (PPU), or individual trial license to view Power BI content."
- **Authoring never relaxes.** "To create Power BI items in workspaces that aren't *My workspace*, you need a *Pro* license" (licenses). A Free user can create lakehouses, notebooks and warehouses but not reports or semantic models.
- **PPU does not buy Fabric.** "**Premium Per User (PPU) doesn't provision a Fabric capacity** … To use Fabric workloads beyond Power BI, you need an F capacity or a Trial Fabric capacity" (licenses). A PPU-only organisation cannot create non-Power BI items at all.
- One documented Free-user exception: with **Build** permission on a shared semantic model on F64+, a Free user can create a report in *My workspace*, but "can't share the report or save it to another workspace without a Pro or PPU license" (premium-migration-faq).

### 3. Capacities

- **P SKUs host Fabric workloads**, with the switch on: "Fabric workloads can run on an Azure F SKU capacity, an existing Power BI Premium P SKU capacity, or a Fabric trial capacity" (fabric-switch). The retirement is commercial, not technical: "Each P SKU subscription ends at the end of its current agreement term, and Microsoft no longer sells new P SKUs" (premium-migration-overview, 2026-07-22).
- **P→F mapping is by CU**, in the same region, at parity: `F64`=P1, `F128`=P2, `F256`=P3, `F512`=P4, `F1024`=P5 (licenses; premium-migration-faq). Mapping stops at P5.
- **A SKUs cannot host Fabric.** "Power BI Premium *P* SKUs support Microsoft Fabric. *A* and *EM* SKUs only support Power BI items" (licenses). A workspaces are a Power BI Embedded workspace type, and "Embedded licenses (EM, A) aren't affected" by the retirement (premium-migration-overview).
- What F adds beyond P: pause/resume, on-demand resize in place of P autoscale, per-second Azure billing and reservations, managed private endpoints, trusted workspace access, Azure Monitor, Cost Management — and Power BI Embedded "included with every F SKU" (premium-migration-overview; service-premium-what-is, 2026-06-15).

### 4. Access model

- **Workspace roles are extended, not replaced.** Four roles keep their names — **Admin**, **Member**, **Contributor**, **Viewer** — and Fabric "extend[s] the Power BI workspace roles by associating new Microsoft Fabric capabilities" (roles-workspaces, ms.date 2026-04-24). Assignment mechanics are unchanged: individuals or security groups, Microsoft 365 groups and distribution lists, nesting, highest role wins. Service principals can hold workspace roles.
- **RLS does not change with the capacity.** It is defined in the model and enforced per user: "RLS only restricts data access for users with **Viewer** permissions. It doesn't apply to workspace **Admin**, **Member**, or **Contributor** roles" (service-admin-row-level-security, ms.date 2026-05-13). Consequence for coexistence: anyone moved from Viewer to Contributor to "help with the launch" sees all rows. Also "Service principals can't be added to an RLS role", so an app authenticating as an SP gets no RLS filtering.
- **Apps and audiences ride along on a same-region reassignment:** "Workspaces are reassigned to the new capacity. Workspace apps, deployment pipelines, and Git integration continue to work" and "Workspaces keep their pipeline assignments and app configurations" (premium-migration-overview; premium-migration-faq). Whether individual app *audience* security-group membership is preserved is **not stated** — could not establish.
- **Item-level permissions are separate from workspace roles and are not carried by any pipeline.** Deployment pipelines explicitly do not copy "Permissions - For a workspace or a specific item", nor app content or settings (understand-the-deployment-process, 2026-09-24). Treat sharing as a manual, human-owned step.

### 5. Deployment and Git

- **The Git folder format is the PBIP format**, so existing Power BI content can join the same repo without a conversion step: a report folder holds `definition.pbir` + `report.json`; a semantic model folder holds `definition.pbism` + a `definition` folder of TMDL (source-code-format, ms.date 2025-12-15). PBIP is documented as "Source control ready" and lists Fabric Git integration as a deploy route (projects-overview, 2026-09-23).
- **Both Power BI item types are in preview in Git**, with exclusions. Report: "except reports connected to semantic models hosted in Azure Analysis Services, SQL Server Analysis Services, or reports exported by Power BI Desktop that depend on semantic models hosted in MyWorkspace". Semantic model: "except push datasets, live connections to Analysis Services, model v1" (intro-to-git-integration, ms.date 2026-09-01). Paginated report is `*.rdl`, also preview.
- **PBIRS does not join it.** Power BI Report Server is a separate on-premises product, still licensed via "a Fabric capacity reservation or SQL Server Enterprise Edition with Software Assurance" (premium-migration-overview), and "Power BI Projects is currently not supported in Microsoft Power BI Desktop version optimized for Power BI Report Server" (projects-overview). Its content stays outside Fabric Git; only paginated reports cross over, as RDL.
- Hard constraints: 25 MB maximum file size; commit caps of 25 MB (service principal) / 125 MB (user principal) on Azure DevOps and 50 MB on GitHub; sensitivity labels not supported for export; workspace cap 1,000 items; "Downloading a report/dataset as *.pbix* from the service after deploying them with Git integration is not recommended" (git-integration-process, 2026-06-15; source-code-format).
- **Fabric deployment pipelines** (the native kind) need "The workspace must reside on a Fabric capacity", cap at 300 items per deployment, do not support PBIR reports, and retired "semantic models that aren't upgraded to Enhanced Metadata" from 2026-02-12 (intro-to-deployment-pipelines, 2026-09-24).

### 6. What carries over on a capacity move, and what does not

Carries, same-region:

| Thing | Evidence |
| --- | --- |
| Reports, semantic models, dashboards | "Continue to work unchanged on F64 or larger capacities" (premium-migration-overview) |
| Refresh schedules, incremental refresh policies | "Semantic models, incremental refresh policies, and scheduled refresh schedules transfer with the workspace" (premium-migration-faq) |
| Deployment pipelines, apps, CI/CD | "Continue to work after a same-region reassignment … keep their pipeline assignments and app configurations" (premium-migration-faq) |
| Tenant settings, sensitivity label policies, sharing controls | "aren't tied to your capacity, so they carry over without changes" (premium-migration-faq) |
| Gateway bindings | "Most gateway configurations persist through reassignment, but you might need to update some" (premium-migration-how-to) |

Does not carry, or must be redone:

- **Datasource credentials** — a named failure mode: "refresh credentials need to be reauthorized after the workspace moved" (premium-migration-how-to). Plan a re-auth pass per semantic model.
- **Capacity-level settings** — capacity admins and workload settings (for example semantic model memory limits) are properties of the *new* capacity, not the workspace (premium-migration-faq).
- **In-flight work** — "When you move a workspace, all jobs related to items in the workspace get canceled" (portal-workspace-capacity-reassignment); "Active refreshes and queries can be interrupted at the moment of reassignment".
- **Cross-region only:** large storage format semantic models and *all* Fabric items. Both are recreated with a new GUID, so "reports that referenced the original model need to be rebound" (premium-migration-how-to). Same-region migration avoids this entirely.
- **Up to an hour** after reassignment before users can create Fabric items on the new capacity (premium-migration-how-to).
- **Endorsements, subscriptions, alerts: could not establish.** No page read states what happens to them on a capacity reassignment. Deployment pipelines are documented *not* to copy "Endorsement settings", "Refresh schedule", "Data source credentials" or "Role assignment" — do not read that list as the behaviour of a capacity move (understand-the-deployment-process).

### 7. The migration path, and the order for a Power BI team

Five documented stages: **Decide → Plan → Provision → Migrate and validate → Decommission and operate** (premium-migration-overview). Concretely, in dependency order:

1. **Baseline** CU consumption on the P capacity with the Microsoft Fabric Capacity Metrics app over 30–45 days; size from measured peaks, not from the P→F table alone (premium-migration-faq).
2. **Buy the F SKU before reassigning anything.** "Purchase the F SKU first, reassign and validate workspaces, and then cancel the P SKU" — cancelling first gives a 30-day grace period, throttling from day 31, and total rejection from day 91 (premium-migration-faq).
3. **Add capacity administrators on the new capacity before any workspace lands** (premium-migration-how-to, Step 2).
4. **Pilot one low-impact workspace** that has "at least one report, one scheduled refresh, and one gateway connection" (Step 3).
5. **Reassign** via Admin portal → **Capacity settings** → **Fabric capacity** → **Assign workspaces** → **Specific workspaces**, or the semantic-link-labs **Capacity Migration** notebook for bulk and for splitting one P SKU across several F SKUs (Step 4).
6. **Validate**: capacity name in workspace settings, reports load, scheduled refreshes succeed, gateways work, pipelines and apps still publish, item count matches the inventory — then watch the Metrics app for 24–48 hours (Step 5).
7. **Cancel the P SKU manually.** "P SKU cancellation is manual — Fabric doesn't automatically decommission your P SKU" (premium-migration-overview).

Two sequencing warnings a Power BI team will hit: reassign outside refresh windows, and re-check **Users can create Fabric items** before the launch rather than during it — it "doesn't affect existing Power BI reports, semantic models, dashboards, or refresh schedules", so it can be settled early with no blast radius (premium-migration-faq).

## What this settles

**Three things an existing Power BI tenant must change before a Fabric launch**

1. **The capacity and its billing** — buy the F SKU on Azure, register `Microsoft.Fabric`, add capacity admins, and re-create the workload settings the P capacity carried. The P SKU is then cancelled by hand; nothing does it for you.
2. **The viewer licence plan, recomputed against the target SKU** — Free + **Viewer** is legal only on **F64+** (or P). An **F2**–**F32** launch keeps a Pro/PPU requirement on every viewer, so a cost-driven size-down silently re-prices the whole audience.
3. **The *Users can create Fabric items* switch** — off for new customers by default, set on the tenant and optionally overridden per capacity. Without it a P capacity hosts no Fabric items at all, and no lakehouse can be created anywhere.

**Three things that carry over untouched**

1. **Tenant settings, sensitivity label policies and sharing controls** — not capacity-bound, so they survive verbatim.
2. **The identity and access model** — same four roles, same group mechanics, same app audiences, same RLS rules and the same rule that RLS applies only to **Viewer**.
3. **Reports, semantic models, refresh schedules, deployment pipelines and Git bindings** — content is re-parented, not migrated; on a same-region move the estate comes across without a rebuild.

## What this does not establish

- What "classic workspace" means in current terms — the phrase is absent from the pages read; the documented axis is workspace type.
- Whether app **audience** security-group membership survives a capacity reassignment (only "app configurations" is claimed).
- What happens to **endorsements, subscriptions and alerts** on a capacity move. Deployment pipelines are documented not to copy endorsement, refresh schedule, credentials or role assignment, but that is a different operation.
- Whether RLS role *membership* (as opposed to role definitions in the model) survives reassignment — the model transfers, membership is not mentioned.
- Any licensing rule for service principals — nothing here says whether an SP needs Free/Pro/PPU to create items.
- Behaviour in the trial capacity or the personal tenant; nothing was executed. All statements are documentation claims dated 2026-06-15 to 2026-11-10.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Understand Microsoft Fabric licenses and capacity](https://learn.microsoft.com/en-us/fabric/enterprise/licenses) | Workspace types, per-user capability matrix, F64 threshold, P/A/EM SKU scope, P→F CU table | 2026-06-15 (updated 2026-11-10) |
| [Enable Microsoft Fabric for your organization](https://learn.microsoft.com/en-us/fabric/admin/fabric-switch) | **Users can create Fabric items**, capacity override, what counts as Fabric-capable capacity | 2026-08-27 |
| [Workspaces in Microsoft Fabric and Power BI](https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces) | Workspace as item container, workspace type setting, 1,000-item limit | 2026-07-28 |
| [Roles in workspaces in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/roles-workspaces) | Four roles extended for Fabric capabilities; SPs assignable | 2026-04-24 |
| [Row-level security (RLS) with Power BI](https://learn.microsoft.com/en-us/fabric/security/service-admin-row-level-security) | RLS applies only to Viewer; SPs cannot hold RLS roles | 2026-05-13 |
| [Power BI Premium → Fabric migration overview](https://learn.microsoft.com/en-us/power-bi/support/premium-migration-overview) | P retirement, what changes/stays, five stages, cross-region rules, PBIRS licensing | 2026-07-22 |
| [Migration FAQ](https://learn.microsoft.com/en-us/power-bi/support/premium-migration-faq) | F2–F32 viewer rule, P→F mapping, carry-over of schedules and apps, tenant settings | 2026-09-11 |
| [Migrate workspaces from Power BI Premium to Fabric](https://learn.microsoft.com/en-us/power-bi/support/premium-migration-how-to) | Reassignment procedure, capacity admin prerequisite, validation list, credentials/gateway symptoms | 2026-07-22 |
| [Capacity reassignment restrictions](https://learn.microsoft.com/en-us/fabric/admin/portal-workspace-capacity-reassignment) | P vs F capacity-admin permission asymmetry, movable item types, workspace-type downgrade limits | 2026-01-30 |
| [What is Power BI Premium?](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-premium-what-is) | P vs EM subscriptions, SKU memory limits, PBIRS inclusion | 2026-06-15 |
| [Overview of Fabric Git integration](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration) | Report and semantic model support in preview, with exclusions | 2026-09-01 |
| [Git integration process](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process) | Commit size limits, sensitivity labels, .pbix download warning | 2026-06-15 |
| [Git source code format](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/source-code-format) | `definition.pbir`/`report.json`, `definition.pbism`/TMDL folder layout | 2025-12-15 |
| [Overview of Fabric deployment pipelines](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines) | Capacity requirement, 300-item cap, PBIR and Enhanced Metadata restrictions | 2026-09-24 |
| [The deployment pipelines process](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process) | Item properties copied vs not copied (permissions, schedules, credentials, endorsement) | 2026-09-24 |
| [Power BI Desktop projects (PBIP)](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-overview) | PBIP as the source-control format; not supported in the Report Server edition | 2026-09-23 |

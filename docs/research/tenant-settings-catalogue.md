# Which Fabric tenant settings are not harmless, and what does each one break or leak?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the "tenant settings to confirm with the work tenant's admin" run-book item, and the settings section of any deployment design

## Short answer

Beyond the four that gate service principals, roughly a dozen settings can stop a deployment and a second dozen
can let data out of a workspace without anyone granting access. The dangerous ones are not the feature toggles
(Copilot, maps, scorecards) but the *plumbing*: Git integration, XMLA, OneLake external access, public-internet
blocking and the export settings — most of which default to **on**, so they are never noticed until something
fails or leaks.

## Detail

Scope: the [tenant settings index](https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index) (ms.date
2026-08-28) and the group pages it links, read 2026-11-12. 57 settings catalogued of ~300; the four SP gates are
restated for completeness but their detail lives in
[`identity-service-principal-and-tenant-settings.md`](identity-service-principal-and-tenant-settings.md). The portal
grouping survives in the **Group** column, and a default the page does not state is written *not stated* — the SP
defaults were introduced "for new customers", so a remembered default is not evidence.

### A. Identity and automation gates

| Setting (exact) | Group | Default | What it changes | Why it matters |
| --- | --- | --- | --- | --- |
| **Service principals can create workspaces, connections, and deployment pipelines** | Developer settings | **Disabled for new customers** | Admits SPs to Create Workspace, Create Connection, Create Deployment Pipeline — APIs "not protected by a Fabric permission model" | With it off the pipeline cannot bootstrap its own workspaces or pipeline objects, however good its roles are |
| **Service principals can call Fabric public APIs** | Developer settings | **Enabled for new customers** | Admits SPs to CRUD APIs "protected by a Fabric permission model" | Off means every item deploy fails even with workspace Admin; the legacy-tenant case is the one to check |
| **Service principals can access read-only admin APIs** | Admin API settings | not stated | Group members get "read-only access to all the information available through admin APIs (current and future)" | Needed for metadata scanning / drift detection; grants user names and emails too |
| **Service principals can access admin APIs used for updates** | Admin API settings | not stated | Admits SPs to admin APIs that write, including Update Tenant Setting | The escalation surface in the one-SP design: a merge-time credential that can rewrite tenant config |
| **Enhance admin APIs responses with detailed metadata** | Admin API settings | not stated | GetScanResult returns table and column names | Turns a metadata scan into a schema inventory — useful to us, also useful to anyone with the group |
| **Enhance admin APIs responses with DAX and mashup expressions** | Admin API settings | not stated | Scan responses include DAX and Power Query expressions | Exposes business logic and literal connection strings, not just names |

### B. Deployment and CI/CD plumbing

| Setting (exact) | Group | Default | What it changes | Why it matters |
| --- | --- | --- | --- | --- |
| **Users can synchronize workspace items with their Git repositories** | Git integration | **Enabled** | The whole Git integration feature; off "prevent[s] users from syncing workspace items" | Off removes the binding mechanism entirely — this is a prerequisite, not a nicety |
| **Users can export items to Git repositories in other geographical locations** | Git integration | not stated | Whether metadata may be committed to a repo outside the capacity's geography; "GitHub doesn't support enforcement of this switch" | A cross-region repo is blocked unless this is on, and an Azure DevOps repo is the case it actually governs |
| **Users can export workspace items with applied sensitivity labels to Git repositories** | Git integration | not stated | Labels are *not* exported with the item, so this decides whether labelled items may be committed at all | Off + any auto-labelling = labelled items become uncommittable and a deploy dies halfway |
| **Users can sync workspace items with GitHub repositories** | Git integration | **Disabled** | Selects GitHub as the Git provider | An Azure DevOps design never needs it; enabling it widens where item metadata can go |
| **Automatically convert and store reports using Power BI enhanced metadata format (PBIR) (preview)** | Workspace settings | **On**; took effect early 2026 | New and edited reports are stored as PBIR, a "source-control-friendly" file structure | Changes the on-disk definition the repo holds — churn, merge conflicts, and preview-format risk |
| **Allow XMLA endpoints and Analyze in Excel with on-premises semantic models** | Integration settings | not stated | Enables connections to XMLA endpoints, read and write | Without it, XMLA/TOM deploys and external semantic-model tooling are unavailable; with it, write access is a data-plane path |
| **Semantic models can export data to OneLake** | Integration settings | not stated | Import-mode tables can be written into OneLake and then read by any Fabric item | A second copy of model data lands in the lake, outside the model's own permissions |
| **Block republish and disable package refresh** | Semantic Model Security | not stated | Disables package refresh; only the model owner may publish updates | Blocks the .pbix-driven refresh-on-publish pattern some pipelines rely on |
| **Users can create Fabric items** | Microsoft Fabric | not stated (delegated to capacity admins) | Whether Fabric items may be created at all; "doesn't impact … Power BI items"; overridable per capacity | Tenant off + capacity override off = no target for a deploy, and the failure looks like a permissions bug |
| **Create workspaces** | Workspace settings | not stated | Who may create app workspaces; a template app install creates one regardless | Gates user-driven workspace creation; SP creation is gated by the Developer setting instead — two different switches |

### C. Settings that let access escape a workspace

| Setting (exact) | Group | Default | What it changes | Why it matters |
| --- | --- | --- | --- | --- |
| **External data sharing** | Export and sharing | not stated | Read-only in-place OneLake shares to other tenants; recipients "can view, build on, and share the data both within and beyond their own Fabric tenants" | The share is a live shortcut: revoking later breaks a third party you do not control |
| **Users can accept external data shares** | Export and sharing | not stated | Permits inbound cross-tenant shares | Inbound data has no provider-tenant labels or DLP applied in your tenant |
| **Guest users can access Microsoft Fabric** | Export and sharing | not stated | B2B guests can reach Fabric and any item they have permissions to; disabling also "prevents users from inviting guests" | Off is a hard external-collaboration stop; on is the precondition for every other guest setting |
| **Users can invite guest users to collaborate through item sharing and permissions** | Export and sharing | not stated | Invitations raised from Fabric; requires the Entra **Guest Inviter** role; formerly "Share content with external users" | Lets a workspace admin create identities in your directory without an Entra admin |
| **Guest users can browse and access Fabric content** | Export and sharing | not stated | Full left-nav browsing for guests; existing role assignments survive disabling it | Browsing is discovery: guests find items nobody shared with them |
| **Guest users can work with shared semantic models in their own tenants** | Export and sharing | **Off** | Guests may build on your semantic models inside *their* tenant | Data leaves your tenant's control while your permissions still gate it — a residency problem |
| **Allow specific users to turn on external data sharing** | Export and sharing | not stated | Per-model external sharing via Entra B2B; "unrelated to" the OneLake external data sharing setting | Two similarly named features; conflating them leaves one path open |
| **Allow shareable links to grant access to everyone in your organization** | Export and sharing | not stated | "People in your organization" links; "won't work for external users" | One link grants the whole tenant read — the cheapest accidental leak in Fabric |
| **Publish to web** | Export and sharing | not stated | Public, unauthenticated embed codes | Anonymous internet access to report data; existing reports keep rendering when set to specific groups |
| **Export to .csv** | Export and sharing | not stated | Tile, visual or paginated-report data to .csv | Flat files carry **no** sensitivity label or encryption — see the interaction section |
| **Download reports** | Export and sharing | not stated | .pbix and paginated report download | A .pbix contains the model, not just the visuals |
| **Export reports as PowerPoint presentations or PDF documents** | Export and sharing | not stated | One of the few export paths where labels *are* applied and encrypted | The only labelled export path; blocking it to stop leakage also removes the protection story |
| **Export to Excel** | Export and sharing | not stated | Visual data to .xlsx, labelled on export | Same class as .csv but protected; useful as the sanctioned route |
| **Users with read or write permission can download data from notebooks** | Export and sharing | not stated | Download/export tables from notebook outputs | Read permission on a notebook becomes bulk data egress |
| **Users can work with semantic models in Excel using a live connection** | Export and sharing | not stated | Analyze in Excel over XMLA, live connection | Live pivot access to the model bypasses report-level design and any RLS you did not set |
| **Users can access data stored in OneLake with apps external to Fabric** | OneLake settings | not stated | ADLS APIs, OneLake File Explorer, Databricks; required for "shortcuts with OneLake security" | The data-plane door: any Entra token from outside Fabric can read the lake, and turning it off breaks those shortcuts |
| **Semantic Model Execute Queries REST API** | Integration settings | not stated | DAX queries against semantic models over REST | Row-level extraction at API speed, independent of any report |
| **Allow downloads from custom visuals** | Power BI visuals | not stated | Custom visuals may download "any information available to the visual"; "not affected by download restrictions" in Export and sharing | Silently defeats every export setting above |
| **Make promoted content discoverable** | Discovery settings | not stated | Promoted content visible to users *without* access | Discovery plus request-access turns a private workspace into a catalogue entry |
| **Make certified content discoverable** | Discovery settings | not stated | Same for certified items | Certification is a trust signal; discoverability exports the signal beyond the audience |
| **Discover content** | Discovery settings | not stated | Users can find and request access to content they cannot open | The request path is a social engineering surface: owners approve without knowing the requester |

### D. Protection, networking and governance metadata

| Setting (exact) | Group | Default | What it changes | Why it matters |
| --- | --- | --- | --- | --- |
| **Allow users to apply sensitivity labels for content** | Information protection | not stated | Whether Purview labels exist in Fabric at all; prerequisites must be met first | Off makes every downstream label setting inert and every export unlabelled |
| **Apply sensitivity labels from data sources to their data in Power BI** | Information protection | not stated | Label inheritance from supported sources into semantic models | An item can arrive already labelled — including during an automated deploy |
| **Automatically apply sensitivity labels to downstream content** | Information protection | not stated | Label propagates to eligible downstream items | Label can appear on an item the pipeline just created, changing its export/commit eligibility |
| **Allow workspace admins to override automatically applied sensitivity labels** | Information protection | not stated | Workspace admins may change or remove labels applied automatically | Removes the guarantee that inherited classification survives a workspace admin |
| **Restrict content with protected labels from being shared via link with everyone in your organization** | Information protection | not stated | Blocks org-wide links for label-protected content; **disabled unless both** the label setting and the shareable-links setting are on | A protection that silently depends on two other switches being on |
| **Domain admins can set default sensitivity labels for their domains (preview)** | Information protection | not stated | Domain default label applies to new items; "Reports, semantic models, dataflows … aren't currently supported" | Half the items you deploy will not get the label you think they have |
| **Tenant-level Private Link** | Advanced networking | not stated | Access to the tenant over Private Link; setup finishes in Azure | Changes the network path the deploy agent must take; a tenant-level link is not a workspace-level one |
| **Block Public Internet Access** | Advanced networking | not stated | Blocks public-internet access to Fabric; "10 to 20 minutes to take effect" | The single setting most likely to make a hosted agent unable to reach `api.fabric.microsoft.com` |
| **Configure workspace-level inbound network rules** | Advanced networking | not stated | Workspace admins add inbound private-link protection; a restricted workspace means "existing tenant-level private links can no longer connect" | A workspace admin can cut the deployment path without touching a tenant setting |
| **Configure workspace-level outbound network rules** | Advanced networking | not stated | Workspace admins add outbound access protection; turning the tenant switch off "also turns off outbound access protection in all the workspaces" | Fail-open by design: the tenant switch is the master off, not a per-workspace lock |
| **Configure workspace-level IP firewall rules and trusted resource instances** | Advanced networking | not stated | IP rules and trusted instances even when public access is blocked | The documented escape hatch for a fixed-IP agent; the page heading calls it "Configure workspace IP firewall rules (preview)" |
| **Apply customer-managed keys** | Encryption | not stated (Microsoft-managed keys by default) | Workspace-level CMK encryption | Needs Key Vault, a capacity, and an admin — a workspace created by the pipeline may not be able to use it |
| **Use short-lived user-delegated SAS tokens** | OneLake settings | not stated | Users may request user delegation keys to sign OneLake SAS tokens, max one hour | Time-boxed but portable credentials to lake data |
| **Authenticate with OneLake user-delegated SAS tokens** | OneLake settings | not stated (delegated to workspace admins) | Applications may authenticate with a OneLake SAS; requires the setting above | Any app holding a SAS reads the lake without an Entra identity in the audit trail |
| **Certification** | Export and sharing | not stated | Who may certify items; security groups only, no named users; delegable to domain admins | Decide whether the deploy identity may certify or only humans may — a security-group question, not a role question |
| **Endorse master data** | Export and sharing | not stated | Who may mark items as authoritative organizational data | A metadata claim that downstream consumers treat as permission to trust the data |
| **Allow tenant and domain admins to override workspace assignments (preview)** | Domain management | not stated | Admins may reassign a workspace from one domain to another | Domain assignment made by the pipeline can be undone out from under it |
| **Use semantic models across workspaces** | Workspace settings | not stated | Cross-workspace use of a semantic model given Build permission | The legitimate cross-workspace read path; every other one in section C is a leak |
| **Enable granular access control for all data connections** | Integration settings | not stated | "Shared items will be disconnected from data sources if they're edited by users who don't have permission" | Hardening that can break an item on republish by the deploy identity |
| **Enable anonymous data access for Fabric Apps (Preview)** | Microsoft Fabric | not stated | Public, unauthenticated access to Fabric App data | An anonymous data endpoint on a tenant otherwise gated by Entra |

## The ten that matter to us

1. **Service principals can create workspaces, connections, and deployment pipelines** — off: the pipeline cannot create anything, and the error looks like a role problem. Off by default for new customers, so a trial tenant and the work tenant can differ.
2. **Service principals can call Fabric public APIs** — off: every CRUD call fails despite workspace Admin. On by default for new customers only.
3. **Block Public Internet Access** — on without a working private link: the agent cannot reach the API at all, and the failure is a timeout, not a 401.
4. **Users can synchronize workspace items with their Git repositories** — off: no Git binding, so a repo-as-source-of-truth design has no mechanism.
5. **Users can export workspace items with applied sensitivity labels to Git repositories** — off plus auto-labelling: labelled items become uncommittable and a deploy fails part-way through a workspace.
6. **Allow shareable links to grant access to everyone in your organization** — on: any "people in your organization" link is a tenant-wide read grant, and it also arms the label-protection setting that is otherwise off.
7. **Guest users can access Microsoft Fabric** — off: collaboration with the business's external reviewers stops, and inviting guests stops with it; on: every other guest setting becomes reachable.
8. **Users can access data stored in OneLake with apps external to Fabric** — off: ADLS/DFS access and OneLake File Explorer break, and shortcuts with OneLake security stop working; on: the data plane is reachable by any Entra token outside Fabric.
9. **Publish to web** — on: unauthenticated public access to report data, and reports already published keep rendering when the setting is narrowed to groups.
10. **Users can create Fabric items** (with **Create workspaces**) — the pair decides whether a workspace and an item may exist at all; the SP switch governs automation while these govern humans, and a capacity override can invert the tenant answer.

## Must be agreed with a tenant admin, not a workspace admin

These are org-wide, and a pipeline that sets them is a pipeline that can widen its own access. Treat them as a
signed-off list, not as automation.

- The four service-principal gates (which include both admin API gates), plus both **Enhance admin APIs responses** settings — the last two expose schema and business logic to anyone in the allowed group.
- **Block Public Internet Access**, **Tenant-level Private Link**, and the three workspace-level network switches — network posture is a security decision, and the outbound switch fails open when disabled at tenant level.
- **Guest users can access Microsoft Fabric**, **Users can invite guest users to collaborate through item sharing and permissions**, **Guest users can browse and access Fabric content**, **Guest users can work with shared semantic models in their own tenants** — half of these depend on Entra configuration the Fabric admin does not own.
- **External data sharing**, **Users can accept external data shares**, **Allow specific users to turn on external data sharing** — three similarly named switches, each a different exit.
- **Publish to web**, **Allow shareable links to grant access to everyone in your organization**, **Export to .csv**, **Download reports**, **Users with read or write permission can download data from notebooks** — export policy is a DLP decision.
- All **Information protection** settings, plus **Apply customer-managed keys** — labels and keys are owned jointly with Purview, Key Vault and the capacity.
- **Certification**, **Endorse master data**, **Make certified content discoverable**, **Discover content** — endorsement is an organizational claim about data quality, not a deployment fact.
- **Users can create Fabric items**, **Create workspaces**, **Use semantic models across workspaces**, **Allow XMLA endpoints and Analyze in Excel with on-premises semantic models** — tenant- or capacity-level grants that the workspace admin cannot see.

## Settings that interact badly with each other

- **Guest access + shareable org-wide links.** Guest browsing finds the item; an org-wide link opens it. Either alone is contained; together a guest reaches content no one shared with them by name.
- **External data sharing + sensitivity labels.** Governance stops at the tenant boundary: "label visibility, downstream label inheritance, export encryption … aren't enforced in the consumer tenant", and the consumer "can grant access … to anyone". A labelled share is an unlabelled share downstream.
- **Auto-apply labels + Git label-export off.** Label inheritance puts a label on an item the pipeline just created; the Git switch then refuses to commit it. The pipeline fails on the item it deployed successfully a minute earlier.
- **Block Public Internet Access + workspace-level inbound rules.** With public access blocked the agent needs the tenant private link; a workspace admin who turns on inbound restrictions cuts off "existing tenant-level private links" to that workspace, and the tenant admin sees nothing change.
- **Workspace-level outbound rules + tenant switch off.** Turning the tenant setting off "also turns off outbound access protection in all the workspaces" — a single tenant-level click silently removes protection from every workspace that had it.
- **Export to .csv + labels.** Label protection applies to Excel, PowerPoint and PDF only, and not to "export to .csv or .txt". Turning on labels plus CSV export gives a labelled, governed-looking estate with an unprotected flat-file exit.
- **Allow shareable links to grant access to everyone in your organization + Restrict content with protected labels from being shared via link with everyone in your organization.** The restriction is "disabled if you haven't enabled both" the label setting and the shareable-links setting. Turning shareable links off to tighten sharing also disables the label restriction.
- **PBIR (preview) + Git integration.** PBIR is on by default and rewrites report definitions on edit, so the repo's serialised JSON changes shape without anyone editing the repo.
- **Certification + Make certified content discoverable + Discover content.** Certification marks an item trustworthy, discoverability shows it to users without access, and Discover content gives them a request path. Three reasonable settings that together publish an attack surface.
- **Service principals can call Fabric public APIs + Users can use the Power BI Model Context Protocol server endpoint (preview).** The MCP setting's own docs say SPs need the public-API setting on, so enabling MCP extends what the deploy identity can reach.

## Preview, and defaults that differ between tenant types

Marked preview in the index as read on 2026-11-12, exact names: **Automatically convert and store reports using Power
BI enhanced metadata format (PBIR) (preview)**, **Domain admins can set default sensitivity labels for their domains
(preview)**, **Enable anonymous data access for Fabric Apps (Preview)**, **Allow tenant and domain admins to
override workspace assignments (preview)**, **Users can use the Power BI Model Context Protocol server endpoint
(preview)**, **Workspace admins can turn on monitoring for their workspaces (preview)**, **Users can view Power BI
files saved in OneDrive and SharePoint (preview)**, **Users can share links to Power BI files stored in OneDrive and
SharePoint through Power BI Desktop (preview)**, **Users can use Fabric Copilot (preview)**, and the new
deployment-pipelines UI. The **Microsoft Fabric** group also carries a run of preview *item-type creation* toggles
(Ontology, Digital Twin Builder, ML endpoint predictions, anomaly detection, Event Schema Sets, mirrored catalog
items, Fabric App Items, Azure Databricks Storage items, Agent 365 telemetry), excluded under the rule below. Of
the catalogued settings, only **PBIR** and **Domain admins can set default sensitivity labels** change behaviour we
depend on.

On trial versus production: **could not establish**. No page read states a trial-tenant default. The documented
asymmetry is *new customer* versus *existing tenant* — the create-workspaces gate is "disabled by default for new
customers" while the public-API gate is "enabled by default for new customers". A trial tenant is always a new
customer, which is exactly why trial behaviour cannot predict the work tenant's.

## What is excluded, and why

Curated, not complete: ~300 settings exist and 57 are catalogued. Excluded, with the reason:

- **Cosmetic, lifecycle or non-security**: conference banners, Product Feedback, Help and support, custom publish message, user-experience experiments, featured content, app installation, scorecards, Q&A, insights entry points, dashboard web content; workspace retention (minimum 7 days, max 90), Fabric item recovery (on by default, 3–90 days), **Block users from reassigning personal workspaces**.
- **Not reachable from our design**: Embedded/app-own-data settings, service principal profiles, template apps, Gen1 dataflows, datamarts, Explore, ArcGIS/Azure Maps and their residency switches, SSO-to-connector settings (Snowflake, BigQuery, Redshift, Dremio, Denodo, Starburst, gateways), Power BI visuals SDK/local storage, R and Python visuals.
- **AI/agent features outside the deployment scope**: all Copilot and Azure OpenAI settings, Azure AI services, Purview AI interactions, operations-agent telemetry, Foundry observability. They leak data, but not the data this pipeline deploys.
- **Marginal on our five axes, but noted**: **Block ResourceKey Authentication** (streaming/PUSH only), **Define maximum number of Fabric identities in a tenant** (10,000 when unset), **Allow service principals to create and use profiles** (multitenancy), **Allow non-Entra ID auth in Eventstream**, **Copy and paste visuals** (static images — a real but low-volume egress), **Users can send email subscriptions to external users** and the B2B subscription switches, **Allow DirectQuery connections**, **Semantic model settings** (edit in service), **Scale-out**, **Kusto embedded app visuals**, **Additional workloads** (unvalidated partner workloads are a genuine risk but not a deployment-path one), **Share Fabric data with your Microsoft 365 services**.

## What this settles

- 57 settings that can break a deploy, leak access or let data out, with exact portal names, group and documented default — and that only two of those defaults are stated *for new customers*, the new-customer split (not trial/production) being the asymmetry that matters.
- That the most consequential settings are plumbing (Git, XMLA, OneLake external access, public-internet blocking, export), not feature toggles, which is why "the rest are harmless" is false.
- That several protections are conditional on other switches being on, and at least one fails open when a tenant switch is disabled.

## What this does not establish

- The default for the majority of settings: most group pages describe behaviour without stating a default. Portal defaults were not observed — no tenant was available.
- Whether creating a deployment pipeline as a *user* is gated by **Users can create Fabric items**; the index lists no user-facing deployment-pipeline setting.
- Whether **Service principals can call Fabric public APIs** reaches the OneLake DFS/ADLS endpoint, or whether the separate OneLake external-apps setting is the only gate.
- Any trial-tenant-specific default, and whether trial capacities inherit tenant settings differently.
- Whether the **Allow specific users to turn on external data sharing** (B2B, semantic models) and **External data sharing** (OneLake) settings share a permitted-users list. They are documented as unrelated features.
- The exact portal text for settings the index describes but whose group page does not name identically (see the naming disagreements below).

## Naming disagreements and index gaps

- The **Admin API settings** page's own note calls the read-only gate **"Allow service principals to use read-only admin APIs"**; the setting is **"Service principals can access read-only admin APIs"**. The same page repeats the wrong name in both enhancement settings' notes.
- The index lists **"Configure workspace-level IP firewall rules and trusted resource instances"**; the advanced-networking page heading is **"Configure workspace IP firewall rules (preview)"**.
- The index lists **"External data sharing"**; the export-and-sharing page refers to **"External data sharing (preview)"** and **"Users can accept external data shares (preview)"**.
- The information-protection page's own note calls the label gate **"Allow users to apply sensitivity labels for Power BI content"**; the setting is **"Allow users to apply sensitivity labels for content"**.
- **"Users can invite guest users to collaborate through item sharing and permissions"** was previously called **"Share content with external users"**, and the export page's **"Allow connections to featured tables"** / **"Allow live connections"** appear on no index row — automation written against either old or missing name will not find it.

## Sources

| Source | What it was used for |
| --- | --- |
| https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index (2026-08-28), .../about-tenant-settings (2026-09-01) | Names, grouping, descriptions, preview markers; the five enablement states; "not a security measure" caveat |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-developer (2026-04-08), .../service-admin-portal-admin-api-settings (2026-06-26) | The two SP defaults "for new customers"; the three unprotected APIs; admin API gate scope and its naming error |
| https://learn.microsoft.com/en-us/fabric/admin/git-integration-admin-settings (2026-10-07) | Git defaults (sync enabled, GitHub disabled); labels not exported; geo restriction; delegation chain |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-export-sharing (2026-04-08), .../service-admin-portal-information-protection (2026-04-08) | Export, guest, sharing and endorsement behaviour; label settings and the export paths that support protection |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-advanced-networking (2026-04-08) | Private link, public-internet block, workspace-level switches and fail-open behaviour |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-onelake (2023-11-02), .../service-admin-portal-integration (2026-04-08), .../onelake/security/fabric-onelake-security (2026-09-01) | OneLake external access, SAS settings and shortcut dependency; XMLA, Execute Queries, granular connection control |
| https://learn.microsoft.com/en-us/fabric/admin/portal-workspace (2026-09-01), .../admin/fabric-switch (2026-08-27) | Create workspaces, cross-workspace models, PBIR default; **Users can create Fabric items** and capacity delegation |
| https://learn.microsoft.com/en-us/fabric/governance/external-data-sharing-overview (2025-06-10) | Cross-tenant governance not flowing; consumer can re-share; label/DLP not enforced |
| https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview (2024-07-11), .../admin/endorsement-certification-enable | Promoted/Certified/Master data semantics; groups-only certification and domain delegation |
| https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines (2026-09-24) | Deployment pipeline structure; no user-facing tenant gate documented |

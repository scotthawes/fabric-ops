# When does a Fabric solution need a data gateway, and what does that mean for unattended operation?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work-repo deploy design — whether a gateway appears in the estate at all, and which
  steps stay out-of-band if it does

## Short answer

Only when Fabric cannot reach the source itself: an on-premises or private-network source, a source
needing connector software on the machine, or a connector that demands a gateway for isolation. Everything
else is a cloud **connection**, a **managed private endpoint** (Spark and Eventstream only) or **Trusted
workspace access** (storage). The gateway is not the hard part for automation — the binding between a
deployed semantic model and its gateway connection is, because no pipeline or Git commit carries it.

## Detail

### 1. Three gateway types, one Fabric-specific variant

| Product name | Reaches | Runs | Cost | Status | Who installs / administers |
| --- | --- | --- | --- | --- | --- |
| **on-premises data gateway** (standard mode; "previously called Enterprise gateway") | On-premises and private-network sources, Azure VMs, and Fabric/Power BI/Power Apps/Power Automate/Logic Apps/Azure Analysis Services | Windows machine you own, outbound only | No Fabric charge documented; you pay for the VM | Unlabelled | Machine local admin installs; a **gateway admin** manages; **Manage gateway installers** restricts installation |
| **on-premises data gateway (personal mode)** | Local sources for one user's Import models; Power BI only | The user's machine, interactive app, not a service | None documented | Unlabelled | The user; "Install only as a local admin: **No**"; one per user |
| **virtual network (VNet) data gateway** | Azure services in a VNet (including private endpoints), public endpoints, on-premises via the VNet | Microsoft-managed container in a delegated subnet | "billed as an additive premium infrastructure charge" on the attached capacity | No GA statement found; PPAC path reads **Data (preview)** | Subscription owner registers `Microsoft.PowerPlatform`; Network Contributor delegates the subnet; a capacity admin creates it |
| **streaming virtual network data gateway** | Named in the connection API and PPAC tabs; sources not described on the pages checked | Microsoft-managed | Not documented | Not documented | Same installer restriction as the VNet gateway |

Exact strings: connectivity types are `OnPremisesGateway`, `OnPremisesGatewayPersonal`,
`VirtualNetworkGateway`, `StreamingVirtualNetworkGateway`, `ShareableCloud`, `PersonalCloud`, `Automatic`
([conn-create]); the subnet delegation is `Microsoft.PowerPlatform/vnetaccesslinks`.

- Outbound only, and clustered for HA: "The gateway uses outbound connections, so you don't need to open
  inbound ports to your network" ([pbi-gw]); "Each cluster can support up to 10 gateway members", the
  service "always uses the primary gateway in a cluster unless that gateway isn't available", and members
  must run "the same gateway version" ([ha]).
- Personal mode is a dead end: "only Import semantic models that use scheduled or on-demand refresh",
  no clustering, and only PowerShell can restrict installation — "Setting the gateway tenant policy by
  using PowerShell is the only way to manage who can install personal gateways in your tenant" ([personal]).
- VNet hardware is fixed ("2 cores / 8 GB of RAM each … can't be scaled or changed", [vnet-arch]) and
  idles down via **Time to auto-shutdown** ([vnet-manage]).

### 2. What needs a gateway — and what a private endpoint replaces

Documented triggers: the source "is located on-premises", "is located in a private network", "you
require a host for connector software", or "you require security isolation for certain connectors or
functions" ([planning]). Two consequences people get wrong:

- **Cloud does not mean direct, and public web can still need one**: "It's a common misconception that
  you don't need a gateway for cloud data sources. When a cloud data source resides within a private
  organizational network, a gateway is required" ([planning]) — Azure SQL behind a VNet or IP firewall is
  that case. Queries over the Web connector or `Web.BrowserContents` "require a gateway for many reasons,
  including security isolation" ([planning]).

- **Trusted workspace access** replaces it for storage: "generally available", F SKU only, via a
  workspace identity plus a **resource instance rule**. Scope is explicit — "You can only use trusted
  workspace access in OneLake shortcuts, pipelines, semantic models, the T-SQL COPY statement, and
  AzCopy. To securely access storage accounts from Fabric Spark, see Managed private endpoints" ([twa]).
- **Managed private endpoints (MPE)** replace it for Spark and streaming only: "notebooks (Spark and
  Python runtimes), lakehouses, and Spark job definitions" and Eventstream — not semantic models, not
  data pipelines ([mpe]). 26 Azure resource types are supported ([mpe-create]), yet "OneLake shortcuts
  do not yet support connections to ADLS Gen2 storage accounts and Azure Blob Storage accounts using
  managed private endpoints" ([mpe]), and "the data source admins are notified" to approve
  ([mpe-create]).
- **SaaS** (Salesforce, SharePoint Online, Dataverse) and **OneLake** need no gateway: the first is a
  `ShareableCloud` connection with organizational-account, service-principal or workspace-identity
  credentials ([conn-create]); the second is direct, and cross-tenant shortcuts "aren't supported over
  Private Link" ([network note](network-private-endpoints-and-deployment-path.md)).
- **On-premises gateway and tenant private link are mutually exclusive**: "Using an on-premises data
  gateway with private link enabled isn't supported. We recommend using the VNet data gateway";
  registration fails with `System.NullReferenceException` ([install]).

### 3. Authentication for unattended refresh

- **Credential owner is the connection, not the item.** Connection roles are **Owner**, **User with
  sharing**, **User**; gateway roles are **Admin**, **Connection creator with sharing**, **Connection
  creator** ([planning]); a consumer needs only the *User* connection role.
- **Storage:** credentials are "encrypted … with symmetric encryption so they can't be decrypted in the
  cloud" and decrypted only on the gateway machine ([datasources]); cloud connections accept a
  `KeyVaultSecretReference` (`connectionId` + `secretName`) instead of a secret ([conn-create]) — a
  reference, not automatic rotation.
- **Service principal is per connector, never global.** The API offers `ServicePrincipal`, but the one
  to quote is the SQL Server note: "The Service principal authentication only applies to SQL Server on
  Azure VMs" ([sql]) — anything on-premises falls back to Basic/Windows, i.e. a stored secret. And
  "Service principal isn't supported for dataflows" at all ([dp]).
- **Storage is the exception:** for trusted workspace access, "workspace identity is the only supported
  authentication method. Test connection fails if organizational account or service principal
  authentication methods are used" ([twa]).
- **Expiry and departure:** transferred ownership is not effective until credentials are re-entered —
  `PendingOwner` means "Ownership of the connection is not yet effective; the principal must update the
  connection credentials … to make it effective" ([conn-create]). Pipelines have the same shape, left
  "without an owner when a user that owned it leaves the company without transferring ownership" ([ts]).
- **Caches outlive the fix:** credentials are cached "in a matter of hours … the new credentials aren't
  used for approximately 5 hours" ([gw]); the VNet gateway "currently doesn't support refreshing tokens
  automatically when access tokens expire" ([vnet]).

### 4. Permissions

- **Create a connection:** for a gateway-bound one "the caller must have permissions for the gateway"; a
  service principal additionally needs **Service principals can create workspaces, connections, and
  deployment pipelines** ([conn-create]). A workspace role grants neither.
- **Bind an item:** the model's own **Gateway and cloud connections** settings, where binding and
  credential are chosen ([twa]); workspace roles are necessary but not sufficient. **Deploy:** "The
  deploying user automatically becomes the owner of the cloned semantic models" ([dp]).
- **A deployment pipeline does nothing about the binding:** "The gateway associated with the target item
  is not automatically mapped to the corresponding data source. You need to manually configure this
  mapping through the target item's settings page … Subsequent deployments do not alter or reset this
  gateway configuration" ([dp]). **Data source credentials** are on the not-copied list ([dp]). Rules can
  repoint a source but "only work when you change data sources from the same type" ([rules]). And in Git,
  "Git integration doesn't support DirectQuery and proxy models at this time" ([ts]) — the exact case a
  gateway exists for.

### 5. Operational realities

- **Clustering is the only HA story**: up to 10 members, one version, failover to any live member,
  optional **Distribute requests across all active gateways in this cluster**, and throttles in
  `Microsoft.PowerBI.DataMovement.Pipeline.GatewayCore.dll.config`
  (`CPUUtilizationPercentageThreshold`, `MemoryUtilizationPercentageThreshold`,
  `ResourceUtilizationAggregationTimeInMinutes`); an offline member that is not disabled still receives
  queries and slows them ([ha]).
- **Single point of failure:** every item bound to one cluster fails when it is offline, and a VNet
  gateway cannot be scaled — "We strongly recommend that you use gateway clusters" ([planning]).
- **Monitoring is local, not platform.** Performance logging is **public preview**, writes four log files
  (`ReportFilePath`) and needs a downloaded template; it "doesn't capture diagnostics directly related to
  the (virtual) machine and its network" ([perf]). Status is PPAC **Check status** plus on-disk logs; no
  Azure Monitor metric surface is described.
- **Limits and cadence:** 1,000 data sources per cluster; 2 MB write payload, 2 MB request and 8 MB
  compressed read response ([gw]); 100 principal assignments per gateway and per connection ([ppac]).
  Updates are manual, monthly and unrollbackable — "The gateway owner must manually apply gateway updates
  to each gateway", only the last six releases are supported, and "there's no rollback process"
  ([planning], [update]).

### 6. What a deployment design must treat as manual

The list under "What this settles" is the whole of it; nothing in it can be produced by a Git commit or a
deployment-pipeline run. The failure that follows a deploy is not a deploy error: the item exists, the
report opens, and the refresh fails because the target stage has no mapping and no credentials — both
excluded from the copy ([dp]). Expect `CreateGatewayConnectionFailed` or `InvalidConnectionDetails`
([conn-create]), `InvalidConnectionCredentials`/`AccessUnauthorized` for expired VNet-gateway OAuth tokens
([vnet]), and a trusted-workspace-access connection sitting at status **Offline** ([twa]).

## What this settles

| Source | Route | Why |
| --- | --- | --- |
| On-premises SQL Server, Oracle, file share, SAP | on-premises data gateway (standard), clustered | Private network, and SP auth does not apply off Azure |
| SQL Server on an Azure VM | VNet data gateway | Private network; SP auth is documented for exactly this case |
| Azure SQL DB / Synapse with a private endpoint | VNet data gateway | MPEs do not serve semantic models or pipelines |
| Azure SQL DB with public endpoint + IP firewall | `ShareableCloud` if Fabric egress is allowed, else VNet gateway | The gateway is about the network path, not the engine |
| ADLS Gen2 / Blob with firewall | Trusted workspace access | GA, and the only route covering shortcuts, pipelines, models, COPY |
| ADLS Gen2 / Blob from Spark | managed private endpoint | TWA explicitly excludes Spark |
| ADLS Gen2 / Blob fully public, SaaS, OneLake | `ShareableCloud` connection or direct | Nothing to tunnel |
| Public web page needing a browser engine | gateway | Web connector requires isolation |
| Tenant with private link on | VNet gateway only | On-premises gateway registration fails |

A human must, outside the pipeline: install/register/cluster the gateway and hold its recovery key; grant
gateway and connection roles; create the connection; bind each item per stage and set credentials; approve
every managed private endpoint; create the resource instance rule and workspace identity; register the
PowerPlatform provider and delegate the subnet; rotate secrets; update the gateway monthly.

## What this does not establish

- GA status of the VNet data gateway or the streaming variant — no page checked labels either, and the
  admin-centre path still reads **Data (preview)**. Nor whether the on-premises gateway carries a licence
  cost; only "no charge documented" is supported.
- The exact role required to bind a semantic model in **Gateway and cloud connections** — the pages
  describe the action, not the permission check.
- Whether a service principal can complete an on-premises gateway connection end to end; untested.
- Any throughput or refresh-concurrency figure beyond payload size and the 1,000-source limit.
- The work tenant's sources, gateways, or whether it has any at all.

## Sources

| Source | Used for | Page date |
| --- | --- | --- |
| [On-premises gateways in Power BI](https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-onprem) / [personal mode](https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-personal-mode) / [data sources](https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-data-sources) | taxonomy, outbound-only, personal limits, credential encryption | 2026-09-18 / 2025-09-25 / 2025-09-30 |
| [What is an on-premises data gateway](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-onprem) / [install](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-install) | service list, payload limits, credential cache, 1,000 sources, private-link conflict | 2025-06-10 / 2025-10-15 |
| [VNet overview](https://learn.microsoft.com/en-us/data-integration/vnet/overview) / [architecture](https://learn.microsoft.com/en-us/data-integration/vnet/data-gateway-architecture) / [create](https://learn.microsoft.com/en-us/data-integration/vnet/create-data-gateways) / [manage](https://learn.microsoft.com/en-us/data-integration/vnet/manage-data-gateways) | managed service, item scope, OAuth limit, 2-core hardware, subnet delegation, auto-shutdown | 2025-06-27 / 2025-06-26 / 2026-08-01 / 2025-06-23 |
| [Gateway HA clusters](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-high-availability-clusters) / [performance](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-performance) | 10 members, primary, throttles, preview logging | 2025-06-12 |
| [Update a gateway](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-update) / [PPAC gateway management](https://learn.microsoft.com/en-us/power-platform/admin/onpremises-data-gateway-management) | monthly cadence, no rollback, installers, 100-assignment limits | 2026-07-28 / 2026-11-06 |
| [Implementation planning: data gateways](https://learn.microsoft.com/en-us/power-bi/guidance/powerbi-implementation-planning-data-gateways) | four triggers, roles, billing, manual updates | 2024-12-30 |
| [Deployment pipelines process](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process) / [rules](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/create-rules) / [troubleshoot](https://learn.microsoft.com/en-us/fabric/cicd/troubleshoot-cicd) | gateway mapping gap, credentials not copied, same-type rules, Git gap | 2026-09-24 / 2026-09-01 / 2026-09-23 |
| [Connections – Create Connection](https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/create-connection) | connectivity and credential types, permissions, `PendingOwner` | 2022-12-28, rev. 2026-11-10 |
| [Managed private endpoints](https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-overview) / [create](https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-create) | item scope, 26 resources, approval, shortcut gap | 2025-05-12 / 2026-08-20 |
| [Trusted workspace access](https://learn.microsoft.com/en-us/fabric/security/security-trusted-workspace-access) | GA, F SKU, workspace-identity-only auth, scope | 2026-08-13 |
| [SQL Server connector](https://learn.microsoft.com/en-us/fabric/data-factory/connector-sql-server-database-overview) | service-principal limitation quoted verbatim | 2025-07-09 |

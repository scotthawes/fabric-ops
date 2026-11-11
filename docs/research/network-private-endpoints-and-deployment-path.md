# Which network path does each kind of Fabric traffic take, and what must the agent VMs reach?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the work-repo pipeline design (agent placement, DNS, proxy) and any decision to turn on private links in the work tenant

## Short answer

There is no single path. Control-plane calls go to a public HTTPS endpoint, `api.fabric.microsoft.com`,
which Fabric answers only when the request arrives from a network the tenant allows; data-plane calls
(OneLake, TDS, Spark, shortcuts) are what private links actually carry. A public deploy path therefore
works only while **Block Public Internet Access** is off; once it is on, the agent must egress through
the VNet holding the private endpoint, resolve the tenant or workspace FQDN privately, and still reach
`login.microsoftonline.com` over public HTTPS for tokens.

## Detail

### 1. The five features, named exactly

| Feature (doc wording) | What it isolates | Admin scoping | Cost | Status |
| --- | --- | --- | --- | --- |
| **Tenant-level Private Link** (tenant setting; the how-to calls it **Azure Private Link**, the overview **Azure Private Links**) | Inbound, whole tenant: "traffic going *into* your organization's Fabric items" | "You must be a Fabric administrator and have permissions in Azure to create and configure resources such as virtual machines (VMs) and virtual networks (VNets)" | "The cost of private links and the increase of the ExpressRoute bandwidth … might add costs"; priced as Azure Private Link. No Fabric CU figure documented | Not labelled preview on any page checked; no page states GA either. Not supported on Trial capacity |
| **Managed private endpoints** | Outbound, from Fabric workloads to *your* data sources behind a firewall | "Users with admin permissions to a Microsoft Fabric workspace can create, view, and delete managed private endpoints" (workspace settings → **Network security**) | No cost statement in the docs. Supported on Fabric capacities "including Trial Capacities" | Unlabelled; the Eventstream use is explicitly *(Preview)* |
| **Managed virtual network** | Spark compute: clusters leave the shared VNet for a per-workspace VNet | None — provisioned automatically on first Spark job (with Private Link on) or on first managed private endpoint | No separate charge documented, but starter pools are disabled | Unlabelled; not available in Switzerland West / West Central US |
| **Trusted workspace access** | Inbound to *storage*: lets a workspace identity through an ADLS Gen2 / Blob firewall via resource instance rules | Workspace admin creates the workspace identity; "A Contributor on the storage account … can configure resource instance rules or trusted service exception" | No charge documented; F SKU only | "**generally available**", explicitly |
| **Workspace-level private link** | Inbound, one workspace; other workspaces stay public | Fabric admin enables **Configure workspace-level inbound network rules** (off by default); "You must be a workspace admin and have sufficient Azure permissions"; Azure custom role needs `Microsoft.Fabric/privateLinkServicesForFabric/*` | No cost statement. F SKU only; P SKU and trial unsupported | Unlabelled; dependent items carry their own preview labels |

Two naming traps worth recording: the tenant setting is **"Tenant-level Private Link"** in the settings
index but **"Azure Private Link"** in the setup steps and **"Azure Private Links"** in the overview — three
strings for one toggle. And the docs never say "Allow trusted workspace access"; the feature is
**Trusted workspace access**, and the storage-side alternatives are **resource instance rules** or the
**trusted service exception**.

### 2. Control plane vs data plane, and whether the REST API is public

Private links protect data traffic. The REST API is a different story, and the docs are explicit in a
table rather than in prose: with tenant public access **Restricted**, "Public internet → Can I access
Fabric REST APIs? **No**", while a "Network with tenant private link" gets "**Yes, using tenant-specific
FQDN or api.fabric.microsoft.com endpoint, and only if the client allows outbound public access**"
([inbound overview][inbound]). So the endpoint is not made private; the source network is checked.
`api.fabric.microsoft.com` is the documented API host in four separate rows of that table.

The same page's second table matters for automation: the workspace communication-policy API is reachable
"using `api.fabric.microsoft.com` endpoint or workspace-specific FQDN" under tenant-level private link,
but **not** over `api.fabric.microsoft.com` from a workspace-level-private-link network when tenant access
is restricted ([workspace setup][ws-setup], Table 1). That is a self-lockout shape: the API you would use
to reopen a workspace is the one the policy can close.

**What the docs do not say:** they never state that `api.fabric.microsoft.com` resolves to a private IP,
and they never explain the mechanism by which a client on the private-link network is allowed to use the
public endpoint. The tenant-specific private API name is `{tenantId}-api.privatelink.analysis.windows.net`
([setup][pl-use], step 7). Entra is public: `login.microsoftonline.com` and `graph.microsoft.com` are on
the "Required for auth" list for private-link tenants, alongside `aadcdn.msauth.net`, `msauth.net`,
`msftauth.net` and `login.live.com` ([private links][pl]). No page describes a private path for Entra
token acquisition.

### 3. What actually respects a private endpoint

- **OneLake** — yes, "OneLake supports Private Link". But "Direct calls using OneLake regional endpoints
  don't work via private link to Fabric"; connect by workspace FQDN (`https://<wsid>.z<xy>.dfs.fabric.microsoft.com`)
  or the tenant path ([OneLake access][onelake], [private links][pl]).
- **OneLake shortcuts** — same-tenant shortcuts work "when both the shortcut source and target are within
  the same tenant". Cross-tenant shortcuts "aren't supported over Private Link". Shortcuts to external
  ADLS/S3 need the external account to allow private endpoint access. And managed private endpoints
  "do not yet support connections to ADLS Gen2 storage accounts and Azure Blob Storage accounts" — so the
  supported route to firewall-enabled storage is **Trusted workspace access**, not an MPE ([MPE][mpe]).
- **SQL analytics endpoint / Warehouse TDS** — supported over private link, but the connection string
  changes: add `z{xy}` and use `{GUID}-{GUID}.z{xy}.datawarehouse.fabric.microsoft.com`. "Visual query in
  Warehouse doesn't work when the **Block Public Internet Access** tenant setting is enabled"
  ([private links][pl], [workspace support][ws-support]).
- **Spark** — works, at a price: a managed VNet is created on the first job, "starter pools … are disabled",
  and jobs run on custom pools that "could take up around 3 to 5 minutes to start". Spark also fails for
  tenants whose *home region* lacks Fabric Data Engineering, even when the capacity region has it
  ([managed VNets][mvn]).
- **Semantic model refresh** — the weakest link. Under workspace-level private link, "Power BI semantic
  models aren't supported in workspaces with workspace-level private links enabled" and their presence
  blocks enabling it. Under tenant-level private link, if internet access is disabled and a semantic model
  "connects to a Power BI semantic model or Dataflow as a data source, the connection fails"; the usage
  metrics dataset refresh also fails. Import-mode models reading firewall-enabled ADLS need **Trusted
  workspace access** bound as a cloud connection ([private links][pl], [trusted access][twa]).

### 4. What the agent VMs need

- **Network position.** The request must arrive from the approved network; a private endpoint exists only
  inside its VNet/peered network. There is no "agent VNet" requirement in the docs, but there is an
  effective one: if the workspace or tenant restricts public access, an agent outside that VNet is denied
  by design.
- **DNS.** Tenant-level: `privatelink.analysis.windows.net`, `privatelink.pbidedicated.windows.net`,
  `privatelink.prod.powerquery.microsoft.com`. Workspace-level: `privatelink.fabric.microsoft.com`. The
  zone must be linked to the agent VNet. A newly created capacity "doesn't support private link until its
  endpoint is reflected in the private DNS zone, which can take up to 24 hours" ([private links][pl],
  [workspace setup][ws-setup]).
- **Ports.** "Fabric requires only TCP Port 443" for the Fabric platform and OneLake endpoints; add
  TCP 1433 for `*.datawarehouse.fabric.microsoft.com` and SQL database, TCP 11000–11999 if SQL database
  uses the redirect policy, and 5672/5673/9093 only if eventstreams are consumed directly
  ([allowlist][allow]).
- **Proxy.** `az` is documented: if behind a proxy, "HTTP_PROXY and HTTPS_PROXY must be set" ([CLI][cli]).
  The agent's own bypass list is fixed: `https://dev.azure.com`, `https://*.dev.azure.com`,
  `https://login.microsoftonline.com`, `https://management.core.windows.net`,
  `https://download.agent.dev.azure.com` ([Linux agent][linux]); and that page warns "your build pipeline
  and scripts must still handle bypassing your web proxy for each task and tool you run".
- **A proxy can break private link itself.** "Network proxies and traffic interceptors (for example,
  Zscaler) can prevent traffic from reaching the workspace's private endpoint, especially when users or
  network egress points are in a different Azure region than the workspace's capacity", producing
  `RequestDeniedByInboundPolicy` ([workspace support][ws-support]).
- **Terraform provider and fabric-cicd.** I could not establish proxy behaviour from Microsoft sources;
  neither the provider repo nor the Fabric docs state it. Treat the agent image as the thing to test.

### 5. Known unsupported or caveated

- **Deployment pipelines**: "Deployment pipelines aren't currently supported for workspace with inbound
  access protection", and a workspace assigned to a pipeline can't be restricted ([CI/CD security][cicd]).
  No page states this for tenant-level private links, so that case is unestablished.
- **Git integration**: allowed by default under inbound protection, but "users attempting to access Git
  features … must do so from within the approved VNet. … This restriction also applies to the Git APIs";
  "Branching out is blocked" ([CI/CD security][cicd]).
- **Copilot**: "isn't currently supported for Private Link or closed network environments"; Copilot in
  Dataflow Gen2 is separately unsupported under workspace-level private links ([private links][pl]).
- **Unsupported item types** in a workspace-level-private-link workspace: deployment pipelines and
  semantic models; if they exist, "inbound public access can't be restricted". Item sharing, workspace
  monitoring and shortcut transforms are also unsupported there ([workspace support][ws-support]).
- **Cross-workspace**: reading another restricted workspace's lakehouse needs a managed private endpoint
  plus "approval from the target workspace private link service owner"; "Cross-region shortcuts aren't
  supported". Creating an MPE to "a private link service for your Fabric tenant isn't supported"
  ([workspace support][ws-support], [MPE create][mpe-create]).
- **Tenant-wide**: on-premises data gateways fail to register; the Capacity Metrics app, OneLake Catalog
  **Govern** tab, Publish to Web, PDF/PowerPoint export and email subscriptions are unsupported; mirroring
  pauses for most sources; tenant migration is blocked; "Fabric supports up to 450 capacities in a tenant
  where Private Link is enabled"; each private endpoint serves one tenant only ([private links][pl]).

## What this settles

- **Confirm whether "Block Public Internet Access" is on.** On → the deploy path cannot be public; agents
  must egress through the VNet and use the tenant/workspace FQDN, with public egress still allowed for
  Entra. Off → a public agent pool works, and private link only accelerates the private clients.
- **Confirm tenant-level or workspace-level private link.** Workspace-level forbids deployment pipelines
  and semantic models, needs the `z{xy}` FQDN and a different DNS zone, so the deployment mechanism and
  every connection string in the work repo change. Tenant-level leaves deployment pipelines usable but
  blocks all public callers.
- **Confirm which private DNS zones are linked to the agent VNet and that the tenant FQDN resolves.**
  If it does not, the fallback is `api.fabric.microsoft.com` plus public egress — which the tenant may
  have forbidden.
- **Confirm the agent subnet can reach `api.fabric.microsoft.com:443` and `login.microsoftonline.com:443`.**
  Without the second, no service principal or federated credential can get a token, private link or not.
- **Confirm what sits between the agent and Fabric (proxy, Zscaler, forced tunnelling).** A proxy in a
  different region is a documented cause of `RequestDeniedByInboundPolicy`; the design must pin egress to
  the capacity's region and resolve FQDNs locally.
- **Confirm every target workspace is on an F SKU.** Workspace-level private link and trusted workspace
  access both reject P SKU and trial; tenant-level private link rejects trial.
- **Confirm the workspaces hold no semantic models or deployment pipelines** before choosing
  workspace-level restriction; otherwise the restriction cannot be enabled at all.
- **Confirm shortcut targets.** Same-tenant OneLake is fine; ADLS/Blob needs Trusted workspace access
  (managed private endpoints don't cover shortcuts yet); cross-tenant is out.
- **Confirm Spark usage and home region.** Spark implies managed VNet, no starter pools, 3–5 minute starts
  and a home-region requirement.
- **Confirm capacity age.** A capacity created as part of the deploy has no private-link path for up to
  24 hours, so the pipeline cannot assume immediate private connectivity.
- **Confirm who holds Fabric administrator plus Azure RBAC on the private endpoint subscription.** None of
  this is workspace-admin self-service at tenant scope, and the workspace path still needs Azure rights.

## What this does not establish

- Any cost figure or Fabric capacity-unit consumption for private link, managed private endpoints,
  managed VNet or trusted workspace access; the docs only point at Azure Private Link pricing.
- GA status for tenant-level private link, workspace-level private link, managed private endpoints or
  managed VNet — none is declared, only the absence of a preview label.
- Whether Entra token acquisition has any private path. The required-URL list is written for the client
  browser, not for an agent, and no private endpoint for `login.microsoftonline.com` is described.
- The mechanism by which `api.fabric.microsoft.com` is allowed from a private-link network; the tables
  assert the result, not the rule.
- Proxy behaviour of the Terraform provider and `fabric-cicd`; no Microsoft page states it.
- Whether deployment pipelines work under *tenant-level* private links — only the workspace-level block
  is documented.
- The work tenant's actual settings, DNS, capacity SKUs and item inventory.

## Sources

| Source | What it was used for | Page date |
| --- | --- | --- |
| [Private links for Fabric][pl] | feature definitions, item-by-item support, limitations, required auth URLs | 2026-10-13 |
| [Set up tenant-level private link][pl-use] | admin requirement, DNS zones, tenant FQDN, disable order | 2025-08-13 |
| [Managed private endpoints][mpe] / [create][mpe-create] | scope, Trial support, shortcut gap, approval flow | 2025-05-12 / 2026-08-20 |
| [Managed VNets][mvn] | automatic provisioning, starter pools, unsupported regions | 2024-05-30 |
| [Trusted workspace access][twa] | GA, F SKU, resource instance rules, what it covers | 2026-08-13 |
| [Workspace-level private links][ws-pl] | FQDN patterns, one PLS per workspace | 2026-05-26 |
| [Workspace-level support][ws-support] | supported/unsupported items, admin APIs, proxy failure | 2026-10-13 |
| [Workspace-level setup][ws-setup] | tenant setting, Azure RBAC role, communication-policy table | 2026-02-04 |
| [Inbound protection overview][inbound] | portal vs REST API access matrix | 2026-01-27 |
| [Protect inbound traffic][pit] | cost and bandwidth statement | 2025-08-13 |
| [Tenant settings index][ts] | exact setting names | 2026-08-28 |
| [Fabric URL allowlist][allow] | endpoints and ports | 2026-02-13 |
| [OneLake access][onelake] | workspace FQDN requirement, regional endpoints | 2026-05-18 |
| [CI/CD network security][cicd] | Git under inbound protection, deployment pipeline block | 2025-12-15 |
| [Linux agent][linux] / [Azure CLI][cli] | proxy bypass URLs, `HTTP_PROXY`/`HTTPS_PROXY` | 2026-09-24 / 2026-02-04 |

[pl]: https://learn.microsoft.com/en-us/fabric/security/security-private-links-overview
[pl-use]: https://learn.microsoft.com/en-us/fabric/security/security-private-links-use
[mpe]: https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-overview
[mpe-create]: https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-create
[mvn]: https://learn.microsoft.com/en-us/fabric/security/security-managed-vnets-fabric-overview
[twa]: https://learn.microsoft.com/en-us/fabric/security/security-trusted-workspace-access
[ws-pl]: https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-overview
[ws-support]: https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-support
[ws-setup]: https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-set-up
[inbound]: https://learn.microsoft.com/en-us/fabric/security/security-inbound-overview
[pit]: https://learn.microsoft.com/en-us/fabric/security/protect-inbound-traffic
[ts]: https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index
[allow]: https://learn.microsoft.com/en-us/fabric/security/fabric-allow-list-urls
[onelake]: https://learn.microsoft.com/en-us/fabric/onelake/onelake-access-api
[cicd]: https://learn.microsoft.com/en-us/fabric/cicd/cicd-security
[linux]: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/linux-agent?view=azure-devops
[cli]: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux

# Which network path does each kind of Fabric traffic take, and what must the agent VMs reach?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the work-repo pipeline design (agent placement, DNS, proxy) and any decision to turn on private links in the work tenant

## Short answer

There is no single path. Control-plane calls go to a public HTTPS endpoint, `api.fabric.microsoft.com`,
which Fabric answers only when the request arrives from a network the tenant allows; data-plane calls
(OneLake, TDS, Spark, shortcuts) are what private links actually carry. A public deploy path works only
while **Block Public Internet Access** is off; once it is on, the agent must egress through the VNet holding
the private endpoint, resolve the FQDN privately, and still reach `login.microsoftonline.com` for tokens.

## Detail

### 1. The five features, named exactly

| Feature (doc wording) | What it isolates | Admin scoping | Cost | Status |
| --- | --- | --- | --- | --- |
| **Tenant-level Private Link** (how-to says **Azure Private Link**, overview **Azure Private Links**) | Inbound, whole tenant: "traffic going *into* your organization's Fabric items" | "You must be a Fabric administrator and have permissions in Azure to create and configure resources such as virtual machines (VMs) and virtual networks (VNets)" | "The cost of private links and the increase of the ExpressRoute bandwidth … might add costs" ([protect inbound][pit]); priced as Azure Private Link, no Fabric CU figure documented | Not labelled preview on any page checked; no page states GA either. Not supported on Trial capacity |
| **Managed private endpoints** | Outbound, from Fabric workloads to *your* data sources behind a firewall | "Users with admin permissions to a Microsoft Fabric workspace can create, view, and delete managed private endpoints" (workspace settings → **Network security**) | No cost statement. Supported on Fabric capacities "including Trial Capacities" | Unlabelled; the Eventstream use is explicitly *(Preview)* |
| **Managed virtual network** | Spark compute: clusters leave the shared VNet for a per-workspace VNet | None — provisioned automatically on first Spark job (Private Link on) or first managed private endpoint | No charge documented, but starter pools are disabled | Unlabelled; not in Switzerland West / West Central US |
| **Trusted workspace access** | Inbound to *storage*: a workspace identity through an ADLS Gen2 / Blob firewall via resource instance rules | Workspace admin creates the workspace identity; "A Contributor on the storage account … can configure resource instance rules or trusted service exception" | No charge documented; F SKU only | "**generally available**", explicitly ([twa]) |
| **Workspace-level private link** | Inbound, one workspace; other workspaces stay public | Fabric admin enables **Configure workspace-level inbound network rules** (off by default); "You must be a workspace admin and have sufficient Azure permissions"; Azure role needs `Microsoft.Fabric/privateLinkServicesForFabric/*` | No cost statement. F SKU only; P SKU and trial unsupported | Unlabelled; dependent items carry their own preview labels |

Three strings name one toggle: **"Tenant-level Private Link"** in the [settings index][ts], **"Azure Private
Link"** in the setup steps, **"Azure Private Links"** in the overview. The docs never say "Allow trusted
workspace access"; the storage-side choices are **resource instance rules** or **trusted service exception**.

### 2. Control plane vs data plane, and whether the REST API is public

Private links protect data traffic; the REST API is governed by a table rather than prose. With tenant
public access **Restricted**, "Public internet → Can I access Fabric REST APIs? **No**", while a "Network
with tenant private link" gets "**Yes, using tenant-specific FQDN or api.fabric.microsoft.com endpoint, and
only if the client allows outbound public access**" ([inbound overview][inbound]). The endpoint is not made
private; the source network is checked, and `api.fabric.microsoft.com` is the host named in four table rows.

The communication-policy API is reachable "using `api.fabric.microsoft.com` endpoint or workspace-specific
FQDN" under tenant-level private link, but **not** over `api.fabric.microsoft.com` from a workspace-private-
link network when tenant access is restricted ([workspace setup][ws-setup], Table 1) — a self-lockout shape:
the API that reopens a workspace is the one the policy can close.

What the docs do **not** say: that `api.fabric.microsoft.com` resolves to a private IP, or why a client on
the private-link network may use the public endpoint. The tenant private API name is
`{tenantId}-api.privatelink.analysis.windows.net` ([setup][pl-use], step 7). Entra stays public:
`login.microsoftonline.com` and `graph.microsoft.com` are "Required for auth", with `aadcdn.msauth.net`,
`msauth.net`, `msftauth.net`, `login.live.com` ([private links][pl]); no private path for Entra is described.

### 3. What actually respects a private endpoint

- **OneLake** — "OneLake supports Private Link", but "Direct calls using OneLake regional endpoints don't
  work via private link"; use the workspace FQDN (`https://<wsid>.z<xy>.dfs.fabric.microsoft.com`) or tenant path ([onelake]).
- **OneLake shortcuts** — supported "when both the shortcut source and target are within the same tenant".
  Cross-tenant shortcuts "aren't supported over Private Link"; external ADLS/S3 needs the account to allow
  private access. Managed private endpoints "do not yet support connections to ADLS Gen2 storage accounts
  and Azure Blob Storage accounts", so firewall-enabled storage uses **Trusted workspace access** ([MPE][mpe]).
- **SQL analytics endpoint / Warehouse TDS** — supported, but add `z{xy}` and use
  `{GUID}-{GUID}.z{xy}.datawarehouse.fabric.microsoft.com`. "Visual query in Warehouse doesn't work when
  the **Block Public Internet Access** tenant setting is enabled" ([private links][pl], [support][ws-support]).
- **Spark** — a managed VNet is created on the first job, "starter pools … are disabled", and custom pools
  "could take up around 3 to 5 minutes to start". Spark fails for tenants whose *home region* lacks Fabric
  Data Engineering even when the capacity region has it ([managed VNets][mvn]).
- **Semantic model refresh** — weakest link. Under workspace-level private link, "Power BI semantic models
  aren't supported" and their presence blocks enabling it. Under tenant-level, if internet access is
  disabled and a model "connects to a Power BI semantic model or Dataflow as a data source, the connection
  fails"; usage metrics refresh also fails. Import-mode ADLS models need **Trusted workspace access** ([twa]).

### 4. What the agent VMs need

- **Position.** The request must arrive from the approved network; a private endpoint exists only inside its
  VNet/peered network. No page names an "agent VNet", but there is an effective one: if public access is
  restricted, an agent outside that VNet is denied by design.
- **DNS.** Tenant: `privatelink.analysis.windows.net`, `privatelink.pbidedicated.windows.net`,
  `privatelink.prod.powerquery.microsoft.com`. Workspace: `privatelink.fabric.microsoft.com`. Link the zone
  to the agent VNet: a new capacity "doesn't support private link until its endpoint is reflected in the
  private DNS zone, which can take up to 24 hours" ([private links][pl], [workspace setup][ws-setup]).
- **Ports.** "Fabric requires only TCP Port 443" for platform and OneLake endpoints; add TCP 1433 for
  `*.datawarehouse.fabric.microsoft.com` and SQL database, TCP 11000–11999 for SQL database under the
  redirect policy, and 5672/5673/9093 only if eventstreams are consumed directly ([allowlist][allow]).
- **Proxy.** `az` is documented: behind a proxy "HTTP_PROXY and HTTPS_PROXY must be set" ([CLI][cli]). The
  agent's bypass list is `https://dev.azure.com`, `https://*.dev.azure.com`, `https://login.microsoftonline.com`,
  `https://management.core.windows.net`, `https://download.agent.dev.azure.com`; and "your build pipeline and
  scripts must still handle bypassing your web proxy for each task and tool you run" ([Linux agent][linux]).
- **A proxy can break private link.** "Network proxies and traffic interceptors (for example, Zscaler) can
  prevent traffic from reaching the workspace's private endpoint … when users or network egress points are
  in a different Azure region than the workspace's capacity", giving `RequestDeniedByInboundPolicy` ([support][ws-support]).
- **Terraform provider / fabric-cicd.** Proxy behaviour could not be established from Microsoft sources; test the agent image.

### 5. Known unsupported or caveated

- **Deployment pipelines**: "aren't currently supported for workspace with inbound access protection", and a
  workspace assigned to a pipeline can't be restricted ([CI/CD security][cicd]). Tenant-level is unstated.
- **Git integration**: allowed by default under inbound protection, but Git features "must do so from
  within the approved VNet. … This restriction also applies to the Git APIs"; "Branching out is blocked" ([cicd]).
- **Copilot**: "isn't currently supported for Private Link or closed network environments"; Copilot in
  Dataflow Gen2 is separately unsupported under workspace-level private links ([private links][pl]).
- **Unsupported items** in a workspace-private-link workspace: deployment pipelines and semantic models —
  if present, "inbound public access can't be restricted"; item sharing, workspace monitoring and shortcut
  transforms are also unsupported ([support][ws-support]).
- **Cross-workspace**: another restricted workspace's lakehouse needs an MPE plus "approval from the target
  workspace private link service owner"; "Cross-region shortcuts aren't supported"; an MPE to "a private link
  service for your Fabric tenant isn't supported" ([support][ws-support], [MPE create][mpe-create]).
- **Tenant-wide**: on-premises data gateways fail to register; Capacity Metrics app, OneLake Catalog
  **Govern**, Publish to Web, PDF/PowerPoint export and email subscriptions are unsupported; mirroring pauses;
  tenant migration is blocked; "up to 450 capacities" per private-link tenant; one tenant per endpoint ([pl]).

## What this settles

- **Is "Block Public Internet Access" on?** On → no public deploy path; agents must egress via the VNet
  and use the tenant/workspace FQDN, with public egress still allowed for Entra. Off → a public pool works.
- **Tenant-level or workspace-level?** Workspace-level forbids deployment pipelines and semantic models,
  needs `z{xy}` FQDNs and a different DNS zone, so the mechanism and every connection string change.
  Tenant-level keeps deployment pipelines usable but blocks all public callers.
- **Which DNS zones are linked to the agent VNet, and does the tenant FQDN resolve?** If not, the fallback
  is `api.fabric.microsoft.com` plus public egress — which the tenant may have forbidden. And can the agent
  reach `api.fabric.microsoft.com:443` and `login.microsoftonline.com:443`? Without the second, no service
  principal or federated credential gets a token, private link or not.
- **What sits between agent and Fabric (proxy, Zscaler, forced tunnelling)?** A proxy in another region is
  a documented cause of `RequestDeniedByInboundPolicy`; pin egress to the capacity region and resolve
  FQDNs locally.
- **Is every target workspace on an F SKU and free of semantic models or deployment pipelines?**
  Workspace-level private link rejects P SKU and trial, and those two item types block the restriction
  entirely; tenant-level private link rejects trial.
- **What do shortcuts target?** Same-tenant OneLake is fine; ADLS/Blob needs Trusted workspace access (MPEs
  don't cover shortcuts yet); cross-tenant is out.
- **Is Spark used, and is the tenant home region supported?** Spark implies managed VNet, no starter pools
  and a home-region requirement. **How old is the capacity?** A capacity created by the deploy has no
  private path for up to 24 hours, so the pipeline cannot assume immediate private connectivity.
- **Who holds Fabric administrator plus Azure RBAC on the endpoint subscription?** None of this is
  workspace-admin self-service at tenant scope, and the workspace path still needs Azure rights.

## What this does not establish

- Any cost figure or Fabric capacity-unit consumption for private link, managed private endpoints,
  managed VNet or trusted workspace access; the docs only point at Azure Private Link pricing.
- GA status for tenant-level private link, workspace-level private link, managed private endpoints or
  managed VNet — none is declared, only the absence of a preview label.
- Whether Entra token acquisition has any private path. The required-URL list is written for the client
  browser, not an agent, and no private endpoint for `login.microsoftonline.com` is described.
- The mechanism by which `api.fabric.microsoft.com` is allowed from a private-link network; the tables
  assert the result, not the rule.
- Whether deployment pipelines work under *tenant-level* private links — only the workspace-level block is
  documented.
- The work tenant's actual settings, DNS, capacity SKUs and item inventory.

## Sources

| Source | What it was used for | Page date |
| --- | --- | --- |
| [Private links for Fabric][pl] | definitions, item-by-item support, limitations, auth URLs | 2026-10-13 |
| [Set up tenant-level private link][pl-use] | admin requirement, DNS zones, tenant FQDN, disable order | 2025-08-13 |
| [Managed private endpoints][mpe] / [create][mpe-create] | scope, Trial support, shortcut gap, approval flow | 2025-05-12 / 2026-08-20 |
| [Managed VNets][mvn] | automatic provisioning, starter pools, regions | 2024-05-30 |
| [Trusted workspace access][twa] | GA, F SKU, resource instance rules, coverage | 2026-08-13 |
| [Workspace-level support][ws-support] | item support, admin APIs, proxy failure | 2026-10-13 |
| [Workspace-level setup][ws-setup] | tenant setting, Azure RBAC, policy-API table | 2026-02-04 |
| [Inbound protection overview][inbound] | portal vs REST API access matrix | 2026-01-27 |
| [Protect inbound traffic][pit] | cost and bandwidth statement | 2025-08-13 |
| [Tenant settings index][ts] | exact setting names | 2026-08-28 |
| [Fabric URL allowlist][allow] | endpoints and ports | 2026-02-13 |
| [OneLake access][onelake] | workspace FQDN, regional endpoints | 2026-05-18 |
| [CI/CD network security][cicd] | Git under inbound protection, pipeline block | 2025-12-15 |
| [Linux agent][linux] / [Azure CLI][cli] | proxy bypass URLs, `HTTP_PROXY`/`HTTPS_PROXY` | 2026-09-24 / 2026-02-04 |

[pl]: https://learn.microsoft.com/en-us/fabric/security/security-private-links-overview
[pl-use]: https://learn.microsoft.com/en-us/fabric/security/security-private-links-use
[mpe]: https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-overview
[mpe-create]: https://learn.microsoft.com/en-us/fabric/security/security-managed-private-endpoints-create
[mvn]: https://learn.microsoft.com/en-us/fabric/security/security-managed-vnets-fabric-overview
[twa]: https://learn.microsoft.com/en-us/fabric/security/security-trusted-workspace-access
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

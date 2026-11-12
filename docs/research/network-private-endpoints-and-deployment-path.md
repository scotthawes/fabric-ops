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
  Tenant-level blocks all public callers. **Corrected 2026-11-12:** the previous sentence asserted that
  tenant-level "keeps deployment pipelines usable". That has no source — Learn documents the
  deployment-pipeline restriction only for *workspace*-level private link, and says nothing either way
  for tenant level, so it is unestablished rather than settled. See the answered block below.
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

## Answered 2026-11-12 — are deployment pipelines supported under tenant-level private link?

**Learn does not say.** The deployment-pipeline block is documented only for *workspace-level* private
link. The tenant-level pages mention deployment pipelines nowhere — not in the supported-experience
list, not in the "Other considerations and limitations" list — so the workspace-level block must not be
read across, and there is equally no documented statement that tenant level is fine. Documentation
settles only this: the restriction Microsoft chose to write down is workspace-scoped.

### The only sentences that mention it, all workspace-scoped

- "The following item types aren't currently supported in workspaces enabled with workspace-level private links: … **Deployment pipelines**" ([workspace-level support][ws-support], ms.date 2026-10-13).
- "If any workspace in a deployment pipeline is set to deny public access (restricted), deployment pipelines can't connect to that workspace. Configuring inbound restriction is blocked for any workspace that is assigned to a pipeline." (same page)
- "Deployment pipelines aren't currently supported for workspace with inbound access protection." Repeated in that page's limitations list as "Deployment pipelines are currently not supported with workspace inbound access protection." ([CI/CD network security][cicd], ms.date 2025-12-15, updated 2026-09-29)

Every sentence says *workspace*. None says *tenant*.

### What each page checked contains (all read 2026-11-12)

| Page | ms.date (updated) | Deployment pipelines mentioned? |
| --- | --- | --- |
| [Tenant-level overview][pl] | 2026-10-13 (2026-10-15) | No. 16 experience sections and 17 limitation bullets; neither names them |
| [Tenant-level setup][pl-use] | 2025-08-13 (2026-09-29) | No. "some unsupported Fabric items become disabled … learn the full list" → that list omits them |
| [Workspace-level support][ws-support] | 2026-10-13 (2026-10-15) | Yes — unsupported items list and the management-options note |
| [Workspace-level overview][ws-overview] | 2026-05-26 (2026-05-27) | No (FQDN/resolution table only; its "can only connect to the specific workspace" row is the mechanism that bites) |
| [Inbound overview][inbound] | 2026-01-27 (2026-10-15) | No. Table 1's nine rows have no pipeline row |
| [CI/CD network security][cicd] | 2025-12-15 (2026-09-29) | Yes — the two workspace-scoped callouts above |
| [Deployment pipelines intro][dp-intro] | 2026-09-24 (2026-11-06) | No. Supported-items list only |
| [Deployment process][dp-process] | 2026-09-24 (2026-11-02) | No. Its "Considerations and limitations" is general/semantic-model/dataflow/DLP — zero network content |
| [Assign a workspace][dp-assign] | 2025-12-15 (2026-11-02) | No. Six assignment conditions, none about networks |
| [Pipeline automation API][dp-auto] | 2026-09-24 (2026-09-29) | No. API limitations are dataflows and Power BI options |
| [CI/CD workflow options][dp-manage] | 2026-10-18 (2026-10-19) | No. Option 3 (deployment pipelines) carries no network caveat |
| [Troubleshoot CI/CD][dp-trouble] | 2026-09-23 | No. Zero occurrences of "private link" or "network" |
| [Security overview][sec-ov] / [fundamentals][sec-fund] | — | No. Zero occurrences of "deployment pipeline" |

Also checked and negative: `security-workspace-level-private-links-set-up` (2026-02-04), which has 36
occurrences of "private link" and none of "deployment pipeline".

### Why the tenant case is a different question, not a weaker version of the same one

1. Tenant-level blocking is conditional on **scenario support**, not on item type: "Traffic from the
   virtual network targeting endpoints and scenarios that *don't* support private links are blocked by
   the service" ([pl]). Whether deployment pipelines is such a scenario is precisely the unstated part.
2. The setup page defers the list to the article that does not contain it: "When you turn on *Block
   Internet Access*, some unsupported Fabric items become disabled. Learn the full list of limitations
   and considerations in About private links" ([pl-use]).
3. At workspace level the pipeline fails for **two independent reasons** — semantic models *and*
   deployment pipelines are both unsupported ([ws-support]) — whereas tenant level supports semantic
   models, with connection caveats ([pl]). The confound is absent at tenant level, so a workspace-level
   failure tells you nothing about it.

One false positive to avoid: the tenant-level overview has a section headed "### Pipeline". It is data
pipelines — "use the pipeline to load data from any data source with public endpoints into a
private-link-enabled Microsoft Fabric lakehouse" — not deployment pipelines.

### Mechanism

Undocumented, but one endpoint-shape fact is worth recording and one inference is not. The only
mechanistic wording is "deployment pipelines **can't connect to that workspace**", which casts the
pipeline service as an inbound *client* of the workspace rather than as the caller being restricted. No
page states where that connection originates, which hostname it uses (workspace FQDN, tenant FQDN or
`api.fabric.microsoft.com`), or whether a control-plane call from outside the VNet is involved. The
"control-plane API from outside the VNet" explanation is plausible and consistent with the wording, but
it is not documented; do not record it as established.

The endpoint shape is documented and is a third case. The workspace-level page states the classifying
rule — "APIs with endpoints containing `v1/workspaces/{workspaceId}` support workspace-level private
links because they operate within the context of a specific workspace. In contrast, admin APIs use
`admin/workspaces/{workspaceId}` … and aren't covered" ([ws-support]) — and the census shows the
deployment-pipeline operations are neither: they are tenant-scoped,
`POST /v1/deploymentPipelines/{deploymentPipelineId}/deploy` (`DeploymentPipelines_DeployStageContent`)
and siblings. That is consistent with the restriction being written as an explicit item-type rule rather
than falling out of the FQDN rule, and it is why the endpoint shape alone cannot settle the tenant case.

### A contradiction this note already carries

§"What this settles" used to state "Tenant-level keeps deployment pipelines usable but blocks all
public callers", while §"What this does not establish" states that the tenant-level case is
unestablished. The first sentence had no source behind it; it was corrected in place on 2026-11-12.
Treat deployment pipelines under tenant-level private link as **open**, and do not use "pipelines keep
working" as an argument for choosing tenant over workspace level.

### What remains unestablished

Whether the deployment pipeline service can create, assign and deploy at all when **Block Public
Internet Access** is on at tenant scope. The observation that settles it — on a tenant with
tenant-level private link and public access restricted, using an F-capacity workspace that holds no
semantic models, so the workspace-level confound cannot apply:

1. Create a pipeline and assign that workspace to the dev stage. Record the error code if it refuses:
   `InboundRestrictionNotEligible` would mean the workspace-eligibility rule is being applied at tenant
   scope; `RequestDeniedByInboundPolicy` would mean the *call* was judged out-of-network.
2. Deploy to an empty test stage, and call
   `POST /v1/deploymentPipelines/{deploymentPipelineId}/deploy` (`DeploymentPipelines_DeployStageContent`),
   once from inside the VNet and once from a public host. Succeeds inside / fails outside confirms the
   tenant path is honoured for the pipeline service; failing in both means the pipeline service is one of
   the "scenarios that don't support private links".
3. Note whether the workspace that a clean deploy creates is itself reachable afterwards — the docs say
   a clean deploy creates a workspace on the capacity ([dp-process]) and say nothing about its network
   posture.

## Answered 2026-11-12 — do the Terraform provider and `fabric-cicd` honour `HTTP_PROXY`?

**Yes, both — by inheritance rather than by contract.** Neither documents proxy support; both end up
on a client whose default reads the standard environment variables. That distinction matters: it works
today and nothing upstream promises it will keep working.

### `fabric-cicd` — yes, via `requests`

`FabricEndpoint` is handed the `requests` module and calls it directly: `self.requests = requests_module`
(`src/fabric_cicd/_common/_fabric_endpoint.py:64`), then `self.requests.request(method=…, url=…, headers=…,
json=…, files=…)` (`:118`). `trust_env` is not set anywhere in `src/` — checked, no occurrences — so
`requests` keeps its default `trust_env=True`, which resolves `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY`
from the environment per call. Token acquisition goes through `azure-identity`, which uses the same
stack, so there is no second, proxy-blind path. Read at v1.4.0, commit `59a0fe86`.

### Terraform provider — yes, via azcore's default transport

The provider constructs its client as `fabric.NewClient(credential, endpoint, &clientOptions)`
(`internal/provider/client/fabric.go:37`) and never sets `ClientOptions.Transport` — no `Transport:` field
appears in non-test provider or SDK code. azcore's pipeline falls back to `transport.DefaultHTTPClient`
when `Transport` is nil (`sdk/azcore/runtime/pipeline.go:92-96` at `azcore v1.24.0`, the version the SDK
pins), and that client's transport is built with `Proxy: http.ProxyFromEnvironment`
(`sdk/internal/transport/transport.go:20`). So `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY` are honoured by
the provider process. Read at provider commit `d0a6a91`.

### What this does not establish

- **Not a contract.** Neither Microsoft page nor either repository's documentation states proxy support.
  An upstream change that supplies its own `Transport`, or sets `trust_env=False`, breaks it silently.
  Treat it as an environmental fact to re-check, not a feature to rely on.
- **Terraform's own traffic is separate.** Provider installation and registry calls are Terraform core's,
  governed by the same variables but in a different process; a provider that proxies says nothing about
  whether `terraform init` did.
- **`NO_PROXY` still has to be right for the private-link path.** A proxy honoured is also a proxy that
  intercepts; the bypass list in this note's allowlist section is what keeps VNet traffic off it.

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
[ws-overview]: https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-overview
[dp-intro]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines
[dp-process]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process
[dp-assign]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/assign-pipeline
[dp-auto]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/pipeline-automation-fabric
[dp-manage]: https://learn.microsoft.com/en-us/fabric/cicd/manage-deployment
[dp-trouble]: https://learn.microsoft.com/en-us/fabric/cicd/troubleshoot-cicd
[sec-ov]: https://learn.microsoft.com/en-us/fabric/security/security-overview
[sec-fund]: https://learn.microsoft.com/en-us/fabric/security/security-fundamentals
[linux]: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/linux-agent?view=azure-devops
[cli]: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux

# Is the legacy Power BI REST API a route around the three things Fabric cannot automate?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the "manual steps" list in the deploy design — gateway binding, semantic-model RLS, sensitivity labels

## Short answer

Half the premise holds, and the half that fails fails in an unexpected direction: the gap is not filled by
the legacy API but by the **Fabric** API. `SemanticModel Items - Bind Semantic Model Connection` is a
service-principal-supported Fabric operation that binds a model in a Fabric workspace to an
`OnPremisesGateway`, `VirtualNetworkGateway` or `ShareableCloud` connection, so gateway binding is
automatable without `api.powerbi.com`. Gateway *administration* is partly API, partly PowerShell, never
fully REST. RLS is automatable only over the XMLA endpoint, labels only for Power BI artifact types and
probably not as a service principal, and app publishing not at all. The legacy API is a fallback for
report rebinding, refresh and takeover — not the recommended route.

## Detail

### 1. Gateway binding — automatable, but through Fabric

`SemanticModel Items - Bind Semantic Model Connection` (service `SemanticModel`, v1, page updated 2026-09-15):

```http
POST https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/semanticModels/{semanticModelId}/bindConnection
{"connectionBinding":{"id":"<connectionId>","connectivityType":"OnPremisesGateway",
                      "connectionDetails":{"type":"SQL","path":"server;database"}}}
```

- Scopes `SemanticModel.ReadWrite.All` or `Item.ReadWrite.All`; "Service principal and Managed identities: **Yes**".
- Permissions: **"The caller must be the owner of the semantic model."**
- `connectivityType` covers every case in the gateway note: `ShareableCloud`, `PersonalCloud`,
  `OnPremisesGateway`, `OnPremisesGatewayPersonal`, `VirtualNetworkGateway`,
  `StreamingVirtualNetworkGateway`, `Automatic`, and `None` to unbind.
- "This API does not support bulk operations" — one data source reference per call.
- Verification endpoint: `Items - List Item Connections`, `GET /v1/workspaces/{w}/items/{i}/connections`,
  returns `connectivityType`, `id`, `gatewayId` (updated 2026-11-10).

Legacy equivalent, for contrast: `Bind To Gateway In Group` `POST /groups/{groupId}/datasets/{datasetId}/Default.BindToGateway`
with `gatewayObjectId` + `datasourceObjectIds[]`, scope `Dataset.ReadWrite.All`, SP-profile callable — but
**"Only supports the on-premises data gateway"**, so it cannot bind a VNet gateway at all, and it demands
"Add the API caller principal as a data source user on the gateway". Re-pointing sources is
`Update Datasources In Group` (`POST .../Default.UpdateDatasources`, `Dataset.ReadWrite.All`, "The user must
be the dataset owner"), which excludes datasets "created or modified using the public XMLA endpoint",
cannot change source type, and skips parameterised connection strings.

**Verdict: automatable.** Two conditions: deploy and bind must run as the same identity (ownership), and
credentials stay a separate step. **Dataflows are not covered**: neither API has a bind operation.

### 2. Gateway administration — partially

The REST `Gateways` group is nine operations, all about data sources: Add Datasource User, Create Datasource,
Delete Datasource, Delete Datasource User, Get Datasource, Get Datasources, Get Datasource Status, Get
Datasource Users, Get Gateway, Get Gateways, Update Datasource. **No create-gateway and no member operations.**

| Step | Route | Constraint |
| --- | --- | --- |
| Register a gateway | installer, no API found | could not establish any REST/PowerShell registration path |
| Add a datasource | `Create Datasource` `POST /v1.0/myorg/gateways/{gatewayId}/datasources` | "the user must have gateway admin permissions", `Dataset.ReadWrite.All`, "Virtual network (VNet) and Cloud gateways aren't supported", "OAuth2 as a credential type isn't supported", credentials encrypted with the gateway public key (`encryptedConnection: Encrypted`, `encryptionAlgorithm: RSA-OAEP`) |
| Update datasource credentials | `Update Datasource` (Gateways) | same on-premises-only restriction |
| Add a member / role | PowerShell `Add-DataGatewayClusterUser -GatewayClusterId -PrincipalObjectId -Role Admin\|ConnectionCreator\|ConnectionCreatorWithReshare` | Example 4 passes a **service principal** object ID, so it is scriptable; `-Scope Organization` for tenant admin |

### 3. RLS — partially, over XMLA, never over REST

No role operation exists in either API: Fabric `SemanticModel Items` has seven operations (bind, create,
delete, get, get definition, list, update definition, update) and Power BI `Datasets` has none. Documented
route: XMLA read-write plus TMSL — "role object definitions can be scripted by using TMSL to
create or modify the Roles object", executed "in SSMS or with the `Invoke-ASCmd` PowerShell cmdlet". Requires
the capacity workload's **XMLA Endpoint** set to `Read Write`, the tenant setting **Allow XMLA endpoints and
Analyze in Excel with on-premises semantic models**, and "Workspace contributors and above ... are
effectively the same as Analysis Services database admins".

Documented limits (XMLA doc, ms.date 2026-02-05): "The only permission for a role that can be set for
semantic models is Read permission"; "**Service Principals do not work with RLS and OLS, and cannot be added
as model role members**"; Build permission is still required for read. So an SP can create roles and add
*user* members, but can never be a role member and is never filtered by RLS. XMLA write is GA; the cost is
that models touched this way become ineligible for `Update Datasources`.

### 4. Sensitivity labels — partial, and the "yes" is narrow

`InformationProtection SetLabelsAsAdmin` `POST /v1.0/myorg/admin/informationprotection/setLabels` (and
`RemoveLabelsAsAdmin`). `artifacts` accepts exactly `dashboards`, `reports`, `datasets`, `dataflows`;
scope `Tenant.ReadWrite.All`; "Users must be Fabric administrators"; "Maximum 25 requests per hour", 2,000
artifacts per request; per-item status `Succeeded`, `Failed`, `NotFound`, `InsufficientUsageRights`,
`FailedToGetUsageRights`.

- **Power BI artifacts only.** A lakehouse, notebook, warehouse or mirrored database cannot be addressed;
  `Create Item`'s `sensitivityLabelSettings` remains the only creation-time path for those.
- **Service principal: could not establish.** setLabels is absent from the read-only admin API list in
  *Enable service principal authentication for admin APIs*, and the "admin APIs used for updates" switch is
  scoped to Fabric admin APIs. The requirement is worded as a Fabric administrator *user*. Do not design on it.

### 5. Refreshes and schedules — the legacy endpoints are current, not deprecated

| Task | Operation | Notes |
| --- | --- | --- |
| Trigger | `Refresh Dataset In Group` `POST /groups/{g}/datasets/{d}/refreshes` | `Dataset.ReadWrite.All`, SP-profile; "enhanced refresh ... only if a request payload other than `notifyOption` is set"; 8/day on shared capacity, resource-bound on capacity |
| History | `Get Refresh History In Group` `GET .../refreshes` | |
| Schedule | `Update Refresh Schedule In Group` `PATCH .../refreshSchedule` | "The user must be the dataset owner"; "Service principals only support the `NoNotification` value" |

Neither is marked deprecated. The only deprecation found in this area is `Set All Dataset Connections In
Group` ("This API call is deprecated and no longer supported"). The Fabric job scheduler
(`Run On Demand Item Job`, `POST /v1/workspaces/{w}/items/{i}/jobs/{jobType}/instances`, `Item.Execute.All`,
SP supported) exists but is generic, and no page read documents a semantic-model refresh job type; the
identity-support article warns a `jobType` fails when the underlying item type does not support the identity.
**Could not establish** that semantic models are covered — treat Power BI as the route.

### 6. Report rebinding and dataset takeover — both yes

- `Rebind Report In Group` `POST /v1.0/myorg/groups/{g}/reports/{r}/Rebind`, body `{"datasetId":"..."}`.
  Requires **Write** on the report *and* **Build** on the target dataset; scope `Report.ReadWrite.All`;
  SP-profile callable. Cross-workspace: "a shared dataset will be created in the report's workspace".
  "Paginated reports are not supported." No Fabric equivalent — `Report Items` has eight operations.
- `Take Over In Group` `POST /v1.0/myorg/groups/{g}/datasets/{d}/Default.TakeOver` still exists,
  `Dataset.ReadWrite.All`, SP-profile callable. Service principals still cannot use **My workspace**.

### 7. Publishing apps — no

The Power BI `Apps` group is read-only: Get App, Get Apps, Get Dashboard, Get Dashboards, Get Report,
Get Reports, Get Tile, Get Tiles — eight GETs, no publish or update. Publishing is described only as portal
steps (Create app → Setup → Content → Audience → Publish app), with the caveats living in that UI ("You must
still manage content visibility of new content that you add to a workspace app manually through audience
management"). Fabric has no app-publish operation. **Not possible headlessly.**

### 8. Recommended route, or fallback?

Fallback, and only for what Fabric genuinely lacks: rebind, refresh trigger/history/schedule, takeover,
admin labelling. The costs of crossing over: a second token audience (Fabric scopes are
`https://api.fabric.microsoft.com/<scope>`; Power BI endpoints sit behind the "Power BI Service" resource —
the `analysis.windows.net/powerbi/api` audience is conventional but **could not establish** it on a page read
today); a second vocabulary ("Some of the Power BI APIs refer to workspaces as groups"); a different set of
tenant switches (`Service principals can call Fabric public APIs` versus the two **Admin API settings**); no
Fabric support statement extending to these endpoints; and deprecation precedent. Where both exist, prefer Fabric.

## What this settles

- **Move from manual to automatable:** gateway binding for semantic models (Fabric `bindConnection`, deploy
  and bind as one identity); gateway datasource creation and credential update; gateway membership and role
  assignment (DataGateway PowerShell, accepts an SP); refresh trigger, history and schedule; report rebind;
  dataset takeover; RLS role creation and user membership via TMSL over XMLA read-write; post-deploy
  verification of bindings via `List Item Connections`.
- **Stays manual:** gateway installation and registration; dataflow gateway binding (no operation in either
  API); adding a service principal to an RLS role (documented as impossible — use groups or dynamic RLS);
  labels on Fabric-native items; labels as a service principal (unverified, assume no); publishing and
  updating workspace apps.

## What this does not establish

- Whether `bindConnection` applies to Direct Lake/OneLake-backed models, or only to models with an external
  connection reference; and whether "owner" is satisfied by the service principal that `fabric-cicd` deployed
  with, or requires explicit ownership transfer.
- Whether a model modified over XMLA can still be bound with `bindConnection`, given `Update Datasources`
  refuses exactly those models.
- That a service principal can call `setLabels` — no page confirms or denies it.
- The literal legacy token audience; and the F-SKU floor for XMLA read-write (the page says "assigned to a
  capacity" without naming a minimum).
- Any API route to create a gateway registration, or to add a machine to an existing cluster.

## Sources

| Source | What it was used for |
| --- | --- |
| [SemanticModel Items](https://learn.microsoft.com/en-us/rest/api/fabric/semanticmodel/items/) (updated 2025-09-10) and [Bind Semantic Model Connection](https://learn.microsoft.com/en-us/rest/api/fabric/semanticmodel/items/bind-semantic-model-connection) (updated 2026-09-15) | the Fabric bind operation, ownership requirement, scopes, identity support, `ConnectivityType` enum |
| [List Item Connections](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/list-item-connections) (updated 2026-11-10) | `connectivityType` / `gatewayId` verification endpoint |
| [Datasets group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/) (updated 2026-09-15) | group-less vs workspace-qualified routes, operation list, absence of RLS operations |
| [Bind To Gateway In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/bind-to-gateway-in-group) and [Update Datasources In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/update-datasources-in-group) (both 2025-03-25) | on-premises-only limitation, `datasourceObjectIds`, XMLA and source-type restrictions |
| [Set All Dataset Connections In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/set-all-dataset-connections-in-group) (2025-02-05) | the one explicit deprecation |
| [Refresh Dataset In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/refresh-dataset-in-group) and [Update Refresh Schedule In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/update-refresh-schedule-in-group) (both 2025-02-05) | refresh limits, owner requirement, `NoNotification` for SPs |
| [Rebind Report In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/reports/rebind-report-in-group) and [Take Over In Group](https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/take-over-in-group) (both 2025-02-05) | rebind permissions and cross-workspace behaviour; takeover still present |
| [Gateways group](https://learn.microsoft.com/en-us/rest/api/power-bi/gateways) (2022-09-14) and [Create Datasource](https://learn.microsoft.com/en-us/rest/api/power-bi/gateways/create-datasource) (2026-05-20) | nine operations, no members/create; gateway-admin permission, credential encryption, VNet/OAuth2 exclusions |
| [Add-DataGatewayClusterUser](https://learn.microsoft.com/en-us/powershell/module/datagateway/add-datagatewayclusteruser) (2025-06-05) | gateway roles, service principal example, `-Scope Organization` |
| [Dataflows group](https://learn.microsoft.com/en-us/rest/api/power-bi/dataflows) (2026-01-25), [Dataflow Items](https://learn.microsoft.com/en-us/rest/api/fabric/dataflow/items/) (2025-09-17), [Report Items](https://learn.microsoft.com/en-us/rest/api/fabric/report/items/) (2024-07-31) | absence of dataflow bind and report rebind operations |
| [Apps group](https://learn.microsoft.com/en-us/rest/api/power-bi/apps) (2022-05-10) and [Publish a workspace app](https://learn.microsoft.com/en-us/power-bi/collaborate-share/service-create-distribute-apps) (2026-09-24) | read-only app API; publish is a portal flow |
| [SetLabelsAsAdmin](https://learn.microsoft.com/en-us/rest/api/power-bi/admin/information-protection-set-labels-as-admin) (2025-03-25) and [Set or remove labels programmatically](https://learn.microsoft.com/en-us/fabric/governance/service-security-sensitivity-label-inheritance-set-remove-api) (2023-09-12) | four artifact types, `Tenant.ReadWrite.All`, 25/hour, statuses, "must be Fabric administrators" |
| [XMLA endpoint](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-premium-connect-tools) (2026-02-05) and [Automate with service principals](https://learn.microsoft.com/en-us/fabric/enterprise/powerbi/service-premium-service-principal) (2022-11-16) | TMSL roles, `Invoke-ASCmd`, XMLA read-write settings, SP/RLS exclusion |
| [Row-level security](https://learn.microsoft.com/en-us/fabric/security/service-admin-row-level-security) (2026-05-13) | "Service principals can't be added to an RLS role" |
| [Enable SP auth for admin APIs](https://learn.microsoft.com/en-us/fabric/admin/enable-service-principal-admin-apis) (2026-06-26) and [Developer admin settings](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-developer) (2026-04-08) | the SP admin-API allow-lists and the two switches |
| [Job Scheduler](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler) (2025-03-03), [Run On Demand Item Job](https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler/run-on-demand-item-job) (2026-09-15), [Identity support](https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support) (2024-08-04) | generic jobType, SP support, unsupported-item warning |
| [Fabric scopes](https://learn.microsoft.com/en-us/rest/api/fabric/articles/scopes) (2025-02-03) and [Fabric REST quickstart](https://learn.microsoft.com/en-us/rest/api/fabric/articles/get-started/fabric-api-quickstart) (2026-07-28) | `https://api.fabric.microsoft.com/<scope>` audience |
| [Embed with service principal](https://learn.microsoft.com/en-us/power-bi/developer/embedded/embed-service-principal) (2025-05-12) | SP cannot use My workspace; legacy developer-setting names |

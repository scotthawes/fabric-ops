# What does the Terraform provider surface for Microsoft Fabric actually cover?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** ADR [0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md)'s boundary table; the work repo's
  `required_providers` block, its auth story and its permission run-book
- **Sibling note:** [`terraform-operating-model.md`](terraform-operating-model.md) owns layout, ordering, import,
  drift, deletion, upgrades and testing. This note owns *what exists*, *what it can do*, *who may do it*, *what state
  means*.

## Short answer

Two providers, two object classes. `hashicorp/azurerm` **5.13.0** creates the capacity, because a capacity is an
Azure resource (`Microsoft.Fabric/capacities`); `microsoft/fabric` **1.15.1** manages everything *inside* Fabric and
cannot create a capacity at all — `fabric_capacity` is a data source only. The Fabric provider is broad (71
resources, 136 data sources, 15 resources behind `preview = true`) and its authentication is complete: secret,
certificate, **OIDC / workload identity federation**, Azure CLI, managed identity. Its weakness is not coverage, it
is support: Microsoft states it is **NOT** covered by Fabric or Microsoft support policies.

## Detail

### 1. The split, the versions, and the minimum Terraform

| | `hashicorp/azurerm` | `microsoft/fabric` |
| --- | --- | --- |
| Source address | `registry.terraform.io/hashicorp/azurerm` | `registry.terraform.io/microsoft/fabric` |
| Version relevant to Fabric | **5.13.0**, published 2026-11-05 | **1.15.1**, published 2026-11-11 (registry tier "partner") |
| Owns | the F SKU: `azurerm_fabric_capacity` | workspaces, accesses, domains, tenant settings, connections, Git binding, item shells |
| Terraform floor | none stated; README: "we recommend using the latest version of Terraform Core" | "**Terraform >= 1.8.x** (>= 1.11.x preferred)"; example `required_version = ">= 1.8, < 2.0"` |
| Auth | AzureRM's own set (`use_oidc`, `use_msi`, …) | a separate implementation, not a wrapper — §3 |

The floor that binds the repo is `>= 1.8, < 2.0`. One wrinkle: the Fabric provider's own capacity guide says
Terraform "can also help you create and manage a Fabric Capacity, but **not through this specific provider**" and
points at **AzAPI**; it never mentions `azurerm_fabric_capacity`. Microsoft publishes two Terraform paths to the same
Azure resource (`docs/guides/fabric_capacity_setup.md` @ v1.15.1).

### 2. Complete inventory of `microsoft/fabric` v1.15.1

**How completeness was established:** git tag `v1.15.1` (the release commit, not `main`) holds exactly 71 files in
`docs/resources/` and 136 in `docs/data-sources/`, and the registry serves that version. Every entry below is one of
those files. There is **no** `fabric_capacity` *resource* — capacity is a data source only, the single most
important asymmetry in the surface.

**Control-plane resources (33).** `(prev)` = preview-gated; `(no SP)` = no service-principal support.

| Resource | Manages | Resource | Manages |
| --- | --- | --- | --- |
| `fabric_workspace` | the workspace, `capacity_id`, identity | `fabric_workspace_role_assignment` | one principal, one role |
| `fabric_workspace_git` | Git branch binding | `fabric_workspace_network_communication_policy` | in/outbound access |
| `fabric_workspace_inbound_azure_resource_rules` | Azure→workspace allow-list | `fabric_workspace_outbound_cloud_connection_rules` | allowed cloud connections |
| `fabric_workspace_outbound_gateway_rules` | allowed gateways | `fabric_workspace_git_outbound_policy` | Git traffic leaving the region |
| `fabric_workspace_firewall_rules` | inbound IP allow-list | `fabric_workspace_managed_private_endpoint` | private endpoint to a data source |
| `fabric_workspace_encryption` (prev) | customer-managed key | `fabric_domain` | tenant governance domain/subdomain |
| `fabric_domain_role_assignments` | `Admins`/`Contributors` | `fabric_domain_workspace_assignments` (prev) | workspaces→domain |
| `fabric_tenant_setting` | one setting by `setting_name` | `fabric_tag` | tenant/domain tag |
| `fabric_folder` (prev) | workspace folders | `fabric_onelake_data_access_security` (prev) | OneLake roles and rules |
| `fabric_connection` | cloud/on-prem connection | `fabric_connection_role_assignment` | who may use it |
| `fabric_gateway` | gateway, VNet members | `fabric_gateway_role_assignment` | who may use it |
| `fabric_deployment_pipeline` | pipeline and stages | `fabric_deployment_pipeline_role_assignment` | pipeline `Admin` |
| `fabric_spark_workspace_settings` | runtime, pool defaults | `fabric_spark_custom_pool` | a Spark pool |
| `fabric_spark_environment_settings` | published libs/compute | `fabric_warehouse_sql_audit_settings` | SQL audit on/off |
| `fabric_org_app` | organisational app | `fabric_org_app_audience` | its audience |
| `fabric_external_data_share` | share to an external tenant | `fabric_item_job_scheduler` | schedule on an item job |
| `fabric_shortcut` | OneLake shortcut in a lakehouse | | |

**Item resources (38).** Each manages one item *shell*; definitions are HCL `definition` blocks pointing at source
files, which is why ADR 0003 keeps items in `fabric-cicd`. Analytics: `fabric_lakehouse`, `fabric_warehouse`,
`fabric_warehouse_snapshot` (prev), `fabric_sql_database`, `fabric_snowflake_database`, `fabric_mirrored_database`,
`fabric_mirrored_catalog` (prev), `fabric_mirrored_azure_databricks_catalog` (prev), `fabric_cosmos_db`,
`fabric_mounted_data_factory`, `fabric_eventhouse`, `fabric_kql_database`, `fabric_kql_queryset`,
`fabric_kql_dashboard`. Engineering: `fabric_notebook`, `fabric_environment`, `fabric_spark_job_definition`,
`fabric_apache_airflow_job`, `fabric_data_pipeline`, `fabric_copy_job`, `fabric_dataflow`, `fabric_variable_library`,
`fabric_user_data_function` (prev, no SP). Real-time: `fabric_eventstream`, `fabric_activator` (prev), `fabric_map`
(prev), `fabric_ontology` (prev), `fabric_digital_twin_builder` (prev, no SP), `fabric_digital_twin_builder_flow`
(prev), `fabric_graphql_api`, `fabric_data_agent`, `fabric_operations_agent` (prev, no SP). BI:
`fabric_semantic_model`, `fabric_report`, `fabric_paginated_report`, `fabric_ml_model`, `fabric_ml_experiment`,
`fabric_anomaly_detector` (prev, no SP). All 38 support a service principal except the four marked "no SP", which
say "Please use a User context".

**Data sources (136).** Every resource has a singular data source (`fabric_<x>`) and 65 of the 136 are plural list
reads (`fabric_<x>s`, filterable by `workspace_id`). The eleven with **no** resource are the ones you cannot infer:
`fabric_capacity`, `fabric_capacities`, `fabric_dashboards`, `fabric_datamarts`, `fabric_mirrored_warehouses`,
`fabric_sql_endpoints`, `fabric_lakehouse_table`, `fabric_lakehouse_tables`,
`fabric_eventstream_source_connection`, `fabric_eventstream_destination_connection`,
`fabric_onelake_data_access_securities`. The plural reads (`fabric_workspaces`, `fabric_notebooks`, `fabric_domains`,
`fabric_tenant_settings`, …) are the inventory mechanism for a workspace or tenant you did not create.

**Preview.** 15 of 71 resources and 36 of 136 data sources are preview, with the verbatim warning: "This resource is
in **preview**. To access it, you must explicitly enable the `preview` mode in the provider level configuration."
The gate is real: without it you get "Preview mode not enabled" / "'%s' is not available without explicitly opt-in
to the preview mode on the provider level configuration", and with it "The '%s' behavior may change in future
releases without notice or compatibility guarantees" (provider source, `internal/common/errors.go`, `warnings.go`).
`preview` is one provider-wide boolean, so a root that sets it enables every preview resource in that root — the
isolation argument is in the sibling note §6. Preview resources: `activator`, `anomaly_detector`,
`digital_twin_builder`, `digital_twin_builder_flow`, `domain_workspace_assignments`, `folder`, `map`,
`mirrored_azure_databricks_catalog`, `mirrored_catalog`, `onelake_data_access_security`, `ontology`,
`operations_agent`, `user_data_function`, `warehouse_snapshot`, `workspace_encryption`.

### 3. Authentication

Provider-block attributes (`docs/index.md` @ v1.15.1): `client_id`, `client_secret`, `client_certificate`,
`client_certificate_password`, `client_certificate_file_path`, `client_id_file_path`, `client_secret_file_path`,
`tenant_id`, `auxiliary_tenant_ids`, `use_cli`, `use_dev_cli`, `use_msi`, `use_oidc`, `oidc_token`,
`oidc_token_file_path`, `oidc_request_token`, `oidc_request_url`, `azure_devops_service_connection_id`,
`environment` (`public` | `gcchigh`), `endpoint`, `preview`, `timeout`, `partner_id`,
`disable_terraform_partner_id`, `use_workspace_private_link_endpoint`.

| Credential | How | Guide |
| --- | --- | --- |
| Service principal + secret | `client_id` + `client_secret` (+ `tenant_id`) | `auth_spn_secret.md` |
| Service principal + certificate | `client_certificate` (base64 PKCS#12) or `client_certificate_file_path` + password | `auth_spn_cert.md` |
| **OIDC / federated** | `use_oidc = true` + `client_id` + `tenant_id`; token from `oidc_token`, `oidc_token_file_path`, or `oidc_request_token`/`oidc_request_url` | `auth_spn_oidc.md` |
| Azure CLI | `use_cli = true` (also the default path) | `auth_app_reg_user.md` |
| Azure Developer CLI | `use_dev_cli = true` | — |
| Managed identity | `use_msi = true` (+ `client_id` for user-assigned) | `auth_msi.md` |

**Federated workload identity is supported — the answer the design needed.** The guide defines it as "a type of
credential that allows workloads, such as GitHub Actions, workloads running on Kubernetes, or workloads running on
compute platforms outside of Azure access Microsoft Entra protected resources without needing to manage secrets
using workload identity federation." Three shapes: **GitHub Actions** — the provider "will detect the
`ACTIONS_ID_TOKEN_REQUEST_URL` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN` environment variables"; the workflow needs
`permissions: id-token: write`, and the federated credential must match Organization, Repository, Entity type
(Environment/Branch/Pull Request/Tag) and value exactly. **Azure DevOps** — `FABRIC_OIDC_REQUEST_TOKEN:
$(System.AccessToken)` plus `FABRIC_AZURE_DEVOPS_SERVICE_CONNECTION_ID`, which "is an ID (GUID), not a Service
Connection name"; the provider attribute is `azure_devops_service_connection_id`, "The Azure DevOps Service
Connection ID that uses Workload Identity Federation". **Generic OIDC** — `oidc_token` / `oidc_token_file_path`.

**Audience and scope.** The requested audience defaults to **`api://AzureADTokenExchange`** and "must match the app's
federated credential"; a different one goes in the `audience` query parameter of `oidc_request_url`. The resource
scope is `https://api.fabric.microsoft.com/.default` (GCC High:
`https://high.analysis.usgovcloudapi.net/powerbi/api/.default`), from `internal/provider/client/fabric_test.go` @
v1.15.1, which asserts the scope per `environment` — a code fact, not a prose statement I found on Learn.

### 4. Permission requirements, as documented

| Object | Required of the caller | Source |
| --- | --- | --- |
| Workspace | "The caller must have permission to create workspaces granted by Fabric administrator" **and** "contributor permissions or be an Admin on the capacity"; an SP also needs "Service principals can create workspaces, connections, and deployment pipelines" | Create Workspace |
| Workspace role assignment | "The caller must have **member or higher** workspace role. Members can add members or others with lower permissions." | Add Workspace Role Assignment |
| Git connection | "The caller must have an **admin role for the workspace**. For configured connection Git credentials, the caller must have permission for the connection." SP only when `git_credentials.source` is `"ConfiguredConnection"` | Connect; `fabric_workspace_git` |
| Domain | "The caller must be a **Fabric administrator**"; Learn: "**Fabric admin (or higher)**: Fabric admins can create and edit domains". The app also "must not have any Fabric permissions that require admin consent configured" | `fabric_domain`; Domains |
| Tenant setting | "The caller must be a **Fabric administrator** or authenticate using a service principal" — an SP is allowed without the role, but gated by the admin-API settings and their security group | List Tenant Settings |
| Item | "The caller must have a **contributor** workspace role." | Create Item |
| Capacity (data source) | "The caller must have **administrator or contributor** permissions on the capacity" | List Capacities |

A service principal is not a second-class caller: Fabric's REST surface admits "Service principal and Managed
identities: Yes" for every one of the above. The awkward part is bootstrap ordering — the SP may need a tenant
setting already enabled before it can set tenant settings.

### 5. State and identity

| Attribute | What it holds |
| --- | --- |
| `fabric_workspace.id` | "The Workspace ID" — a GUID, and the only thing import wants (`"<WorkspaceID>"`). Stable across rename; `display_name` updates in place |
| `fabric_workspace.capacity_id` | the **Fabric capacity object GUID**, not an Azure resource ID — see below |
| `capacity_region`, `capacity_assignment_progress` | read-only; progress ∈ `Completed`/`Failed`/`InProgress` |
| `fabric_workspace_role_assignment.id` | assignment GUID; import `"<WorkspaceID>/<WorkspaceRoleAssignmentID>"`; `principal.id` is the Entra object ID, `principal.type` ∈ `Group`/`ServicePrincipal`/`ServicePrincipalProfile`/`User` |
| `fabric_domain.id` | domain GUID; `parent_domain_id` is ForceNew |
| `fabric_tenant_setting` | **no `id` attribute and no Import section** — identity is `setting_name`, a singleton per setting |
| item resources | item GUID plus `workspace_id` (ForceNew) |

**`capacity_id` is a GUID — this settles the earlier doubt.** The provider types it as `customtypes.UUID` and
rejects a non-UUID at plan time (the `"invalid uuid"` test case). The GUID is the one `GET /v1/capacities` returns —
`{"id": "96f3f0ff-4fe2-4712-b61b-05a456ba9357", "sku": "F4", …}` — whereas `azurerm_fabric_capacity.id` is
`/subscriptions/…/providers/Microsoft.Fabric/capacities/<name>`. **The AzureRM ID cannot be passed to
`capacity_id`.** The supported path is `data "fabric_capacity" { display_name = azurerm_fabric_capacity.x.name }`
then `capacity_id = data.fabric_capacity.x.id`, which is what Microsoft's `102-fabric-capacity` quickstart does.

**A paused or invisible capacity.** `fabric_workspace` validates capacity state on create and read by paging
`/v1/capacities` for the ID: not found gives "Unable to find Capacity with 'id': …", found-but-not-`Active` gives
"Fabric Capacity is NOT in Active state. Inactive Capacity may cause unrecoverable damage." (provider source,
`internal/services/workspace/helpers.go`). That endpoint lists only capacities "the principal can access", so an SP
that is not a capacity admin fails the *lookup*, not the state check — the real reason
`skip_capacity_state_validation` exists, and the attribute says so: "Use this when the caller does not have
permissions to list capacities." It also warns that with it set "the provider cannot detect a suspended or inactive
capacity … subsequent `terraform apply` runs may fail to find workspace items and could remove them from the
Terraform state, potentially causing unrecoverable state drift." The data source narrows ARM's 13 states to
`Active`/`Inactive`.

### 6. `azurerm_fabric_capacity`, precisely

- **Arguments:** `name`, `location`, `resource_group_name` (each "Changing this forces a new resource to be
  created"), `sku { name, tier }`, `administration_members`, `tags`, `timeouts`. **Exported:** `id` only.
- **SKU range:** `sku.name` ∈ `F2`, `F4`, `F8`, `F16`, `F32`, `F64`, `F128`, `F256`, `F512`, `F1024`, `F2048`;
  `sku.tier` "The only possible value is `Fabric`".
- **API version:** `Microsoft.Fabric` **`2023-11-01`** (generated "API Providers" section) — the GA ARM version, not
  the `2026-09-01-preview` one that carries `properties.overage`.
- **`administration_members`:** "An array of administrator user identities. The member must be an Entra user or a
  service principal." UPN for a user, object ID for an SP — how the automation principal becomes a capacity admin.
- **What it cannot express:** suspend/resume (an ARM *action*, `POST …/suspend`, not a property — so a paused
  capacity is invisible to Terraform and `state` is not even exported); `overage` (preview API only); surge
  protection (not in the ARM resource); any autoscaling (no such capability); `F4096`/`F8192` (documented in
  licensing, absent from the SKU list); zone/region mobility. Resizing via `sku.name` carries no ForceNew note, so
  it is expected in place — inferred from the marker's absence, not stated. Cost and pause policy:
  [`capacity-provisioning-and-cost-control.md`](capacity-provisioning-and-cost-control.md).

### 7. Provider health

- **Cadence:** 31 GitHub releases; `v1.0.0` 2025-03-31, `v1.15.1` 2026-11-11, **11 releases in 2026** to date —
  roughly monthly, sometimes three days apart. MPL-2.0, 3.6M registry downloads.
- **GA or preview?** Neither is declared: no badge, no support commitment, no release policy. `1.x` numbering is the
  only stability signal, and the sibling note records a breaking change shipped in a *minor* (v1.6.0). What is
  declared, verbatim: "**Terraform Provider for Microsoft Fabric** is an open-source project that is **NOT** covered
  by the [Microsoft Fabric](https://support.fabric.microsoft.com/) or [Microsoft](https://support.microsoft.com/)
  support policies." It also refuses code: "This project welcomes feedback and suggestions only via GitHub Issues.
  Pull Request (PR) contributions will **NOT** be accepted at this time."
- **Open issues:** 40 open (54 counting PRs), oldest 2025-01-15. The shape is "core works, edges are rough", with
  long-lived bugs on objects this design leans on: **#455** (2025-05-21, last touched 2026-02-05) `data
  "fabric_capacity"` SIGSEGV under a service principal; **#497** (2025-06-11, 19 comments) `fabric_warehouse` reports
  `EntityNotFound` on a create that succeeded, then `ItemDisplayNameAlreadyInUse` on retry; **#537** (2025-07-13)
  `fabric_gateway_role_assignment` creates a `ServicePrincipal` assignment that never reaches state; **#355**
  (2025-03-27) asks for domain assignment from `fabric_workspace`, which exists only as the preview
  `fabric_domain_workspace_assignments`. Whether #455 still reproduces on 1.15.1 I could not establish.

## What this settles

| Object class | Terraform today | Note |
| --- | --- | --- |
| Capacity (F SKU) | **yes** — `azurerm_fabric_capacity` | resize yes; pause/overage/surge no |
| Workspace | **yes** — `fabric_workspace` | capacity via `data "fabric_capacity"` |
| Workspace role assignment | **yes** | one principal per resource |
| Git binding | **yes** — SP only with `ConfiguredConnection` | non-production only (ADR 0005) |
| Domain, domain roles | **yes**; workspace→domain is **preview** | Fabric administrator required |
| Tenant settings | **yes**, tenant-wide | SP allowed without the role |
| Connections, gateways, deployment pipelines | **yes** | non-preview, SP-capable |
| Items (38 types) | **yes as shells**, not as definitions | ADR 0003 leaves items to `fabric-cicd` |
| Folders, OneLake security, workspace encryption, 12 more | **preview only** | one `preview = true` per root |

**Three things to verify in the tenant before relying on any of it:**

1. **Is the automation principal a capacity admin on the target capacity?** If not, `data "fabric_capacity"` lists
   nothing, `capacity_id` cannot be validated, and the only escape (`skip_capacity_state_validation = true`) trades
   the drift guard for a silent one. Verify with a real `GET /v1/capacities` under that principal, not via the portal.
2. **Are the enabling tenant settings on, and is the SP in the allowed group?** "Service principals can create
   workspaces, connections, and deployment pipelines" for anything that creates a container; "Service principals can
   call Fabric public APIs" for the rest; "Service principals can access admin APIs used for updates" plus an
   allowed group for `fabric_tenant_setting` and `fabric_domain`. Beware the name: Learn's identity-support page and
   the provider's guides still say "Service principals can use Fabric APIs".
3. **Does the federated credential match reality?** Issuer, subject (`repo:org/repo:ref:…`, or the ADO service
   connection GUID), audience `api://AzureADTokenExchange`, and no admin-consent Fabric permission on the app — the
   last is a documented blocker for `fabric_domain`, not a preference.

**Verdict.** Safe today: `fabric_workspace`, `fabric_workspace_role_assignment`, `fabric_connection`,
`fabric_deployment_pipeline` and its role assignment, `fabric_tag`, `fabric_spark_workspace_settings`, and the F SKU
— non-preview, SP-capable, with IDs other systems can reference. Separate gated root only: `fabric_domain`,
`fabric_domain_role_assignments`, `fabric_tenant_setting` (tenant-wide blast radius) and `fabric_workspace_git`
(non-production). Leave to the deployer or the run-book: every item resource (definitions are unreadable back, so
Terraform is a second writer with no arbiter), all 15 preview resources, and anything about capacity lifecycle. The
surface is wider than ADR 0003 assumed; the support position is worse than its wording implies.

## What this does not establish

- Whether #455 reproduces on 1.15.1, and whether `fabric_capacity` works cleanly once the SP is a capacity admin.
  Both need a tenant to test in.
- Whether `fabric_workspace.id` is the same GUID as the legacy Power BI workspace ("group") object ID.
- Which workspace role update or delete of an existing `fabric_workspace` needs; and what `fabric_gateway` and
  `fabric_connection` creation require — the provider states no permission for any of the three.
- Whether a `sku.name` change applies in place without replacing the capacity (no ForceNew marker; untested).

## Sources

| Source | Used for | Dated |
| --- | --- | --- |
| [Provider docs index @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/docs/index.md) | provider attributes, Terraform >= 1.8, capacity/SP limitations | checked 2026-11-12 |
| [`docs/resources/`](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/resources) and [`docs/data-sources/`](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/data-sources) | the 71 + 136 inventory, schemas, preview markers, SP notes | checked 2026-11-12 |
| [Auth guides @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/guides) | credential types, `use_oidc`/`use_msi`, ADO service connection, audience, capacity-admin grant | checked 2026-11-12 |
| [Provider source @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/internal) | `capacity_id` as UUID, `validateCapacityState`, preview error text, token scope | read 2026-11-12 |
| [README.md](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/README.md) / [SUPPORT.md](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/SUPPORT.md) | support statement verbatim, no-PR policy | checked 2026-11-12 |
| [Releases](https://github.com/microsoft/terraform-provider-fabric/releases) / [Issues](https://github.com/microsoft/terraform-provider-fabric/issues) | 31 releases, v1.0.0 date, 40 open issues, #455/#497/#537/#355 | checked 2026-11-12 |
| [azurerm registry metadata](https://registry.terraform.io/v1/providers/hashicorp/azurerm) and [`azurerm_fabric_capacity` @ 5.13.0](https://registry.terraform.io/providers/hashicorp/azurerm/5.13.0/docs/resources/fabric_capacity) | version, arguments, F2–F2048, ForceNew fields, API `2023-11-01`, import ID | checked 2026-11-12 |
| [Create Workspace](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/create-workspace) / [Add Workspace Role Assignment](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/add-workspace-role-assignment) | create permission and capacity role; "member or higher"; 1,000-principal limit | checked 2026-11-12 |
| [Git – Connect](https://learn.microsoft.com/en-us/rest/api/fabric/core/git/connect) | workspace admin role; `ConfiguredConnection` rule for SPs | checked 2026-11-12 |
| [Domains](https://learn.microsoft.com/en-us/fabric/governance/domains) | "Fabric admin (or higher)"; domain admin vs contributor | checked 2026-11-12 |
| [List Tenant Settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings) | "Fabric administrator or authenticate using a service principal" | checked 2026-11-12 |
| [Create Item](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item) / [List Capacities](https://learn.microsoft.com/en-us/rest/api/fabric/core/capacities/list-capacities) | contributor role; capacity GUID shape; admin-or-contributor read | checked 2026-11-12 |
| [Identity support](https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support) | SP/MSI support; the stale "use Fabric APIs" setting name | checked 2026-11-12 |

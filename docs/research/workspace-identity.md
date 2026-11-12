# What is a Fabric workspace identity, what is it for, and where does it replace a service principal?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the work repo's deploy identity design — extends [`identity-service-principal-and-tenant-settings.md`](identity-service-principal-and-tenant-settings.md);
  decides whether shortcut and storage access can ride the deploy pipeline at all

## Short answer

A workspace identity is a Fabric-managed **service principal plus app registration** in Entra, created for one workspace, named after it, and deprovisioned only when
that workspace is *permanently* deleted. It is not a caller identity: you cannot authenticate as it against the Fabric API, and it holds no workspace role until one is
granted. Its job is **outbound** authentication — trusted workspace access to firewall-enabled ADLS Gen2/Blob, and a `WorkspaceIdentity` connection credential — so it
replaces a service principal exactly where the credential must be *bound to a workspace* rather than to a pipeline.

## Detail

### 1. Definition

"A Fabric workspace identity is an automatically managed service principal that can be associated with a Fabric workspace"; "When you create a workspace identity,
Fabric creates a service principal in Microsoft Entra ID to represent the identity. An accompanying app registration is also created" (workspace-identity, 2026-09-16).
Not an Entra managed identity: "While Fabric workspace identities share some similarities with Azure managed identities, their lifecycle, administration, and governance
are different."

- **One per workspace, optional, name not yours to choose:** "The name of the workspace identity is always the same as the name of the workspace it's associated with."
  Renaming the workspace renames the identity, but "its Microsoft Entra application and service principal remain the same."
- **Tenant cap:** "A default of 10,000 workspace identities can be created in a tenant" — setting **Define maximum number of Fabric identities in a tenant**, on
  **Developer settings** (rev. 2026-09-29).
- **Created** via **Workspace settings** → **Workspace identity** → **+ Workspace identity**; REST `POST /v1/workspaces/{workspaceId}/provisionIdentity`; or Terraform
  `identity = { type = "SystemAssigned" }` on `fabric_workspace` — the only enum value, and nothing is Entra-assigned. States: *Active*, *Inactive*, *Deleting*,
  *Unusable*, *Failed*, *DeleteFailed*.

### 2. What it is used for

"Workspace identity currently can be used in two ways: For authentication … For trusted workspace access."

| Scenario | Supported? | Exact wording |
| --- | --- | --- |
| OneLake shortcut | ADLS Gen2 only | "supported only for ADLS Gen2 shortcuts" |
| Pipeline activities | Copy, Lookup, GetMetadata | "supported for Copy, Lookup, and GetMetadata activities" |
| Semantic model (import), Dataflows Gen2 | Yes / narrow | Dataflows: "only supported … with deployment pipelines and Public API" |
| T-SQL `COPY`, AzCopy | Yes | ingestion paths under trusted workspace access |
| Gateway connections | **No** | "not supported for gateway connections" |
| Spark / direct storage | **No** | use "Managed private endpoints" instead |
| Anything else | **No** | only those four item types; not B2B/cross-tenant; not My workspace; never a Fabric API caller |

### 3. How it differs from a service principal

| | Workspace identity | Service principal |
| --- | --- | --- |
| Lifecycle | "When you permanently delete the workspace, Fabric deletes the identity" | yours forever; survives every workspace |
| Credentials | "Fabric automatically manages the credentials … preventing credential leaks and downtime" | secret or federated credential, rotated by you |
| Fabric API caller | no | yes, subject to four tenant settings |
| Grantable where | Azure RBAC on target resources; optionally a workspace role ("not granted any workspace role" by default) | Azure RBAC, workspace roles, admin allowed-groups |
| Audit | Purview **Created / Retrieved / Deleted Fabric Identity for Workspace**, **Retrieved Fabric Identity Token for Workspace**; Entra sign-in and audit logs on the enterprise app | Entra sign-in logs; Fabric audit log names it as caller |

The weight is in rows one and two: one SP across three workspaces has one blast radius and one rotation event; three workspace identities have three, mutually
invisible. Deleting one is a breaking change with no undo — "Deleted workspace identities cannot be restored" — whereas an SP credential is re-issuable.

### 4. Creation and deletion

- **Who:** "You must be a workspace admin to be able to create and manage a workspace identity"; REST needs "an *admin* role in the workspace" plus
  `Workspace.ReadWrite.All`, 10 calls/min (Provision Identity, rev. 2026-11-10). No Azure permission is documented as necessary to create one.
- **Azure exposure:** "Application Administrators or users with higher roles can view, modify, and delete the service principal and app registration", and doing so "is
  not recommended, as it will cause Fabric items relying on workspace identity to stop working." Adding API permissions to the app *is* supported.
- **Workspace deletion is deferred:** the workspace sits in *Deleted* for the retention period, "Fabric doesn't deprovision the workspace identity" until permanent
  deletion, then it moves to *Deleting*. Deleting the SP by hand "causes errors and can delay the cleanup."
- **Restore from soft delete:** "If you restore the workspace after deletion, the workspace identity **is not** restored … you must create a new one." New application
  and service principal IDs, so every Azure RBAC assignment, resource instance rule and connection is stale. Recreating after a *Failed* state needs "wait for an hour and
  then delete the identity … wait 5 minutes and then create" it again.
- **2026-era surfaces**, all live: GA status, `provisionIdentity`/`deprovisionIdentity` (rev. 2026-11-10), the `workspaceIdentity` object on Get Workspace (rev.
  2026-10-28), the **Fabric identities** admin page (2026-09-01), the `identity` block on `fabric_workspace`. When it left preview: could not establish.

### 5. Granting it access

Two independent layers; both are needed.

- **Azure RBAC (data).** Storage account → **Access control (IAM)** → **Add role assignment** → "Assign access to User, group, or service principal", searching "by name
  or app ID of the workspace identity". Roles: "Storage Blob Data Contributor, Storage Blob Data owner, or Storage Blob Data Reader role at the storage account scope, or
  a Storage Blob Delegator role at the storage account scope together with access at the folder level" — and "The role must be provided at the Storage account level."
- **Resource instance rule (network path).** `resourceAccessRules` under `networkAcls`, with `tenantId` and `resourceId`
  `/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/Fabric/providers/Microsoft.Fabric/workspaces/{workspaceId}`. "Resource instance rules for Fabric
  workspaces can only be created through ARM templates or PowerShell. Creation through the Azure portal is not supported." Maximum **200**; the all-zero subscription ID
  is mandatory; the rule names the *workspace*, not the identity.
- **Trusted service exception (network path).** A checkbox, not a rule: "any workspaces in your tenant's Fabric capacities that have a workspace identity can access
  data stored in the storage account." Tenant-wide, and "This configuration isn't recommended, and support might be discontinued in the future."
- **Who may create either:** "A Contributor on the storage account (an Azure RBAC role) can configure resource instance rules or trusted service exception." The rule
  grants reachability only: "A resource instance network rule provides access to the public endpoint but not to the data" (storage-network-security-resource-instances,
  2025-09-12).

### 6. Limits and gotchas

- **Runtime check most designs miss:** "The identity that *runs* the pipeline must also have an admin, member, or contributor role in the workspace. Fabric checks this
  permission at run time and issues a workspace identity token only to an identity that holds one of these roles … both to the user who runs the pipeline on demand and to
  the service principal that runs it on a schedule or through the API." A deploy SP *can* drive such a pipeline, but only while it holds a workspace role, and "Granting
  the workspace identity permissions on the target data source isn't sufficient on its own."
- **Trusted workspace access wants a workspace role too:** "Ensure that the workspace identity has Contributor access to the workspace."
- **Recreate duplicates names:** during retention the tenant can hold "more than one app registration with that name" — resolve by object ID, never name. A
  **Conditional Access** policy for workload identities that covers all service principals breaks the identity unless
  it is excluded.
- **Capacity and connection state:** moving to non-F or trial leaves the identity alive but "Fabric items that rely on trusted workspace access stop working" ("after an
  hour"); such connections read *Offline* in **Manage connections and gateways**, and "Checking the status of a connection that has workspace identity as the
  authentication method isn't supported."
- **The two pages disagree:** trusted-access says "workspace identity is the only supported authentication method. Test connection fails if organizational account or
  service principal authentication methods are used", then three bullets later that all three methods are usable in shortcuts and pipelines. Read the first as scoped to
  **Manage connections and gateways**.

### 7. What a deployment design must do about it

Terraform *can* own most of this — unlike the gateway binding:

- `fabric_workspace` — `identity = { type = "SystemAssigned" }`, with `application_id` and `service_principal_id` read-only afterwards (`docs/resources/workspace.md`,
  checked 2026-11-12).
- `fabric_connection` — the `credential_type` enum includes **`WorkspaceIdentity`** (`docs/resources/connection.md`); `fabric_shortcut` carries no auth kind, only
  `connection_id` (`docs/resources/shortcut.md`), so the credential is decided once on the connection.
- **The gap is the resource instance rule:** neither `azurerm_storage_account` nor `azurerm_storage_account_network_rules` documents `resource_access_rules` (checked
  2026-11-12), so it needs an ARM template (`azurerm_resource_group_template_deployment`) or PowerShell. RBAC is ordinary `azurerm_role_assignment` with `principal_id =
  fabric_workspace.<x>.identity[0].service_principal_id`.

Ordering follows from one sentence — "The **Workspace identity authentication** option appears in connection and shortcut experiences only after you create a workspace
identity":

**workspace → identity → Azure RBAC + resource instance rule → connection → shortcut.** `provisionIdentity` is a POST against an existing workspace, so the identity
never exists at workspace-create time from the API even though Terraform hides that inside one resource. Destroy reverses badly: the identity is deprovisioned
eventually, but the role assignment, the resource instance rule and the connection survive pointing at a dead object ID.

## What this settles

Use a **workspace identity** for anything whose access must be scoped to *one workspace's* items — a firewall-enabled ADLS Gen2 or Blob shortcut, a semantic model or
pipeline reading that storage, a `COPY`/AzCopy ingest — because it is the only credential trusted workspace access accepts and the only one whose life ends with the
workspace. Keep the **deploy service principal** for everything that *calls Fabric*: creating workspaces, items, role assignments and connections, where a workspace
identity is not an admissible caller at all. They are complementary: the deploy SP creates and grants the identity, the identity does the data access, and the SP needs
a workspace role only so Fabric will issue the identity's token to scheduled runs.

Manual steps, once per workspace: create the identity (or let `fabric_workspace` do it), add it as **Contributor** in **Manage Access**, assign `Storage Blob Data
Contributor` or `Reader` at storage-account scope, author the resource instance rule by ARM template or PowerShell, then create the `WorkspaceIdentity` connection and
bind it to shortcuts, pipelines and models.

## What this does not establish

- Whether a workspace identity needs a Fabric or Power BI licence — no Learn statement found.
- Whether it may join the security groups behind the two Admin API settings, or hold **Fabric administrator**. No page says either way, and it can never call an API to
  use them.
- When it reached general availability, and what changed in provisioning at that point.
- Whether a connection can be created with the `WorkspaceIdentity` credential before the identity exists — the docs imply no, but only for the portal experience.
- Whether `fabric_workspace`'s `identity` block is stable or preview, and whether dropping it deprovisions the identity or merely forgets it.
- The work tenant's state: any Conditional Access workload-identity policy, existing identity count, and whether its storage accounts use resource instance rules or the
  trusted service exception.
- Nothing was executed. The Terraform ordering is read from schema docs, not from an apply.

## Sources

| Source | What it was used for |
| --- | --- |
| [Workspace identity](https://learn.microsoft.com/en-us/fabric/security/workspace-identity) (2026-09-16) | Definition, app registration, lifecycle, deletion and retention, rename, 10,000 cap, Purview activities |
| [Authenticate with workspace identity](https://learn.microsoft.com/en-us/fabric/security/workspace-identity-authenticate) (2026-08-13) | Supported items, ADLS-only shortcuts, runtime role check, gateway exclusion, status gap |
| [Trusted workspace access](https://learn.microsoft.com/en-us/fabric/security/security-trusted-workspace-access) (2026-08-13) | F SKU, RBAC roles, resource instance rule, trusted service exception, Contributor on the account |
| [Manage Fabric identities](https://learn.microsoft.com/en-us/fabric/admin/fabric-identities-manage) (2026-09-01) · [Developer settings](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-developer) (rev. 2026-09-29) | Service principal / application ID fields; the identity-count setting |
| [Provision](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/provision-identity) / [Deprovision](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/deprovision-identity) (rev. 2026-11-10) · [Get Workspace](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/get-workspace) (rev. 2026-10-28) · [Create Connection](https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/create-connection) (rev. 2026-11-10) | Routes, admin role, scopes, throttles, `workspaceIdentity` shape, `WorkspaceIdentity` credential type |
| [Storage firewall rules](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security) (2026-10-23) · [Resource instance rule](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-resource-instances) (2025-09-12) | Four rule types; "public endpoint but not … the data" |
| [terraform-provider-fabric](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/) (`workspace.md`, `connection.md`, `shortcut.md`) | `identity` block, `WorkspaceIdentity` credential type, `connection_id`-only shortcut |

# Which identity should a self-hosted Azure DevOps pipeline use against Fabric, and which tenant settings gate it?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the deploy-vs-administer identity split for the work repo's pipeline

## Short answer

A Microsoft Entra service principal, used with a federated credential (or a managed identity), is the
only documented headless identity for both jobs, and it is admitted by four separate tenant settings
across two admin pages plus two "allowed security group" list memberships. Use two service principals:
one for deploy that holds workspace roles only, one for administration that sits in the allowed
security groups — the one-SP shortcut is legal but moves tenant-settings and domain-creation rights
onto the credential that runs on every merge. A service principal cannot be shown to hold the
**Fabric administrator** role; the allow-listed security group is the documented substitute.

## Detail

### 1. Identity options, and what actually accepts them

| Identity | Fabric public APIs | Fabric admin APIs | Azure DevOps service connection |
| --- | --- | --- | --- |
| Service principal, client secret | Yes | Yes (both admin gates) | No Fabric-native type; secret held as a pipeline secret |
| Service principal, federated credential | Yes | Yes | **Azure Resource Manager** + **Workload identity federation** |
| Managed identity | Yes | Yes | **Azure Resource Manager** + **Managed identity** (user-assigned) |
| Fabric workspace identity | **No** — not a caller identity | No | n/a |

The Fabric REST identity article lists "**User**", "**Service principal**" and "**Managed identity**"
(Fabric REST, ms.date 2024-08-04). Every API page read for this note carries the block "Microsoft
Entra supported identities … Service principal and Managed identities: Yes" — Create Workspace,
Assign To Capacity, Get Item, Add Workspace Role Assignment, Create Item, Update Item Definition,
Update Tenant Setting, Create Domain.

What is **not** supported:

- **No Fabric service connection type exists.** The Azure Pipelines list of default connection types
  (ms.date 2026-10-15) has no Fabric, Power BI or Microsoft 365 entry. The exact type for a
  Fabric/Entra WIF setup is **"Azure Resource Manager"** with authentication method **"Workload
  identity federation"** — "App registration (automatic)", "Managed identity", or "App registration or
  managed identity (manual)" (connect-to-azure, ms.date 2026-08-18).
- **You cannot sign in to the portal as a service principal**: "you can't open Fabric with service
  principal credentials" (enable-service-principal-admin-apis, ms.date 2026-06-26).
- **An app with admin-consent Fabric permissions is rejected**: an app calling read-only admin APIs
  "**must not** have any admin-consent required permissions for Power BI set on it" (same page).
- **A workspace identity is not an automation identity.** It is "an automatically managed service
  principal that can be associated with a Fabric workspace", used for outgoing authentication and
  trusted access, and cannot be created in My workspace (workspace-identity, ms.date 2026-09-16).

Certificate credentials: Fabric documents "federated credentials (recommended) or a client secret"
(same page); no Fabric page read here documents a certificate, which is an Entra-side grant type.

### 2. The four tenant settings, named exactly

All four live under **OneLake catalog > Govern > Configurations > Tenant settings**. Two are on the
**Developer settings** page (`service-admin-portal-developer`, ms.date 2026-04-08); two are on the
**Admin API settings** page (`service-admin-portal-admin-api-settings`, ms.date 2026-06-26).

| Gate | Exact setting name | Page | Default | Allowed group? |
| --- | --- | --- | --- | --- |
| Calling Fabric public APIs | **Service principals can call Fabric public APIs** | Developer settings | Enabled by default for new customers | Yes |
| Creating workspaces / connections / deployment pipelines | **Service principals can create workspaces, connections, and deployment pipelines** | Developer settings | Disabled by default for new customers | Yes |
| Read-only admin APIs | **Service principals can access read-only admin APIs** | Admin API settings | — | Yes |
| Admin APIs used for updates | **Service principals can access admin APIs used for updates** | Admin API settings | — | Yes |

The split matters: the create setting covers APIs that "aren't protected by a Fabric permission model"
— exactly Create Workspace, Create Connection and Create Deployment Pipeline — while the public-API
setting covers CRUD "protected by a Fabric permission model".

**Naming trap.** Two Microsoft pages call the public-API gate **"Service principals can use Fabric
APIs"** (the identity-support article and the fabric-cicd tutorial, ms.date 2026-02-19). No setting of
that name appears in the tenant settings index (ms.date 2026-08-28); search the portal for the names
in the table above instead.

### 3. Fabric administrator vs workspace Admin

- **Workspace Admin** is a per-workspace role that a service principal can hold: "Microsoft Entra ID
  service principals (app registrations) can also be assigned to workspace roles and inherit the same
  permissions as users for API-based operations in Fabric" (roles-workspaces, ms.date 2026-04-24).
- **Fabric administrator** is described only as assigned to users: "Microsoft 365 user admins assign
  users to the Fabric administrator or Power Platform administrator roles in the Microsoft 365 admin
  portal" (roles, ms.date 2026-04-21). No Learn page read here assigns that role to a service
  principal, and no page describes a group-membership route to it.
- A service principal **can** be a member of an ordinary security group: "Add your app ID as a member
  of the security group you created" (enable-service-principal-admin-apis). That is the documented
  mechanism, and the setting descriptions say group members get "read-only access to all the
  information available through admin APIs (current and future)".
- The admin API reference treats the SP as an *alternative* to the role, not a holder of it:
  "The caller must be a Fabric administrator or authenticate using a service principal"
  (Update Tenant Setting, updated 2026-09-15).

### 4. Role or permission per operation

| Operation | Exact requirement (quoted) | SP allowed |
| --- | --- | --- |
| Create a workspace | "The caller must have permission to create workspaces granted by Fabric administrator"; "The caller must have *contributor* permissions or be an Admin on the capacity"; "Service Principals must have permission granted by Fabric administrator" | Yes |
| Assign a workspace to a capacity | "The caller must have *contributor* permissions or be an capacity Admin"; "The caller must have *admin* workspace role" | Yes |
| Create / deploy an item | "The caller must have a *contributor* workspace role" | Yes, per item type |
| Update an item definition | "The caller must have *read and write* permissions for the item" | Yes, per item type |
| Add or remove a workspace role assignment | "The caller must have *member* or higher workspace role"; "Members can add members or others with lower permissions"; only Admin can "Add or remove people, including other admins" | Yes |
| Read item metadata | "The caller must have *read* permissions for the item" | Yes |
| Call read-only admin APIs | Membership of an allowed security group; the principal gets "read-only access to all the information available through admin APIs" | Yes |
| Call admin APIs used for updates | Allowed security group under **Service principals can access admin APIs used for updates**; Update Tenant Setting: "The caller must be a Fabric administrator or authenticate using a service principal" | Yes |
| Set a tenant setting | Update Tenant Setting above; "Maximum 25 requests per minute" | Yes |
| Create a domain | "The caller must be a Fabric administrator"; "Maximum 25 requests per minute per principal" | Yes |

Principal-type restrictions worth designing around:

- **Capacity Admin is written for users**: "Only users that belong to the tenant the capacity is part
  of, can be added as admins to the capacity" (capacity-settings, ms.date 2026-03-06). Capacity
  **Contributor** is the grantable one: "Contributor permissions … Specific users or security
  groups", and assigning a workspace needs "a capacity **contributor** role, and a workspace admin role".
- **Member-or-higher thresholds bite**: a SP at Contributor can deploy items but cannot add role
  assignments.

### 5. Gotchas that actually stop pipelines

- **My workspace.** "Each Microsoft Fabric user has a personal workspace known as *My workspace*"
  (licenses, ms.date 2026-06-15). An SP is not a user, so there is no My workspace to resolve;
  workspace identities are likewise barred from it. Never look up "My workspace" by name.
- **SP display name in the portal.** No Learn page read here states that service principals appear as
  a GUID in permission lists — treat that as unverified. The documented API shape is
  `ServicePrincipalPrincipal` with `id` and `servicePrincipalDetails.aadAppId`, so resolve SPs by
  object ID, never by display name.
- **Licensing.** Could not establish. Create Item says only "To create a non-PowerBI Fabric item the
  workspace must be on a supported Fabric capacity" and "To create a Power BI item, the user must
  have the appropriate license". No page states whether an SP needs a Fabric/Power BI licence.
- **Audience/scope.** Fabric: `https://api.fabric.microsoft.com/` with scope `.default` — verbatim in
  the fabric-cicd tutorial and in Microsoft's `fabric-cicd` source. For Power BI the permission
  surface is the "Power BI Service" app registration (scopes article, ms.date 2025-02-03); the
  literal `analysis.windows.net` resource string could not be confirmed on a current Learn page.
- **Throttling.** Quota is per identity — "every user, service principal, or managed identity receives
  its own independent quota allocation" — 500 calls/min platform, 200 job scheduler, 500
  long-running operations, fixed 60-second windows. 429 bodies distinguish `RequestBlocked` (honour
  `Retry-After`) from `CapacityLimitExceeded` (retrying immediately is "unlikely to succeed").
  Workspaces cap at 1,000 users or groups, and "A user or a service principal can be a member of up
  to 1,000 workspaces".
- **Token lifetime.** Access tokens are "assigned a random value ranging between 60-90 minutes (75
  minutes on average)", and "Configuring token lifetimes for managed identity service principals
  isn't supported" (configurable-token-lifetimes, ms.date 2026-04-08). A pipeline longer than an hour
  must re-acquire tokens through a credential object, not cache a bearer token.
- **Permission propagation.** "After you add or remove workspace access for a user or a group, the
  permission change only takes effect the next time the user logs into Microsoft Fabric"
  (give-access-workspaces). Do not grant a role and act on it in the same run.

### 6. Recommended topology

**Two service principals, both federated, no secrets.**

- `sp-fabric-deploy` — workspace roles only (Admin or Member on the target workspaces, or Contributor
  plus a workspace Admin grant for the capacity move), not in any allowed security group, no admin
  API rights. Runs on merge and can only touch item content.
- `sp-fabric-admin` — member of the security group referenced by both **Admin API settings** gates,
  plus capacity Contributor and the workspace Admin needed for capacity assignment. Runs only from a
  gated pipeline or a manual stage, never from a merge trigger.

Trade-off: two credential and group-membership lifecycles to manage, two sets of approvals, and more
setup before the first deploy works. The alternative — one SP for both jobs — is legal and documented,
but **it weakens the trust boundary**: the identity that runs on every merge would also be a member of
the group that can flip tenant settings and create domains, so compromise of a routine deploy
credential escalates to tenant configuration. Note the boundary is not absolute even when split:
`sp-fabric-admin` still needs workspace Admin to move a workspace onto a capacity.

On the WIF mechanism: an **Azure Resource Manager** service connection with **Workload identity
federation** avoids stored secrets, though the fabric-cicd tutorial does the opposite (client secret in
Key Vault, no service connection). With self-hosted VM agents a third option exists — a user-assigned
managed identity on the VM — which removes credentials but moves the boundary to the *agent pool*: any
pipeline on that VM can use the identity. For a shared pool, prefer the federated service connection.

## What this settles

- The four exact tenant setting names, which admin page each sits on, and that two of them default off.
- That the ADO side is an **Azure Resource Manager** service connection with **Workload identity
  federation**; there is no Fabric service connection type.
- Service principal vs managed identity support is per API, stated in each API page's supported
  identities block; both are accepted everywhere this project needs.
- The permission thresholds per operation, and that capacity **Admin** is written for users while
  capacity **Contributor** is the grantable role for SPs.
- The recommended split: deploy SP with workspace roles, admin SP in the allowed groups.

## What this does not establish

- Whether a service principal needs a Fabric or Power BI licence (no Learn statement found).
- Whether the Microsoft 365 admin portal's role-assignment UI will accept a service principal for
  **Fabric administrator** — only that no Learn page documents it, and that the SP path is the group.
- Whether service principals render as a GUID in the portal's permission lists (unverified; do not
  build a name lookup on it either way).
- Any difference between system-assigned and user-assigned managed identities for Fabric — the API
  pages collapse both into "Managed identities".
- Whether Fabric accepts certificate-based service principal credentials; documented credentials are
  federated and client secret.
- The literal Power BI audience string (`analysis.windows.net/...`).
- Behaviour in the trial capacity or a personal tenant; nothing here was executed.

## Sources

| Source | What it was used for |
| --- | --- |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-developer (ms.date 2026-04-08) | Exact names of the two Developer settings, defaults, allowed-group requirement |
| https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-admin-api-settings (2026-06-26) | Exact names of the two Admin API settings |
| https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index (2026-08-28) | Confirming no "Service principals can use Fabric APIs" setting exists |
| https://learn.microsoft.com/en-us/fabric/admin/enable-service-principal-admin-apis (2026-06-26) | SP as group member, admin API enablement steps, "can't open Fabric", admin-consent restriction |
| https://learn.microsoft.com/en-us/fabric/admin/roles (2026-04-21) | Fabric administrator assigned to users |
| https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support (2024-08-04) | User / service principal / managed identity support |
| https://learn.microsoft.com/en-us/rest/api/fabric/articles/throttling (2026-08-14) | Per-identity quotas, 429 semantics |
| https://learn.microsoft.com/en-us/rest/api/fabric/articles/scopes (2025-02-03) | Scopes apply to delegated access only; Power BI Service permission surface |
| https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/create-workspace, .../workspaces/assign-to-capacity, .../items/create-item, .../items/update-item-definition, .../items/get-item, .../workspaces/add-workspace-role-assignment (updated 2026-09-24 to 2026-11-11) | Per-operation permissions, supported identities, per-API throttling limits |
| https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/update-tenant-setting (2026-09-15), .../admin/domains/create-domain (2026-11-09) | "Fabric administrator or authenticate using a service principal", 25/min limits |
| https://learn.microsoft.com/en-us/fabric/fundamentals/roles-workspaces (2026-04-24) | Workspace role capability table, SPs assignable to roles |
| https://learn.microsoft.com/en-us/fabric/fundamentals/give-access-workspaces (2025-06-10) | Permission-change propagation |
| https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces (2026-07-28) | 1,000-workspace membership limit |
| https://learn.microsoft.com/en-us/fabric/admin/capacity-settings (2026-03-06) | Capacity Admin vs Contributor wording |
| https://learn.microsoft.com/en-us/fabric/enterprise/licenses (2026-06-15) | Per-user licence model, My workspace definition |
| https://learn.microsoft.com/en-us/fabric/security/workspace-identity (2026-09-16) | Workspace identity scope and limits |
| https://learn.microsoft.com/en-us/fabric/cicd/tutorial-fabric-cicd-azure-devops (2026-02-19) | Scope string, Key Vault secret pattern, "Member or Admin" guidance |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure (2026-08-18) | ARM + Workload identity federation options |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints (2026-10-15) | Full service connection type list (no Fabric type) |
| https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes (2026-04-08) | 60–90 min access tokens; MI lifetimes not configurable |
| https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept (2026-03-16) | Role-assignable group restrictions (no nesting) |
| https://github.com/microsoft/fabric-cicd (`_common/_fabric_endpoint.py`) | `api.fabric.microsoft.com/.default` scope constant |

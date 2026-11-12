# Who can see what in Fabric, and what sits below the workspace role?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** [`0006-access-through-entra-groups.md`](../adr/0006-access-through-entra-groups.md) — the audit story for "one group per workspace", and which governance features to adopt on day one.

## Short answer

Workspace roles are four and fully documented, and a group may hold any of them including
**Admin**. Below them sit six independent grant paths — item sharing, app audiences, publish to web,
shareable links, OneLake security roles, and SQL `GRANT` — of which only the first three are visible
to the admin APIs. The admin APIs answer "who is assigned what" but never expand a group, and never
show data-plane grants, so "who can see what" is answered by joining three sources: Fabric admin API,
Entra group membership, and per-item SQL/OneLake queries.

## Detail

### 1. The workspace role matrix, in the product's own words

Four roles: **Admin**, **Member**, **Contributor**, **Viewer**. "You can either assign roles to
individuals or to security groups, Microsoft 365 groups, and distribution lists" (roles-workspaces,
ms.date 2026-04-24).

| Capability (quoted from the matrix) | Admin | Member | Contributor | Viewer |
| --- | --- | --- | --- | --- |
| "Add or remove people, including other admins." | ✅ | | | |
| "Add members or others with lower permissions." | ✅ | ✅ | | |
| "Allow others to reshare items."^1^ | ✅ | ✅ | | |
| "Update and delete the workspace." | ✅ | | | |
| "Create or modify database items" / "warehouse items" | ✅ | ✅ | ✅ | |
| "Write or delete pipelines, notebooks, ... and shortcuts."^2^ | ✅ | ✅ | ✅ | |
| "Read Lakehouse and Data warehouse data and shortcuts ... through OneLake APIs and Spark (ReadAll)." | ✅ | ✅ | ✅ | |
| "Read ... through T-SQL ... (ReadData)." / "Connect to SQL analytics endpoint" | ✅ | ✅ | ✅ | ✅ |
| "Modify gateway connection settings."^3^ | ✅ | ✅ | ✅ | |
| "Create workspace identity" / "Connect workspace to Git repository" | ✅ | | | |

^1^ "Contributors and Viewers can also share items ... if they have Reshare permissions." ^2^ Shortcut creation sits in this row; the target path needs its own permission. ^3^ Gateway permissions are "managed elsewhere, independent of workspace roles."

Two capabilities the Fabric matrix omits: **publishing apps** is Admin/Member only ("Any Admin or
Member of a workspace can unpublish the app", service-create-distribute-apps, ms.date 2026-09-24);
**editing OneLake security** is Admin/Member, Contributor excluded (get-started-security,
ms.date 2026-09-01). That page states the consequence plainly: Viewer "Can read data in OneLake? No*"
— "\*You can give Viewers access to data by using OneLake security roles."

### 2. What sits below workspace roles, and the switch that restrains it

| Grant path | Who can create it | Tenant setting that restricts it |
| --- | --- | --- |
| **Item sharing** (Share button, "Direct access", item permissions Read/Edit/Share/Build/Execute) | Admin/Member, or anyone holding **Reshare** on the item | **Allow shareable links to grant access to everyone in your organization**; **Users can invite guest users to collaborate through item sharing and permissions** |
| **Workspace app / audience** ("An app can have permissions that are different than the permissions set on a workspace") and **org app** (`OrgApp` + `OrgAppAudience` items) | Admin/Member; audiences may include users or groups | **Publish apps to the entire organization**; **Push apps to end users** |
| **Publish to web** (public embed code) | users named by the setting | **Publish to web**, with **Choose how embed codes work** → **Allow only existing embed codes** |
| **OneLake security roles** (Read / ReadWrite on tables and folders, optional RLS/CLS) | workspace Admin or Member | none found that disables the feature; nearest lever is **Users can access data stored in OneLake with apps external to Fabric** |
| **SQL permissions** on the warehouse / SQL analytics endpoint (`GRANT`, `DENY`, SQL roles) | anyone with sufficient SQL rights in the item | none; enforced per item |

Item permissions do not inherit upward: "you can't modify or remove permissions that are inherited
from a workspace role" (share-items, ms.date 2025-04-06). Removing item permission alone does not
revoke access either — a Viewer still sees the item through the workspace (permission-model,
ms.date 2025-05-22, Example 2). Two data-plane quirks: once OneLake security exists, `ReadAll` grants
nothing directly, only through the auto-created `DefaultReader` role, so deleting that role removes
data from users who still hold `ReadAll`; and ReadWrite "can't contain row-level security (RLS) or
column-level security (CLS) constraints" (data-access-control-model, ms.date 2026-08-28).

### 3. Entra groups in Fabric

- **A group can be Admin.** "You can add security groups, mail-enabled security groups, distribution
  lists, Microsoft 365 groups, or individuals to these workspaces as admins, members, contributors,
  or viewers" (give-access-workspaces, ms.date 2025-06-10).
- **Nesting works.** "If you nest user groups and assign a role to a group, all the contained users
  have permissions" (roles-workspaces). Access counts are "calculated by flattening membership of all
  nested groups ... also include +1 for each nested group" (content-sharing, ms.date 2024-08-07).
- **The portal and the API show the group, not the people.** `List Workspace Access Details` returns
  a principal of `type: "Group"` with `groupType: "SecurityGroup"` and no member array; expansion is
  an Entra query, not a Fabric one.
- **Audit:** the audit log records operations attributed to the acting principal (track-user-activities,
  ms.date 2026-02-12; operation names in operation-list). Group membership changes are Entra events,
  not Fabric ones. Could not establish any Learn statement that Fabric audit expands a group.
- **Service principals** "can also be assigned to workspace roles and inherit the same permissions as
  users for API-based operations" (roles-workspaces), and a documented Git automation step is
  literally "Add Service Principal as Workspace Admin" (automate-git-integration-with-service-principal,
  ms.date 2026-09-01). They cannot sign in to the portal.
- **Where a group of only SPs breaks:** the group is the documented *workaround*, not a failure —
  "Service principals can't be added to protection policies directly ... first add them to an Azure
  security group, and then add this group to the protection policy". It also satisfies the admin-API
  "allowed security group". It grants no interactive access, and SPs still "can't be added to an RLS
  role" (row-level-security-limitations, ms.date 2024-09-20).

### 4. Auditing "who has access": endpoints, permissions, and blind spots

All Fabric admin endpoints below: "The caller must be a Fabric administrator or authenticate using a
service principal"; scope `Tenant.Read.All` or `Tenant.ReadWrite.All`.

| Endpoint | Returns | Notes |
| --- | --- | --- |
| `GET /v1/admin/workspaces` | id, name, type, state, `capacityId`, `domainId`, tags | 10,000/page, **200 requests/hour**; `state=Deleted` available |
| `GET /v1/admin/workspaces/{workspaceId}/users` | List Workspace Access Details: principals + `workspaceRole` (`Admin`/`Member`/`Contributor`/`Viewer`) | **Preview**; 200/hour; groups returned unexpanded |
| `GET /v1/admin/workspaces/{workspaceId}/items/{itemId}/users` | List Item Access Details: principals + `permissions` (`Read`, `Write`, `Reshare`, `Explore`, `Execute`) and `additionalPermissions` (`readAll`, `viewOutput`) | **Preview**; `type` required for `Report`, `Dashboard`, `SemanticModel`, `App`, `Dataflow` |
| `GET /v1/admin/items` | item id, type, workspace, `creatorPrincipal`, `defaultIdentity` | **Preview**; 10 requests/minute, 200/hour — access, not ownership |
| `GET /v1/admin/domains/{domainId}/roleAssignments` | domain admins and contributors | same scope; SP supported |

Power BI admin equivalents remain necessary for app and web exposure:
`Groups GetGroupUsersAsAdmin`, `Users GetUserArtifactAccessAsAdmin`, `Apps GetAppUsersAsAdmin`,
`WidelySharedArtifacts PublishedToWeb`, `WidelySharedArtifacts LinksSharedToWholeOrganization`,
`Get Activity Events` (enable-service-principal-admin-apis, ms.date 2026-06-26). All of it needs two
switches under **Admin API settings** — **Service principals can access read-only admin APIs** and
**Service principals can access admin APIs used for updates**, each scoped to a security group — and
the app "must not have any admin-consent required permissions for Power BI".

**Invisible to all of the above:** OneLake security role membership and RLS/CLS predicates; SQL
`GRANT`/`DENY` and database roles (`sys.database_permissions` "doesn't return permissions that users
receive through a Fabric workspace role or item", sql-granular-permissions, ms.date 2026-06-25);
semantic-model RLS role membership; shortcut targets and the identity a delegated shortcut uses;
workspace identity consumers; group membership itself; and anything in a personal **My workspace**.

### 5. Governance features worth adopting early, and what each costs

| Feature | What it buys | Cost / trap |
| --- | --- | --- |
| **Domains** (+ subdomains) | Catalogue scoping and delegation of specific settings; roles **Fabric admin**, **Domain admin**, **Domain contributor** | "Domain assignment doesn't affect item visibility or accessibility" — it is not a security boundary. A default domain auto-assigns unassigned workspaces of named users/groups. REST control via `/v1/admin/domains` |
| **Sensitivity labels** | Purview classification, protection, export control | **Not preserved by Git**: "Sensitivity labels aren't included when exporting an item" (git-integration-admin-settings, ms.date 2026-10-07). **Copied by deployment pipelines only** when "a new item is deployed, or an existing item is deployed to an empty stage", or a protected label overrides an unlabelled target (understand-the-deployment-process, ms.date 2026-09-24). REST `Create Item` takes an explicit `sensitivityLabelSettings` (`labelId`, `sensitivityLabelApplyStrategy`: `ApplyOrFail` default or `Ignore`) — a Terraform deploy that omits it ships unlabelled |
| **Endorsement** (`Promoted`, `Certified`, `Master data`) | Discovery signal | Promoted is self-service for "any user with write permissions"; Certified needs admin-nominated certifiers and the **Certification** setting; Master data needs **Endorse master data**. Domain admins can override certification per domain (endorsement-overview, ms.date 2024-07-11) |
| **Workspace identity** | An auto-managed service principal for trusted workspace access and outbound auth | GA; workspace Admin only; "except My workspaces"; creates an app registration in Entra that admins must not edit; deletion "cannot be restored" and breaks dependent items (workspace-identity, ms.date 2026-09-16) |
| **OneLake security roles** | Table/folder/row/column control for Viewers | 250 roles per item, 500 members per role; ~5 minutes for role changes, ~1 hour for group changes; distribution lists "can't resolve the members" at the SQL analytics endpoint; nested groups not resolved across producer → consumer |

### 6. Things that surprise people

- **Sole admin leaves:** the workspace becomes **Orphaned** — "A workspace with no admin user. You need
  to assign an admin" (portal-workspaces, ms.date 2026-09-08); the API still reports it as `Active`.
- **Deleted group:** cloud security groups are "retained but not visible for 30 days" and restorable;
  distribution groups are not restorable at all. What Fabric shows for a permanently purged group's
  assignment: **could not establish**.
- **Role changes are not immediate:** "After you add or remove workspace access for a user or a group,
  the permission change only takes effect the next time the user logs into Microsoft Fabric"
  (give-access-workspaces). Item-permission revocation can take "up to two hours ... if the user is
  signed-in".
- **A service principal can be a workspace Admin** — documented for Git automation and Premium
  operations ("add the service principal as an **Admin** or **Member**"). It cannot use the portal,
  cannot hold a semantic-model RLS role, cannot take over item ownership. And group-based admin is one
  click away: nothing in the product prevents granting `Admin` to a group, only your process does.

## What this settles

- **Day one** (cheap, reversible, closes the obvious holes): one Entra security group per workspace
  carrying `Contributor` or `Viewer`; `Admin` to named humans; turn off **Allow shareable links to
  grant access to everyone in your organization** and set **Publish to web** to **Allow only existing
  embed codes**; enable the two **Admin API settings** for the admin service principal; run the
  workspace and workspace-access scans nightly; enable **Certification** with a named certifier list.
- **Can wait a year:** OneLake security roles and SQL-level grants — per item, per engine, capped
  (250 roles / 500 members) and slower to converge than role membership; add them when a Viewer must
  see a subset of a lakehouse, not as a general access model. Domains too: they buy catalogue
  filtering and delegated setting overrides, not access control, so add them when delegation hurts.
- **Never automate:** sensitivity labels as a deploy-time guarantee. Git drops them and REST only
  carries them when the call says so; treat labelling as a post-deploy check, not a pipeline output.

## What this does not establish

- What Fabric displays for a role assignment whose Entra group has been permanently deleted.
- Whether Fabric audit records ever expand a group to member UPNs; no Learn page read states either way.
- Whether a group containing only service principals is accepted by both admin-API allow-list toggles
  — only that a group is the documented way to attach an SP where direct attachment is refused.
- Whether Terraform's `fabric_workspace_role_assignment` has the same next-sign-in latency as the
  portal, and any behaviour of the work tenant's actual settings: the provider is not a Learn page,
  and nothing here is observed configuration.

## Correction — 2026-11-12

The short answer above says only item sharing, app audiences and publish-to-web are visible to the
admin APIs, leaving OneLake security roles and SQL grants entirely invisible. That is half right.
[`onelake-security-model.md`](onelake-security-model.md) establishes that OneLake data access roles
are readable per item through the item's own `dataAccessRoles` endpoint with only item `Read` — so
role definitions and membership are visible, just not through `/v1/admin/*`. SQL `GRANT`s remain
outside every API. Two consequences: an access report must join a third source rather than two, and
a Viewer with item Read can enumerate their co-members.

## Sources

| Source | What it was used for |
| --- | --- |
| [Roles in workspaces in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/roles-workspaces) (ms.date 2026-04-24) | The capability matrix, nesting, group types, SP inheritance |
| [Permission model](https://learn.microsoft.com/en-us/fabric/security/permission-model) (2025-05-22) | Workspace vs item vs compute permissions; order of evaluation |
| [Share items in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/share-items) (2025-04-06) | Item permission model; 2-hour revocation latency |
| [Give users access to workspaces](https://learn.microsoft.com/en-us/fabric/fundamentals/give-access-workspaces) (2025-06-10) | Group types admissible as Admin; next-sign-in latency; 1,000-principal cap |
| [OneLake security: get started](https://learn.microsoft.com/en-us/fabric/onelake/security/get-started-security) (2026-09-01) | Role table including "Can edit OneLake security" |
| [OneLake security roles, permissions, and scopes](https://learn.microsoft.com/en-us/fabric/onelake/security/data-access-control-model) (2026-08-28) | `DefaultReader`, ReadWrite limits, DL and nested-group limitations, propagation |
| [SQL granular permissions in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/data-warehouse/sql-granular-permissions) (2026-06-25) | `GRANT`/`DENY`, `sys.database_permissions` blind spot |
| [Enable service principal authentication for admin APIs](https://learn.microsoft.com/en-us/fabric/admin/enable-service-principal-admin-apis) (2026-06-26) | Both admin-API switches, allowed security group, Power BI admin API list |
| [Workspaces – List Workspaces](https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces/list-workspaces) (v1, updated 2026-09-15) | Endpoint, scope, 200/hour, orphaned-as-active |
| [Workspaces – List Workspace Access Details](https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces/list-workspace-access-details) (Preview) | `GET .../users`, `workspaceRole`, group principal schema |
| [Items – List Item Access Details](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-item-access-details) (Preview) | Item permissions enum, `type` requirement |
| [Items – List Items](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-items) (Preview) | Rate limits, `creatorPrincipal` |
| [Domains](https://learn.microsoft.com/en-us/fabric/governance/domains) (2025-05-01) | Domain roles, delegation, "doesn't affect item visibility" |
| [Information protection in Fabric](https://learn.microsoft.com/en-us/fabric/governance/information-protection) (2026-07-13) | Capability table, programmatic labelling, inheritance limits |
| [Git integration admin settings](https://learn.microsoft.com/en-us/fabric/admin/git-integration-admin-settings) (2026-10-07) | "Sensitivity labels aren't included when exporting an item" |
| [Understand the deployment process](https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process) (2026-09-24) | When labels are copied between stages |
| [Create Item (REST)](https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item) | `sensitivityLabelSettings`, `ApplyOrFail` default |
| [Endorsement overview](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) (2024-07-11) | Promoted / Certified / Master data and who may grant each |
| [Workspace identity](https://learn.microsoft.com/en-us/fabric/security/workspace-identity) (2026-09-16) | Creation rights, lifecycle, deletion consequences |
| [Manage workspaces (admin portal)](https://learn.microsoft.com/en-us/fabric/admin/portal-workspaces) (2026-09-08) | Workspace states, "Orphaned: A workspace with no admin user" |
| [Export and sharing settings](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-export-sharing) (2026-04-08) | Exact names of shareable-link, guest and publish-to-web settings |
| [Tenant settings index](https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index) (2026-08-28) | **Publish apps to the entire organization**, **Push apps to end users** |
| [Track user activities](https://learn.microsoft.com/en-us/fabric/admin/track-user-activities) (2026-02-12) | Audit log entry point and prerequisites |
| [Restore a deleted Microsoft 365 group or cloud security group](https://learn.microsoft.com/en-us/entra/identity/users/groups-restore-deleted) (2026-03-11) | 30-day retention; distribution groups not restorable |
| [Automate Git integration with a service principal](https://learn.microsoft.com/en-us/fabric/cicd/git-integration/automate-git-integration-with-service-principal) (2026-09-01) | "Add Service Principal as Workspace Admin" |

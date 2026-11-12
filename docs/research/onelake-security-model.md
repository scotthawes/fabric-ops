# What is the OneLake data security model, and what can a deployment-and-access pipeline do about it?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** `backlog.md` B4; the data-plane section of the access report; whether OneLake roles join the deploy
  surface. Extends [`governance-access-and-workspace-roles.md`](governance-access-and-workspace-roles.md) §2, §4.

## Short answer

OneLake security is a **grant-only, deny-by-default RBAC layer on the data plane**: roles carry `Read` or `ReadWrite`
over tables, folders and schemas, optionally narrowed by RLS and CLS, and they bind only Viewers and item-`Read`
principals — Admin, Member and Contributor keep their workspace write access whatever a role says. It is
**engine-dependent, not universal**: the SQL analytics endpoint starts in delegated identity mode, where OneLake roles
are ignored and reads run as the item owner. A pipeline *can* write these roles (bulk `PUT …/dataAccessRoles`, a
preview Terraform resource) but should not in v1: renames are destructive, deletion is a data outage, and each role
encodes a data-owner judgement.

## Detail

### 1. The roles, in the product's own words

Four components: **Permissions**, **Type**, **Data in role**, **Members in role** (data-access-control-model, ms.date
2026-08-28). Two permissions and no others. **`Read`**: "read data from a table and view the associated table and
column metadata. In SQL terms … equivalent to both `VIEW_DEFINITION` and `SELECT`." **`ReadWrite`**: "equivalent to
`ALTER`, `DROP`, `UPDATE`, and `INSERT`", and it "only applies to users with the Read permission on an item" — on an
Admin, Member or Contributor it "has no effect".

Only **Grant** roles: "It doesn't support Deny roles that remove access." Scope is object-level — the role table's
**Type** column reads **Schema**, **Table**, **Folder** — and "Schemas are also folders" (table-column-row-security,
2026-08-19), so a role covers tables, folders and schemas but not the item; the portal scopes it as **All data** or
**Selected data**. RLS
and CLS are Read-only: a ReadWrite role "can't contain row-level security (RLS) or column-level security (CLS)
constraints". RLS is one T-SQL predicate per table and "RLS roles don't support dynamic and multitable queries"; CLS is
a **Hide** allow-list; both need "a single OneLake security role".

Role-carrying items: **Lakehouse** (Read, ReadWrite); **Azure Databricks mirrored catalog**, **Mirrored databases**,
**Mirrored catalogs** (Read only). Warehouse is absent — that data is reached through SQL grants. Created in the item's
**Manage OneLake security** pane by a principal with "Fabric **Write** or **Reshare** permissions (generally included
for Admin or Member workspace users)" (create-manage-roles, 2026-09-25); members are users, Microsoft Entra groups and
security principals, or **virtual members** via **Advanced configuration** on **Read**, **Write**, **Reshare**,
**Execute**, **ReadAll**; names are alphanumeric, starting with a letter, unique, "maximum name length is 128
characters".

Limits: **250 roles per item** (raisable "to 1,000" via support), **500 users or user groups per role**, **500
permissions per role**. Resolution is algebra — within a role `OLS ∩ RLS ∩ CLS`, across roles a union, RLS predicates
combining with `OR` — except that the SQL endpoint "intersects CLS allow lists", and "OneLake doesn't support a role
combination in which two roles allow a different set of columns for a table and either role also applies RLS".

### 2. Interaction with workspace roles — confirmed, with one correction

Confirmed verbatim: "In an item with OneLake security enabled, `ReadAll` doesn't grant data access on its own. It
grants access through the `DefaultReader` role. If you delete `DefaultReader`, users who relied on that role lose data
access, even if they still have ReadAll permission."

The trigger needs correcting: this is not a state you enter. "A default role is a normal OneLake security role that
Fabric automatically creates with **every new item**", with members virtualised to "any users in that workspace with the
required permission". Every lakehouse already sits in that state, `DefaultReader` granting `Read` to all `ReadAll`
holders. The trap is not enabling anything — it is that **any restrictive role is a union with `DefaultReader`**, hence
the warning printed twice: "verify that the `DefaultReader` role doesn't already grant them broader access."

Deleting it removes the lakehouse from every `ReadAll` holder at once; "To restore access, assign the affected users or
groups to another OneLake security role", and Admins, Members and Contributors "retain access through their Write
permission" — which makes the outage look selective.

For a **Contributor**, OneLake security does nothing in either direction: they cannot be restricted ("these controls
don't restrict access for users in the Admin, Member, and Contributor roles at the workspace level") and cannot grant,
because "Can edit OneLake security? No" (get-started-security, 2026-09-01). A Contributor assuming a role narrows their
own access, or that a role protects data from them, is wrong twice. §7 has the one contradiction.

### 3. OneLake roles vs SQL `GRANT` vs item permissions vs item sharing

One setting per SQL analytics endpoint — **Data access mode** — decides which layer is authoritative; the grants do not
add up.

| Control | Set where | Enforced when | Silently overridden by |
| --- | --- | --- | --- |
| OneLake security role | item → **Manage OneLake security** | any engine that honours it (§5, §7) | SQL endpoint in **Delegated identity access mode** |
| SQL `GRANT`/`DENY`, SQL roles, `CREATE SECURITY POLICY` | the SQL endpoint | **Delegated identity** only | **User's identity access mode**: "SQL `GRANT`/`REVOKE` statements on tables are ignored"; "Existing SQL roles are deleted and can't be recovered" |
| Item permission (`Read`, `Write`, `Reshare`, `Explore`, `Execute`, `ReadData`, `ReadAll`) and item sharing | **Manage permissions** / Share | always — the gate, not a filter | nothing |

The item permissions decide engines: `Write` sees data in SQL **and** OneLake, `Read` in neither, `ReadData` in SQL
"Only in **Delegated mode**", `ReadAll` in OneLake "Only through the **DefaultReader**".

Two gates precede all of it. Item `Read` is required to connect — "the connection to the SQL analytics endpoint is
rejected, regardless of any SQL permissions that might exist for that user". And user identity mode "passes the
signed-in user's identity to OneLake", so one user needs a control-plane grant *and* a data-plane role; SQL rights alone
buy nothing, and delegated mode makes OneLake roles equally inert. Switching "makes SQL analytics endpoints temporarily
unavailable across the entire workspace".

### 4. What a pipeline can deploy

**Yes, through the Fabric REST API** — *OneLake Data Access Security*, Core v1 (Fabric REST TOC, checked 2026-11-12):

- `PUT …/items/{itemId}/dataAccessRoles` — bulk, `?dryRun=`, `If-Match`; caller needs "reshare permissions for the
  item"; `OneLake.ReadWrite.All`; 50 calls/min; **no `preview` parameter**.
- `GET` the collection ("read permissions for the item", `OneLake.Read.All` or `…ReadWrite.All`, 100/min) and
  `GET|POST|DELETE …/dataAccessRoles/{roleName}` — each single-role call needs `?preview=true` and "member or higher
  role on the workspace"; `POST` takes `?dataAccessRoleConflictPolicy=Overwrite|Abort`.
- "Service principal and Managed identities: Yes" throughout.

Payload is the portal's own object: `decisionRules[].{effect: Permit, permission[] with attributeName Path|Action,
constraints.columns[], constraints.rows[]}`, plus `members.fabricItemMembers` (`itemAccess` enum `Read`, `Write`,
`Reshare`, `Explore`, `Execute`, `ReadAll`) or `members.microsoftEntraMembers` (`tenantId` + `objectId`).

**Terraform: a preview resource exists.** `fabric_onelake_data_access_security` — "This resource is in **preview** …
you must explicitly enable the `preview` mode" — supports SP authentication and models the same rules and members;
`workspace_id`, `item_id` and `role_name` are all **ForceNew**, import is `"<WorkspaceID>/<ItemID>/<RoleName>"`, and a
plural data source `fabric_onelake_data_access_securities` exists. Its cited Learn page
(`…/onelake/security/data-access-security-overview`) returns 404: the provider is ahead of its own documentation.

**Recommendation: manual in v1, and that is fine.** (a) `role_name` is ForceNew, so a rename is destroy-then-create — a
documented five-minute-plus hole in a Viewer's access. (b) A delete is a data outage (§2). (c) Membership is a list of
Entra object IDs, putting tenant identity data in state for no gain. (d) "Which column of which table may this team
see" is a data-owner judgement with a review date, hanging off an item the content deployer creates. Automate the
**read** side instead: `GET …/dataAccessRoles` per lakehouse into the access report, plus a drift check for `Path: *`.

### 5. Shortcuts, and what external access changes

Shortcuts bypass nothing but carry no ACL of their own: "You can't define OneLake security permissions directly on a
OneLake-to-OneLake shortcut. Permissions on the folder that contains the shortcut combine with permissions on the
target path." Formally `(ShortcutRole1 ∪ ShortcutRole2) ∩ (InferredRole1 ∪ InferredRole2)` — target roles become
"inferred roles" so shortcut-side access cannot override the target. Listing is looser than reading: "when you list a
directory, OneLake returns all internal shortcuts regardless of your access to the target."

**Passthrough** ("the default for OneLake-to-OneLake shortcuts") uses the calling user's identity. **Delegated** uses
"a configured connection identity or credential", is mandatory for **cross-tenant OneLake-to-OneLake** and **external
(multicloud)** shortcuts, and shows the caller "the intersection of their access on the shortcut path and the configured
connection identity's access on the target path". For external shortcuts "OneLake security is applied on top of the
access granted by that credential" — the connection may read S3, and OneLake still decides who may. Cross-tenant
therefore changes the model rather than escaping it: the connection identity needs target access in the producer
tenant, and a B2B guest in a role needs **Guest user access** = **Guest users have the same access as members (most
inclusive)**.

The switch that bites is **Users can access data stored in OneLake with apps external to Fabric**. Off, "users can
still access data from internal apps like Spark, Data Engineering, and Data Warehouse, but can't access data from
applications running outside of Fabric environments" — the only thing between an Entra token and the lake via ADLS APIs
or OneLake File Explorer. Counter-intuitively, "This setting must be enabled to use shortcuts with OneLake security": a
tenant that turns it off to close the external door breaks secured shortcuts. External shortcut access "through Spark
or a direct OneLake API call also requires Fabric Read permission on the item", and warehouse SQL security does not
travel — "users accessing the data through a shortcut might see the full warehouse data".

### 6. Auditability, and what the access report must admit

- **Invisible to the admin APIs; readable per item.** `List Item Access Details` returns `permissions` and
  `additionalPermissions` (`Read`/`Write`/`Reshare`/`Explore`/`Execute`, `readAll`, `viewOutput`) and nothing else, and
  nothing under `/v1/admin/*` enumerates roles. But `GET …/items/{itemId}/dataAccessRoles` returns roles *and* members
  with only "read permissions for the item" plus `OneLake.Read.All`, so the governance note's "invisible to all of the
  above" is right about the admin APIs and wrong as a general claim. By that stated bar a Viewer could enumerate
  co-members — my inference from the permission text, untested.
- **Audit log: probable, unproven.** `operation-list` has `GetArtifactRoles` ("Get USEC roles for an artifact") and
  `UpdateArtifactRoles` ("Update USEC roles for an artifact"), both "OneLake operation". "USEC" is never expanded, so I
  cannot confirm these are role writes.
  **Corrected 2026-11-12:** `UpdateArtifactRoles` is an audit operation name with no API behind it; the write path is the
  GA `PUT …/items/{itemId}/dataAccessRoles` and the matching audit operation is `CreateOrUpdateDataAccessRoles`. Role
  changes are documented as reaching the Fabric audit log; before/after content is not — see the answered block at the
  foot of this note.
- **Data access: only OneLake diagnostics.** "To audit OneLake data access and storage operations, use OneLake
  diagnostics. The Fabric audit log isn't a complete source for OneLake data-plane activity." Enable **Add diagnostic
  events to a lakehouse**; events carry `executingUPN`, `operationName`, `isShortcut`, `accessedViaResource`,
  `originatingApp`, `callerIPAddress`. But "For Fabric workloads access, it records that temporary access was granted"
  — reads prove *that* access happened, not which role allowed it.

### 7. Failure modes people actually hit

1. **A Viewer reads everything through SQL and nothing through Spark.** Endpoints "start in delegated identity access
   mode by default", where "security is governed exclusively by SQL permissions" and reads "use the identity of the
   Lakehouse or SQL analytics endpoint owner". The Viewer's lack of `ReadAll` is irrelevant; the owner's access is the
   access. Fix: **User's identity access mode**, accepting workspace-wide query cancellation and that "Existing SQL
   roles are deleted and can't be recovered".
2. **A role that appears to grant nothing.** Usually the user is still in `DefaultReader`, and a union cannot subtract.
   Otherwise: the folder fails the table test (needs `_delta_log`, no child shortcuts) and is secured as a folder; a
   rule references a renamed column, "denying all access to the resource"; or sync is stalled — it "may temporarily
   pause automatic synchronization", resuming "when an existing OneLake security role is modified or a new one is
   created", so the portal looks right while enforcement is stale.
3. **`DefaultReader` deleted.** Every `ReadAll` holder loses the lakehouse at once while Admins, Members and
   Contributors are unaffected — it reads as a partial outage. Same shape when an apply destroys a role because
   `role_name` changed.
4. **"I removed their access and they still have it."** Four clocks: workspace roles apply "the next time the user logs
   into Microsoft Fabric"; role definitions ~5 minutes, group membership ~1 hour, plus engine cache; item-permission
   revocation "up to two hours … if the user is signed-in"; delegated-mode SQL caches the owner's token, so owner-side
   changes "can persist until token expiration, typically up to 30–60 minutes".
5. **A Contributor expecting to be restricted**, **the RLS contradiction** (the SQL endpoint page says RLS "is enforced
   for all users, including those in Admin, Member, and Contributor roles", irreconcilable with the grant-only model on
   the same page and in §1), and **the edges that don't resolve**: distribution lists and mail-enabled security groups
   at the SQL endpoint, so "users appear not to be members of the role"; nested groups across producer → consumer,
   which must match "**exactly 1:1**"; and a role name that is 128 characters in the portal but "cannot exceed 124
   characters" for sync.

## What this settles

- **Decision rule.** Use an OneLake security role only when all three hold: the principal is a **Viewer** or holds item
  `Read`/`ReadAll`; the requirement is a subset of *one item* (named tables/folders, or rows/columns); and the consumer
  path honours the role — Spark, Direct Lake on OneLake, Eventhouse, or a SQL endpoint in **User's identity access
  mode**. "Can query but not build" is a workspace **Viewer**; "one item, named owner, review date" is item sharing;
  genuinely table-shaped and T-SQL-only is **delegated mode + SQL `GRANT`**, accepted with the endpoint reading as the
  item owner. Never mix modes inside one item and expect one answer.
- **Must stay manual.** Creating, renaming and deleting roles; `All data` vs `Selected data`; every RLS predicate and
  CLS column list; removing a user from `DefaultReader` (the step that actually restricts anyone); switching an SQL
  endpoint's access mode; a cross-tenant shortcut's connection identity.
- **Worth automating.** `GET …/dataAccessRoles` into the access report, and a drift check that no lakehouse has
  silently gained a role with `Path: *`.

## What this does not establish

- Whether `UpdateArtifactRoles`/`GetArtifactRoles` are the role write path — **partly answered 2026-11-12:** they are
  audit names only, the write path is `PUT …/dataAccessRoles` (see the answered block at the foot of this note). Still
  open for a tenant: whether the audit record carries before/after values.
- Whether RLS in user identity mode really binds Admins, Members and Contributors. Two Learn pages contradict each
  other; "grants don't restrict them, but a predicate they are a member of does" is the only reconciling reading, and a
  tenant test must settle it. **Reread 2026-11-12:** the contradiction survived a direct comparison of both pages —
  neither states that condition, so it is still a tenant test.
- Whether the REST `preview=true` parameter marks a preview API or a preview feature (bulk `PUT` needs none), and
  whether a Viewer can in fact call `GET …/dataAccessRoles`.
- Whether `DefaultReader` is recreated if deleted, or only at item creation; whether the 250-role cap counts it; and
  whether the Terraform resource sends `preview` and survives a rename without an access gap.
- The work tenant's actual state: whether its SQL endpoints are delegated or user identity, whether OneLake diagnostics
  is on, whether external-apps access is enabled. All three need the portal.

## Sources

| Source | What it was used for |
| --- | --- |
| [OneLake security roles, permissions, and scopes](https://learn.microsoft.com/en-us/fabric/onelake/security/data-access-control-model) (2026-08-28) | Role components, `Read`/`ReadWrite`, grant-only, default roles, `DefaultReader`/`ReadAll`, shortcut formulas, limits, latencies |
| [Data security overview](https://learn.microsoft.com/en-us/fabric/onelake/security/get-started-security) (2026-09-01) | Control vs data plane, "Can edit OneLake security", item-permission engine table, external-apps setting |
| [Create and manage OneLake security roles](https://learn.microsoft.com/en-us/fabric/onelake/security/create-manage-roles) (2026-09-25) | Prerequisites, name rules, `All data`/`Selected data`, virtual members |
| [Table, column, and row-level security in OneLake](https://learn.microsoft.com/en-us/fabric/onelake/security/table-column-row-security) (2026-08-19) | Grant-only consequence for write roles, schema-as-folder, no dynamic RLS |
| [OneLake Security for SQL analytics endpoints](https://learn.microsoft.com/en-us/fabric/onelake/security/sql-analytics-endpoint-onelake-security) (2026-07-22) | Mode comparison, SQL roles deleted on switch, 1:1 mapping, per-mode shortcuts, RLS contradiction, 124-char limit |
| [Secure and manage OneLake shortcuts](https://learn.microsoft.com/en-us/fabric/onelake/onelake-shortcut-security) (2026-07-31) | Shortcut permission tables, passthrough vs delegated by type |
| [OneLake diagnostics](https://learn.microsoft.com/en-us/fabric/onelake/onelake-diagnostics-overview) (2026-01-12) | Event fields, "records that temporary access was granted", enable toggle |
| [Activity log operation list](https://learn.microsoft.com/en-us/fabric/admin/operation-list) | "The Fabric audit log isn't a complete source…"; `GetArtifactRoles`/`UpdateArtifactRoles` |
| [OneLake Data Access Security – REST (Core v1)](https://learn.microsoft.com/en-us/rest/api/fabric/core/onelake-data-access-security/) | Five operations, paths, `preview`/`dryRun`/conflict policy, scopes, throttling, SP support, role schema |
| [List Item Access Details](https://learn.microsoft.com/en-us/rest/api/fabric/admin/items/list-item-access-details) | Admin-API blind spot: `permissions` and `additionalPermissions` only |
| [terraform-provider-fabric — `onelake_data_access_security`](https://github.com/microsoft/terraform-provider-fabric/blob/main/docs/resources/onelake_data_access_security.md) | Preview resource, ForceNew fields, import syntax; cited Learn page 404s |
| [fabric-sdk-go — `onelakedataaccesssecurity_client.go`](https://github.com/microsoft/fabric-sdk-go/blob/main/fabric/core/onelakedataaccesssecurity_client.go) | Confirms the routes and verbs behind the provider |

## Answered 2026-11-12 — Is `UpdateArtifactRoles` the write path for OneLake security roles, and is it audited with before/after values?

**Answer.** Not as named. `UpdateArtifactRoles` is an audit operation name and corresponds to no documented API. The write path is the generally available `PUT …/items/{itemId}/dataAccessRoles` (`operationId` `OneLakeDataAccessSecurity_CreateOrUpdateDataAccessRoles`), and the audit operation whose name matches that operation is **`CreateOrUpdateDataAccessRoles`** — "Creates or updates data access roles" — not `UpdateArtifactRoles`. That role changes reach the Fabric audit log is now documented outright; whether the record carries before/after role definitions is not documented anywhere and needs a tenant.

**Evidence** (all checked 2026-11-12):

| Check | Finding | Source |
| --- | --- | --- |
| `artifactRoles` in the OpenAPI | Absent. `microsoft/fabric-rest-api-specs` at `3f8600f` contains five `dataAccessRoles` operations and no `artifactRoles` path or definition | clone of [fabric-rest-api-specs](https://github.com/microsoft/fabric-rest-api-specs) |
| The write operation | `PUT https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/items/{itemId}/dataAccessRoles`; "Creates or updates data access roles in OneLake."; only query parameter `dryRun`; `If-Match`/`If-None-Match`; 50 calls/min; "The caller must have *reshare* permissions for the item" | [Create Or Update Data Access Roles](https://learn.microsoft.com/en-us/rest/api/fabric/core/onelake-data-access-security/create-or-update-data-access-roles) (ms.date 2022-12-28; updated 2026-11-10) |
| Identity table | `User` — Yes; `Service principal and Managed identities` — Yes | same page |
| Preview or GA (bulk `PUT`) | No `preview` parameter: across all five operations the OpenAPI carries only `dryRun`, `continuationToken` and `dataAccessRoleConflictPolicy`. The Learn pages for the single-role operations were not re-read here, so §4's `?preview=true` is unconfirmed by the spec rather than contradicted by it | same page, and `platform/swagger.json` |
| Under `/v1/admin`? | No. The path sits under `/v1/workspaces/…`. The `admin` group's role paths are `domains/{domainId}/roleAssignments` and `connections/{connectionId}/roleAssignments` — nothing for item data roles | `admin/swagger.json` (60 operations) |
| Audit name | `CreateOrUpdateDataAccessRoles` — "Creates or updates data access roles"; and `ListDataAccessRoles` — "Returns a list of data access roles" | [Operation list](https://learn.microsoft.com/en-us/fabric/admin/operation-list) (ms.date 2026-11-12, updated 2026-11-10) |
| Is auditing documented at all | "For OneLake control-plane activities, such as changes to security roles, shortcuts, sharing, lifecycle policies, and storage tiers, use the Fabric audit log." | [Data security overview](https://learn.microsoft.com/en-us/fabric/onelake/security/get-started-security) (ms.date 2026-09-01, updated 2026-09-29) |
| `UpdateArtifactRoles` elsewhere | One Learn page only — the operation list. GitHub code search returns six files, of which the only Microsoft one is `MicrosoftDocs/fabric-docs/docs/admin/operation-list.md`; no SDK, provider or spec refers to it | GitHub code search, 2026-11-12 |
| Before/after fields | The Power BI audit schema that Fabric events extend adds twelve properties — `AppName`, `DashboardName`, `DataClassification`, `DatasetName`, `ActivityStatus`, `MigrationTriggerType`, `MembershipInformation`, `OrgAppPermission`, `ReportName`, `SharingInformation`, `SwitchState`, `WorkSpaceName` — and none is a previous/current value pair. `ModifiedProperties`, `OldValue` and `NewValue` appear in that document only under other workloads' schemas | [Microsoft 365 Management Activity schema](https://learn.microsoft.com/en-us/office/office-365-management-api/office-365-management-activity-api-schema#power-bi-schema) |

**What is still unestablished.**

- **Which audit operation the `PUT` actually emits.** The operation list now carries two pairs that both read as OneLake role operations: `GetArtifactRoles`/`UpdateArtifactRoles` ("Get/Update USEC roles for an artifact", note "OneLake operation.") and `ListDataAccessRoles`/`CreateOrUpdateDataAccessRoles`. "USEC" is still never expanded, so "it is the legacy internal name for the same write" is not excluded. Name-matching is evidence, not identity: `ListDataAccessRoles` is described as "Returns a list of data access roles" while the REST summary is "Returns a list of OneLake roles."
- **Whether the record carries the role definitions.** The operation being logged is documented; the payload is not. No page read describes the contents of a `CreateOrUpdateDataAccessRoles` record, and the schema has no field shaped for one.
- **What settles it: one tenant.** Make one role change in the portal and one through `PUT …/dataAccessRoles`, then open `purview.microsoft.com/audit/` and read `AuditData` for both records over that window. That names the operation and shows whether the role payload, prior values, or only an actor-and-item pair is present. Documentation cannot settle it, and neither can any amount of further page-reading.
- **Verdicts:** no row in [`automation-coverage.md`](../guides/automation-coverage.md) changes. `Create OneLake security roles` stays **Gated** — the reason is `role_name` being ForceNew, not visibility. The answer does mean a role write is not invisible to an auditor, which strengthens the read-side drift check in §4 rather than the deploy case.

## Answered 2026-11-12 — Does row-level security bind the Admin/Member/Contributor workspace roles in user-identity mode?

**Answer.** The documentation asserts both positions and never reconciles them. Three pages state that the workspace roles are not restricted by OneLake security; one page states, as an explicit exception, that RLS in user identity mode is enforced "for all users, including those in Admin, Member, and Contributor roles". Neither statement carries the condition that would make both true — membership of the role holding the predicate — so the question is undecided on paper and needs a tenant.

**Evidence** (all checked 2026-11-12). The two pages that conflict:

[OneLake Security for SQL analytics endpoints](https://learn.microsoft.com/en-us/fabric/onelake/security/sql-analytics-endpoint-onelake-security) — ms.date 2026-07-22, updated 2026-09-09. Under **Limitations → Applies only to readers → Exceptions**:

> "**RLS in user identity mode**: When row-level security (RLS) is configured in user identity mode, the defined security rules are enforced for all users, including those in Admin, Member, and Contributor roles."

The same page, two paragraphs apart, states the general rule and then the switch note:

> "OneLake security is primarily enforced for users accessing data through **Viewer**-level workspace or item access. Users with broader workspace roles such as **Admin**, **Member**, or **Contributor** retain elevated access and are not the primary target of OneLake security enforcement."

> "Only users with Viewer permissions or shared read-only access are governed by OneLake security."

[OneLake table, column, and row-level security](https://learn.microsoft.com/en-us/fabric/onelake/security/table-column-row-security) — ms.date 2026-08-19, updated 2026-08-19, second paragraph:

> "OneLake security roles use a grant model to give access to data. You can't deny access that is granted through a different role or permission model. For that reason, these controls don't restrict access for users in the Admin, Member, and Contributor roles at the workspace level."

Two further pages repeat the second position with no carve-out:

| Page | Date | Sentence |
| --- | --- | --- |
| [Data security overview](https://learn.microsoft.com/en-us/fabric/onelake/security/get-started-security) | ms.date 2026-09-01, updated 2026-09-29 | "Workspace Admins, Members, and Contributors already have read and write permissions on all data in a workspace, so they're not affected by OneLake security roles." Its plane table adds "Admins, Members, and Contributors already have data access." |
| [OneLake security roles, permissions, and scopes](https://learn.microsoft.com/en-us/fabric/onelake/security/data-access-control-model) | ms.date 2026-08-28, updated 2026-10-16 | "(Default roles apply only to Viewers, because Admin, Member, and Contributor roles have elevated access through the Write permission.)" and "Workspace Admins, Members, and Contributors retain access through their Write permission." |

**Is it a real contradiction?** Tested against the four ways it could dissolve:

| Candidate reconciliation | Verdict |
| --- | --- |
| Different modes — user identity vs default/workspace identity | **No.** The exception names user identity mode explicitly. The other pages are mode-agnostic but describe the same roles and the same predicates. |
| Different layers — OneLake security roles vs SQL/warehouse RLS | **Partly, and it is the most useful distinction found.** The exception is on the SQL analytics endpoint page, but its own comparison table places RLS "Defined as part of OneLake security roles" under user identity mode, so this is OneLake RLS, not a `CREATE SECURITY POLICY`. It is nonetheless the *endpoint* asserting it, and the endpoint's sync service is documented as "Translating OneLake-defined policies (RLS, CLS, OLS) into equivalent SQL-compatible database role structures", propagated "with the `OLS_` prefix". If RLS binds an Admin anywhere, it will be there first; whether Spark and the other engines follow is not stated. |
| Different product generations | **No.** All four pages are current, the newest updated 2026-10-16. |
| Different scope — the sentence is about role membership, not about workspace role | **This is the only reading under which both are true, and neither page says it.** A grant cannot subtract; a row predicate is not a grant. The exception says "all users" with no membership condition; the other page says "these controls" with no exception. |

Read strictly, the documented algebra points away from the exception. Access for these roles is not a role grant at all — it is the control plane `Write` permission ("retain access through their Write permission"), and `DefaultReader`, whose members are "All users with ReadAll permission", does not include them. `data-access-control-model` then says that across multiple roles "row-level security rules combine with an `OR` operator". With no role-derived grant to attach a predicate to, OR-ing an unrestricted grant with a predicate yields the unrestricted grant — which is the §1 grant-only model and page B. The note's earlier reconciling line, "grants don't restrict them, but a predicate they are a member of does", remains a plausible *implementation* and is not what any page states. Supporting that the exception records observed behaviour rather than designed semantics: its sibling exceptions are all cases where enforcement is unexpectedly more restrictive — "Shortcut deny behavior" and "Security sync failure cases".

**What is still unestablished.**

- Whether an explicit RLS predicate filters reads by a workspace Admin, Member or Contributor, in any engine. No page read states a mechanism by which a principal whose access comes from `Write` acquires a predicate.
- **What settles it: one tenant, four observations.** A lakehouse with one table; a Viewer and an Admin; one role granting `Read` on that table with a row predicate (for example `select * from T where Region = "EMEA"`); the Admin added as an explicit member. Then compare (a) the Admin in a Spark notebook, (b) the Admin at the SQL endpoint in **User's identity access mode**, (c) the same Admin after removal from the role, (d) the Viewer in the same role. If (a) and (b) filter and (c) does not, page A is right and page B needs an RLS carve-out. If only (b) filters, the effect is SQL-endpoint-only and page A's placement is exact. If neither filters, page B is right and page A's exception is wrong.
- **Verdicts:** no row in [`automation-coverage.md`](../guides/automation-coverage.md) changes. §7's "RLS contradiction" failure mode stands as written and now has both sides quoted with dates.

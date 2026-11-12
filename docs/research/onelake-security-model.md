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

- Whether `UpdateArtifactRoles`/`GetArtifactRoles` are the role write path — "USEC" is never expanded — hence whether
  role changes produce an audit record with before/after values.
- Whether RLS in user identity mode really binds Admins, Members and Contributors. Two Learn pages contradict each
  other; "grants don't restrict them, but a predicate they are a member of does" is the only reconciling reading, and a
  tenant test must settle it.
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

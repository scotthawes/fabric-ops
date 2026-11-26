# What does the Terraform provider support for Fabric domains, and for putting a workspace in one?

- **Status:** answered
- **Checked:** 2026-11-26
- **Blocks:** [issue #44](https://github.com/scotthawes/fabric-ops/issues/44) (does the automation
  principal hold Fabric administrator, and what is the domain/subdomain shape for nonprod and prod),
  and [issue #47](https://github.com/scotthawes/fabric-ops/issues/47) downstream
- **Sibling:** [`terraform-provider-surface.md`](terraform-provider-surface.md) owns the provider-wide
  inventory, authentication and preview gate. This note owns the three domain resources.

## Short answer

`microsoft/fabric` **v1.15.1** has three domain resources — `fabric_domain` and
`fabric_domain_role_assignments` (GA) and `fabric_domain_workspace_assignments` (**preview**) — and
all three call the **admin** API group, whose documented permission is "The caller must be a Fabric
administrator". A service principal is an accepted caller, but only behind the admin-API tenant
setting, an allowed group, and an app carrying no admin-consent Fabric permissions; it can never be
the *assignee* of a domain role through Terraform.

That administrator requirement is the **provider's route choice, not a platform limit**: Fabric also
offers Core `POST /v1/workspaces/{id}/assignToDomain`, which needs workspace admin plus domain
contributor or domain admin, and Core `GET /v1/domains`, which needs only `Domain.Read.All`. One
domain can hold both environments' workspaces; a subdomain has no admins and no delegated settings of
its own, so it is a catalogue branch rather than an environment boundary. `fabric_domain` supports
import and the two assignment resources do not; destroying the assignment resource **unassigns** the
workspaces.

## Detail

### 1. The surface at v1.15.1

| Terraform type | Status | Identity | Import | APIs called (all `admin` group) |
| --- | --- | --- | --- | --- |
| `fabric_domain` | GA — preview removed in v1.8.0 (2026-03-02) | `id` = domain GUID | yes: `terraform import fabric_domain.example "<DomainID>"` | `POST/PATCH/DELETE /v1/admin/domains[/{domainId}]`, `GET /v1/admin/domains` |
| `fabric_domain_role_assignments` | GA — preview removed in v1.8.0 | **none**; the schema's `id` is commented out in source | **no** | `POST /v1/admin/domains/{domainId}/roleAssignments/bulkAssign` and `/bulkUnassign` |
| `fabric_domain_workspace_assignments` | **preview** | **none**; `id` also commented out | **no** | `POST /v1/admin/domains/{domainId}/assignWorkspaces`, `/unassignWorkspaces`, `GET /v1/admin/domains/{domainId}/workspaces` |

Data sources: `fabric_domain` (one, by `id`), `fabric_domains` (all), and
`fabric_domain_workspace_assignments` (workspaces in one domain, preview). There is **no**
`fabric_domain_role_assignments` data source — the provider registers only a resource
(`internal/provider/provider.go` at v1.15.1), even though the admin API does expose a list operation
(§2).

Attributes that matter for layout:

- `fabric_domain`: `display_name` (max 40), `description` (max 256, defaults to `""`),
  `parent_domain_id` (**ForceNew**), `default_label_id` (rejects the all-zero GUID), `id` read-only.
- `fabric_domain_role_assignments`: `domain_id`, `role` ∈ `Admins` | `Contributors`, and
  `principals` — **all three ForceNew**, so every change replaces the resource. Principal `type` is
  validated against the API enum minus `ServicePrincipal` and `ServicePrincipalProfile`.
- `fabric_domain_workspace_assignments`: `domain_id` (ForceNew) and `workspace_ids`, a set with
  `SizeAtLeast(1)` — you cannot model "this domain has no workspaces" with it.

`fabric_workspace` has **no** domain attribute; `domainId` is read-only on the workspace object
(`Workspace` definition, Update Workspace) and `UpdateWorkspaceRequest` carries only `displayName`
and `description`. Assignment happens through one of the two domain routes in §2, never by patching
the workspace.

### 2. Which permission, and on which route

Everything Terraform calls is in the admin group, and each of those pages carries the same sentence:

| Operation the provider calls | Documented permission |
| --- | --- |
| Create Domain, Delete Domain, List Domains | "The caller must be a Fabric administrator." |
| Assign / Unassign Domain Workspaces By Ids | "The caller must be a Fabric administrator." |
| Role Assignments Bulk Assign (and Bulk Unassign) | "The caller must be a Fabric administrator." |
| List Domain Workspaces | "The caller must be a Fabric administrator." |

`fabric_domain`'s own docs repeat it, plus a second warning: "The caller must be a Fabric
administrator" and "the Azure application must not have any Fabric permissions that require admin
consent configured in the Azure portal".

**The platform is wider than the provider.** Each need has a Core (public-API) route with a lower
bar, and the workspace-assignment one is the path Learn's Domains article describes for domain admins
and domain contributors:

| Need | Route the provider uses | Route Fabric also offers |
| --- | --- | --- |
| Read one or all domains | `GET /v1/admin/domains[/{domainId}]` — Fabric administrator | `GET /v1/domains[/{domainId}]` — required scope `Domain.Read.All`, no permission note; and "all users within a tenant can see all the domains defined in the tenant" |
| Assign a workspace | `POST /v1/admin/domains/{domainId}/assignWorkspaces` — Fabric administrator; overrides any existing assignment unless blocked | `POST /v1/workspaces/{workspaceId}/assignToDomain` — "The caller must have contributor permissions or be a domain Admin" **and** "The caller must have workspace admin role" |
| Unassign a workspace | `POST /v1/admin/domains/{domainId}/unassignWorkspaces` — Fabric administrator | `POST /v1/workspaces/{workspaceId}/unassignFromDomain` — "The caller must have workspace admin role" only |
| Read role assignments | never called | `GET /v1/admin/domains/{domainId}/roleAssignments` — Fabric administrator |

So the honest form of the answer is: **through Terraform, all three resources require a Fabric
administrator; through Fabric, only domain create/update/delete and the role writes do — reading
domains and assigning a workspace do not.** A principal that is workspace admin and domain contributor
can assign its own workspace, but only by
calling the Core API (portal, script, `az rest`), because the provider has no resource for that route.
That is the shape of the fallback if the automation SP cannot hold Fabric administrator. The two route
families sit behind different tenant settings as well: admin APIs behind "Service principals can access
admin APIs used for updates", public APIs behind "Service principals can call Fabric public APIs".

The admin group also carries bulk operations the provider does not expose: `assignWorkspacesByCapacities`,
`assignWorkspacesByPrincipals`, `unassignAllWorkspaces`, and `syncToSubdomains`. They are relevant if a
domain is populated by capacity or by workspace owner rather than by an explicit ID list.

### 3. Is a service principal admissible?

As a **caller**, yes, on paper — on both route families:

- Every domain API, admin and Core, lists "Service principal and Managed identities: Yes" in its
  "Microsoft Entra supported identities" table (checked 2026-11-26).
- Each resource carries "This resource supports Service Principal authentication", and the provider
  sets `IsSPNSupported: true` for all three.
- Learn's "Enable service principal authentication for admin APIs" describes the admin-route
  preconditions: create a **security group**, add the app ID as a member, enable **Service principals
  can access admin APIs used for updates** under Admin API settings, scope it to that group. That
  setting "applies to Fabric admin APIs", and the page points at each API's identity table to confirm
  support.
- The same page carries the admin-consent rule verbatim: "Make sure the app you use doesn't have any
  admin-consent required permissions for Fabric set on it in the Azure portal"; to check, "There must
  be no admin-consent required permissions of type Application registered for the app." This is the
  Learn counterpart of the provider's warning, and it is a precondition on the app registration, not
  on the role.

Two distinct gates are therefore in play and neither is controlled by the provider: the identity must
**hold Fabric administrator**, and the tenant must **allow service principals on update admin APIs**
for the app's group. Learn's identity-support article still calls the public-API setting "Service
principals can use Fabric APIs", while the developer settings page uses "Service principals can call
Fabric public APIs" — a different setting from the admin-API one; do not conflate them.

As an **assignee**, no: `fabric_domain_role_assignments` cannot name a service principal. The REST
body does document `ServicePrincipal` and `ServicePrincipalProfile` among principal types, and the API
has an error code `UnsupportedPrincipalTypeForDomainAdminAssignment` ("Using unsupported principal
type for assigning or unassigning domain admin roles"), but the provider strips both service-principal
types from the accepted set:

```go
possiblePrincipalTypeValues := utils.RemoveSlicesByValues(
    fabadmin.PossiblePrincipalTypeValues(),
    []fabadmin.PrincipalType{fabadmin.PrincipalTypeServicePrincipal, fabadmin.PrincipalTypeServicePrincipalProfile},
)
```

Accepted types are `EntireTenant`, `Group`, `User`. A group can contain an SP, which is the only way
an SP becomes a domain contributor or admin through Terraform.

### 4. One domain with two environments, or a subdomain each?

A workspace has exactly one domain: `Workspace.domainId` is a single UUID ("The ID of the domain the
workspace is assigned to"), not a list. Nothing in the provider schema or Learn restricts *which*
workspaces share a
domain, so the nonprod and prod workspaces of one business area can sit in the same domain. The
environment split is carried by workspace roles, capacity and state, not by the domain.

Assignment also overrides: "Preexisting domain assignments will be overridden unless bulk reassignment
is blocked by domain management tenant settings". The tenant setting "Allow tenant and domain admins
to override workspace assignments (preview)" is "enabled by default" and "The domain REST APIs respect
this setting". With it on, an apply that assigns a workspace to domain A moves it out of domain B
instead of failing — a silent ownership change if two roots disagree.

A subdomain buys less than it looks:

- **No admins of its own.** "Subdomains don't have their own domain admins. A subdomain's domain
  admins are the domain admins of its parent domain." The provider enforces this on create:
  `Admins not supported for subdomains … Only adding Contributors to subdomains is currently
  allowed.` (added in v1.8.0).
- **No delegated settings.** "Subdomains currently have general settings only." Domain-level default
  sensitivity label and certification overrides therefore cannot differ between a domain and its
  subdomain.
- **No separate visibility.** "Domain assignment doesn't affect item visibility or accessibility for
  tenant users."

So a subdomain is a catalogue/hierarchy device. If nonprod and prod genuinely need different delegated
governance settings, only two top-level domains give that — a subdomain split does not. If they do not,
one domain holding both workspaces is simpler and is what the provider models most directly.

### 5. Import

Only `fabric_domain` can be imported, by domain GUID. `fabric_domain_role_assignments` has no `id`
attribute and no `ImportState` implementation, and `fabric_domain_workspace_assignments` likewise —
both reconcile against configuration rather than an identity. Practically: a domain created in the
portal can be adopted; role assignments and workspace assignments created in the portal must be
written into HCL and applied. For workspace assignment that is idempotent, because assigning an
already-assigned workspace is a no-op.

### 6. What destroy does

| Destroying | Effect |
| --- | --- |
| `fabric_domain_workspace_assignments` | Calls `unassignWorkspaces` with every ID in state, then removes the resource from state. The **workspaces survive and become unassigned**; nothing is deleted. Under `terraform destroy` the dependency edge on `fabric_workspace` means assignments go first, so the workspaces are free by the time their own destroy runs. |
| `fabric_domain_role_assignments` | Calls `roleAssignments/bulkUnassign` for the role and every principal in state, then removes the resource. The principals lose the domain role; they are not deleted. |
| `fabric_domain` | A single `DELETE /v1/admin/domains/{domainId}`. The provider does **not** unassign workspaces (or delete subdomains) first. |

Two operational consequences follow from the resource shapes rather than from the API:

- **Role assignments have no drift detection in Terraform.** `Read` is a no-op — the source comment is
  "DO NOTHING / This resource does not have get/list API" — so a role granted or revoked in the portal
  is invisible to `terraform plan`. The API does now expose `GET
  /v1/admin/domains/{domainId}/roleAssignments`, so this is a provider gap rather than an API one. And
  because `role` and `principals` are ForceNew, changing one principal replaces the resource:
  unassign everyone in state, then re-assign. Keep the admin list short and expect a gap.
- **Workspace assignments do drift-detect, within the configured set.** `Read` lists the domain's
  workspaces and intersects them with the IDs in configuration, so removing an assignment in the
  portal shows up as drift and the next apply re-adds it. Workspaces assigned out-of-band to the same
  domain are ignored, and survive a destroy of the resource.

`fabric_domain`'s create cannot set `default_label_id` — the API's create body has no such field — so
the provider saves state and then issues a second `PATCH`. If that patch fails, the domain exists,
state already records it, and the next apply reports drift and retries (source comment: "State
already saved — resource exists, Terraform knows about it"). Clearing the label sends the all-zero
GUID.

### 7. Wiring notes

- `parent_domain_id` is ForceNew, so re-parenting a domain destroys and recreates it. Build the
  top-level domains first and the subdomains as separate resources in the same apply.
- Preview is provider-wide: enabling `preview` for `fabric_domain_workspace_assignments` enables every
  other preview resource in that root ([provider surface §2](terraform-provider-surface.md)).
- Use **one** `fabric_domain_workspace_assignments` per domain. A 2025 bug (#174, fixed in
  v0.1.0-beta.8) produced "Provider produced inconsistent result after apply" when the same domain was
  managed by several instances, because the resource enforced assignment from configuration only; the
  current `Read` filters to the configured IDs, but one resource per domain has no reason to be split.
- Rate limits on the domain admin APIs are 25 requests per minute per principal (10/min on
  `assignWorkspaces`); a large workspace count needs batching, not a tight loop.

## What this settles

- **Surface:** three resources (`fabric_domain`, `fabric_domain_role_assignments`,
  `fabric_domain_workspace_assignments`), three data sources, no role-assignment data source. Only
  workspace assignment is preview; the other two went GA in v1.8.0.
- **Permission:** through Terraform, all three require a **Fabric administrator**. Fabric's own
  narrower routes — Core `assignToDomain` (workspace admin + domain contributor/admin) and Core
  `GET /v1/domains` (`Domain.Read.All`) — are not reachable from the provider, so "requires Fabric
  administrator" is a Terraform constraint, not a Fabric one.
- **Service principal:** admissible as the caller on every domain API, admin and Core, subject to the
  admin-API setting and allowed group plus no admin-consent Fabric permissions on the app. Never
  admissible as the *assignee* of a domain role through Terraform.
- **Shape:** one domain can hold the nonprod and prod workspaces. A subdomain gives a hierarchy
  branch, no own admins, no delegated settings, and contributors only — it is not an environment
  boundary.
- **Lifecycle:** import works for the domain only. Destroying the assignment resource unassigns
  workspaces; destroying the domain sends a bare DELETE whose effect on assignments is undocumented.

## What this does not establish

- **Whether a service principal can hold the Fabric administrator role** in this tenant, directly or
  through a role-assignable group. Learn's admin-roles page describes assigning "users" to the role in
  the Microsoft 365 admin portal; whether an SP is eligible is an Entra/tenant fact, and it is the
  pivot of issue #44. If it cannot, the Terraform route is closed and the Core `assignToDomain` route
  is the only automation path left.
- **Whether the tenant's "Service principals can access admin APIs used for updates" setting is on**,
  which group it is scoped to, and whether the automation SP is in it.
- **What Fabric does to workspace assignments when a domain is deleted.** Neither the Delete Domain
  reference nor the Domains article states a cascade; the provider issues a bare DELETE with no prior
  unassignment, so a destroy against a non-empty domain may fail or may orphan assignments — untested
  here.
- **Whether the admin `assignWorkspaces` endpoint would also accept a domain admin or contributor** in
  practice. Its reference says Fabric administrator; the Core endpoint documents the lower bar. Only a
  tenant test shows whether the admin route is enforced strictly.
- **Whether `ServicePrincipal` is accepted for the `Contributors` role at the API level.** The request
  schema lists it; the provider forbids it and the API exposes an unsupported-principal error for admin
  roles. Not separable from a tenant.
- **Whether the override tenant setting is enabled** in the target tenant, and therefore whether a
  cross-domain reassignment overrides or errors.
- **Whether subdomains have a depth or count limit**, and whether a parent domain with subdomains can
  be deleted without deleting them first.
- **Whether the 25/min and 10/min admin limits are adequate** for the workspace count the corporate
  session will assign, or whether the Core route's throttling is better.

## Sources

| Source | Used for | Dated |
| --- | --- | --- |
| [`docs/resources/domain.md` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/docs/resources/domain.md) | `fabric_domain` schema, Fabric-administrator warning, admin-consent warning, import syntax | checked 2026-11-26 |
| [`docs/resources/domain_role_assignments.md` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/docs/resources/domain_role_assignments.md) | roles `Admins`/`Contributors`, principal types, ForceNew markers, no import | checked 2026-11-26 |
| [`docs/resources/domain_workspace_assignments.md` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/docs/resources/domain_workspace_assignments.md) | preview warning, `domain_id`/`workspace_ids`, no import | checked 2026-11-26 |
| [`docs/data-sources/domain.md`, `domains.md`, `domain_workspace_assignments.md` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/data-sources) | the three data sources; absence of a role-assignment data source | checked 2026-11-26 |
| [`internal/services/domain/`, `domainra/`, `domainwa/` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/internal/services) | admin client use, import implementations, delete/unassign behaviour, read-is-a-no-op, principal-type filtering, subdomain admin error, default-label second PATCH, read filtering | read 2026-11-26 |
| [`internal/provider/provider.go` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/internal/provider/provider.go) | registration of 3 resources and 3 data sources | read 2026-11-26 |
| [`CHANGELOG.md` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/blob/v1.15.1/CHANGELOG.md) | v1.8.0 GA migration (#801), subdomain role support (#828), SP permission text (#742), #174 | checked 2026-11-26 |
| [Releases](https://github.com/microsoft/terraform-provider-fabric/releases) | v1.15.1 is the latest release (2026-11-11) | checked 2026-11-26 |
| [Domains](https://learn.microsoft.com/en-us/fabric/governance/domains) | domain/subdomain concepts, Fabric admin vs domain admin vs contributor, assignment and override, "subdomains currently have general settings only", no visibility effect | checked 2026-11-26 |
| [Understand Microsoft Fabric admin roles](https://learn.microsoft.com/en-us/fabric/admin/roles) | Fabric administrator vs domain admin; roles assigned to users in the Microsoft 365 admin portal | checked 2026-11-26 |
| [Enable service principal authentication for admin APIs](https://learn.microsoft.com/en-us/fabric/admin/enable-service-principal-admin-apis) | security-group route, "Service principals can access admin APIs used for updates", no admin-consent Fabric permissions | checked 2026-11-26 |
| [Identity support](https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support) | the older "Service principals can use Fabric APIs" name | checked 2026-11-26 |
| [Create Domain](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/create-domain), [Delete Domain](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/delete-domain), [List Domains (admin)](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/list-domains) | Fabric-administrator permission, SP support, request/response shape | checked 2026-11-26 |
| [Assign](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/assign-domain-workspaces-by-ids) / [Unassign](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/unassign-domain-workspaces-by-ids) Domain Workspaces By Ids, [List Domain Workspaces](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/list-domain-workspaces) | permission, override behaviour, 10/min rate limit | checked 2026-11-26 |
| [Role Assignments Bulk Assign](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/role-assignments-bulk-assign), [List Role Assignments](https://learn.microsoft.com/en-us/rest/api/fabric/admin/domains/list-role-assignments) | permission, principal types including ServicePrincipal, unsupported-principal error, the read API the provider does not use | checked 2026-11-26 |
| [Workspaces – Assign To Domain](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/assign-to-domain), [Unassign From Domain](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/unassign-from-domain) | the lower-privilege Core route: workspace admin + domain contributor/admin; unassign needs workspace admin only | checked 2026-11-26 |
| [Domains – List Domains (Core)](https://learn.microsoft.com/en-us/rest/api/fabric/core/domains/list-domains) | `Domain.Read.All`, no Fabric-administrator requirement for reading domains | checked 2026-11-26 |
| [Domain management tenant settings](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-domain-management-settings) | "Allow tenant and domain admins to override workspace assignments (preview)", enabled by default, respected by the REST APIs | checked 2026-11-26 |
| [Update Workspace](https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/update-workspace) | `Workspace.domainId` is read-only; `UpdateWorkspaceRequest` has no domain field | checked 2026-11-26 |

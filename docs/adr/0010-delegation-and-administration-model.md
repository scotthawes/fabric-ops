# 0010 — Existence is centralised, operation is delegated

- **Status:** accepted
- **Date:** 2026-11-15
- **Amended:** 2026-11-26 — the pipeline creates the groups; ownership and membership stay human
- **Deciders:** Scott
- **Evidence:** [`governance-access-and-workspace-roles.md`](../research/governance-access-and-workspace-roles.md),
  [`entra-and-ado-operations.md`](../research/entra-and-ado-operations.md),
  [`workspace-and-item-lifecycle.md`](../research/workspace-and-item-lifecycle.md),
  [`tenant-settings-catalogue.md`](../research/tenant-settings-catalogue.md),
  [`what-goes-where.md`](../guides/what-goes-where.md)
- **Amends:** [ADR 0006](0006-access-through-entra-groups.md) — its "review is the control" consequence is
  replaceable by an assertion (§4), and its group-per-workspace rule gains an owner (§3)
- **Drawn up as:** [`maps/platform-administration-architecture.html`](../maps/platform-administration-architecture.html)
  — the same design as one page, for someone who will not read an ADR

## Context

ADR 0006 settled *who holds a workspace role*: one Entra security group per workspace, `Admin` to named
humans. Spec 0002 settled *what is done regularly*: four steady-state operations and four quarterly reviews.
Neither answers the question a platform team hits in its second month, which is not "who has access" but:

- **Who is allowed to create a workspace?** The pack never names the **Create workspaces** tenant setting,
  although the entire group-per-workspace convention depends on its answer. Today the only path is a pull
  request against `terraform/workspaces`, which makes one person the queue for every new project.
- **Who changes group membership?** ADR 0006 says "membership is managed in Entra" and stops. If the answer
  is "the platform team", onboarding is a ticket; if it is "nobody", offboarding depends on a leaver process
  that never learns which groups exist.
- **Who owns the platform roles?** The pack names four owners in spec 0002 (capacity, platform engineer,
  security reviewer, tenant admin) but designs no role catalogue, so "who is a Fabric administrator" is not
  a query and the capacity owner has no deputy.
- **What happens between reviews?** Break-glass access is "recorded" with no format and no expiry, so the
  recording decays and the quarterly recertification is where it is discovered rather than prevented.

The governing constraint is that only some of this can be delegated. Domains — Fabric's native delegation
primitive — **do not affect item visibility or accessibility**; they delegate catalogue scoping and settings,
not access. So delegated administration has to be assembled from things that actually carry authority: group
ownership in Entra, the workspace `Admin` role, and the tenant settings that gate creation.

## Decision

**1. One path creates a workspace, and it is the Terraform root.** Every workspace arrives as a generated
variables entry plus a checklist review, not as a design review and not as a portal click. `Create workspaces`
is scoped to a platform group, never `Everyone`; **Users can create Fabric items** and the two
service-principal switches stay as spec 0002 and recommendation 01 describe them. Self-service workspace
creation is refused as a design, because a self-created workspace has no group, no role assignment and no
capacity discipline, and no later report can retro-fit them.

**2. The group name is the contract between Entra and Terraform.** The workspaces root resolves each group by
display name (`fabric-sales-forecast-dev-contributors`, per `reference/naming.md` rule 5), so a missing group
fails `terraform plan` instead of pasting an object ID that survives one rename. Group creation stays manual:
adding the AzureAD provider to the platform principal buys `Directory.ReadWrite.All` to save a click, and
that trade is refused.
**Amended 2026-11-26:** group creation moves into the workspaces root, because the role assignment needs a
resource edge and the cost is narrower than `Directory.ReadWrite.All`; ownership and membership stay human.
See the amendment below.

**3. Membership is delegated to a named group owner, not to the platform team.** Each per-workspace group is
owned by the human who holds `Admin` on that workspace. That person adds and removes members; the platform
team manages the *assignment*, never the *people*. This is the whole delegation mechanism — it needs no new
product feature — and it works only because the group carries `Contributor` or `Viewer` and never `Admin`.

**4. No group carries `Admin`, and that is asserted rather than reviewed.** `GET
/v1/admin/workspaces/{workspaceId}/users` returns both `workspaceRole` and a principal `type` of `Group`, so
"an `Admin` assignment whose principal is a group" is a query. ADR 0006 conceded it was structurally
indistinguishable from a person and left review as the control; the admin API already in the access report
makes it a failing check instead. Treat this as the ADR's amendment to 0006, with the same caveat the research
carries: the endpoint is Preview and the assertion is documentation-derived, unverified in a tenant.

**5. Two tiers of group, and the platform tier never holds a workspace role.**

| Tier | Naming | Holds | Cannot hold |
| --- | --- | --- | --- |
| Workspace | `<workspace>-<role>`, closed suffix list `contributors` / `viewers` | `Contributor` / `Viewer` on the named workspace | `Admin` (assertion 4) |
| Platform | `fabric-role-<role>` | tenant or platform capability: admin API allow-list, security review, platform engineering | any workspace role |

Workspace `Admin` is granted to a named human with a **named deputy**; capacity admin is the same, because
the documentation describes it for users and a group cannot hold it. Two single-person points of failure are
designed in and must be designed against.

**6. Break-glass is an expiring entry in a file.** Direct per-user role assignments and item sharing are
permitted only where an entry in the repo's exception register matches — principal, workspace, role or item,
reason, approver, **expiry date**. Expiry is mandatory and the weekly access report fails on any unmatched or
expired entry. Item sharing additionally carries a named owner and a review date, because it is the one grant
path a Viewer can create and the pipeline never sees.

**7. Steady state gains three assertions and one freshness check.** The four operations in spec 0002 keep
their owners and cadences; what changes is that each produces a verdict that can be red:

| Check | Fails when |
| --- | --- |
| Group-Admin assertion | any `Admin` role assignment's principal is a group |
| Exception assertion | a direct assignment or share has no unexpired register entry |
| Settings drift | a named setting differs from the committed expectation (the `Create workspaces` switch is first) |
| Freshness | any of the above has not produced a report in 36 hours |

Plus the lifecycle operation the pack was missing: orphaned workspaces (the admin API reports them `Active`),
workspaces assigned to no capacity, and retired workspaces past a reaping decision. Prevention is preferred —
requiring an `Admin` at creation means the orphan class never appears — and reaping is a decision with an
owner, not a scheduled deletion, because a workspace restore loses its workspace identity and may not return
its role list.

## Consequences

- **Cheap now, expensive later.** The role catalogue, the group naming and the exception register are all
  cheap to fix this month and cost a rename, a URL change and a re-grant afterwards.
- **Two systems, one order.** Creating a workspace is group first, then pull request. That ordering
  dependency is deliberate and it is a human step, so it is the most likely place for the model to be
  abandoned under pressure.
- **3N groups now have 3N owners.** Ownership is how membership scales without the platform team, and it is
  also a directory of people who must be maintained: an owner who leaves is a group nobody can edit, which is
  the orphan workspace problem one level down.
- **The exception register rots unless the report enforces it.** A file that is not diffed against reality is
  a comment. The register is only worth having because assertion 7 fails on it.
- **The deputy roster is a maintenance tax with no automation behind it.** Nothing detects a workspace whose
  Admin and deputy have both left except the orphan check, and nothing detects a capacity owner who has not
  been replaced.
- **Delegation is still bounded by licensing.** `Contributor` on any SKU requires Pro or PPU, so adding a
  person to a `-contributors` group is a purchase, not a permission change. Group ownership therefore sits
  next to a cost decision, and the quarterly licence reconciliation has to read Entra membership to be
  meaningful.
- **Not established:** whether the Preview access-details endpoint returns group principals in every tenant
  configuration, and whether a group of only service principals satisfies both admin-API allow-lists — both
  are tracked tenant questions in [`research/backlog.md`](../research/backlog.md). The work tenant's
  **Create workspaces** setting is a [run-book](../runbook/01-work-tenant-checklist.md) item, because it is
  observed by logging in, not by reading.
- **Deliberately not decided here:** staffing, whether the security review is internal or delegated, and who
  approves an exception. Those are organisational facts the pack cannot supply — spec 0002 already says so,
  and inventing them would make this look more finished than it is.

## Amendment 2026-11-26 — the pipeline creates the groups; people still own them

The §2 refusal rested on a price that turned out to be wrong, and on a benefit that turned out to be
the smaller half.

- **The price is `Group.Create`, not `Directory.ReadWrite.All`.** The `azuread_group` resource
  documents its least application permission as `Group.Create`, plus `User.Read.All` when a user is
  named as owner (or `Directory.Read.All` when either owner type is used). Directory-wide write is
  not required.
- **The benefit is the dependency edge, not the saved click.** With the group in the same root as
  the workspace, the role assignment references `azuread_group.x.object_id`, so plan orders the
  creation and a workspace rebuild cannot leave a name lookup pointing at a group that no longer
  matches.

**Decision.** Groups are created by `azuread_group` in the **workspaces root**, one per role:

- `display_name = "<workspace>-<key>"` and `security_enabled = true` — the naming rule is unchanged.
- `prevent_duplicate_names = true`, because Entra display names are **not unique**; §2's
  name-as-contract only holds if a duplicate cannot exist.
- `lifecycle { prevent_destroy = true }`, so a workspace destroy cannot churn the group's object ID
  under an access review, a break-glass entry or an Azure RBAC assignment.
- `owners` names the workspace's Admin human. An empty list falls back to the applying principal,
  which is the provider's documented default — permitted, but it leaves §3's delegation unassigned.
- §3 (membership is delegated to the owner) and §4 (no group carries `Admin`; the assertion stays)
  are unchanged. Creation is automation's; who is in the group, and who owns it, are not.

**Consequences.**

- A directory change now appears in a Terraform plan and is reviewed with the workspace that needs it.
- The platform principal holds directory write. It is `sp-fabric-admin`, never the deploy principal,
  so ADR 0002's split still bounds what a content pipeline can do.
- Group deletion is a 30-day soft delete (cloud security groups are in preview), and a permanent
  purge leaves dangling role assignments — the tracked tenant question in the backlog. `prevent_destroy`
  is the guard; the restore window is not.
- Still unverified: whether an SP-created group with a human co-owner is editable by that human in
  every tenant configuration. That is a tenant fact, not a design choice.

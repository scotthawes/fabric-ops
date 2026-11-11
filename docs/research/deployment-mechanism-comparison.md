# How should a repo deploy and promote Fabric content, given it must also administer workspace users and roles?

- **Status:** answered
- **Checked:** 2026-11-11
- **Blocks:** the ADR that picks the deployment mechanism (`README.md` "Not yet decided")

## Short answer

No single mechanism covers both halves of the job. The item-definition APIs (directly, or
through `fabric-cicd`) are the only ones that deploy items from a repo into an arbitrary
environment *and* work headlessly as a service principal; Terraform is the only one that
manages workspaces, role assignments, domains and tenant settings declaratively. Git
integration and deployment pipelines are workspace-bound and neither carries role assignments.
Adopt repo-as-source-of-truth: definitions in Fabric's source-control format deployed by
`fabric-cicd`/REST per environment, with control-plane resources in Terraform (or the same
REST calls).

## Detail

| | Git integration | Deployment pipelines | Item-def. REST / fabric-cicd | Terraform provider |
| --- | --- | --- | --- | --- |
| Create workspace | ❌ must already exist | ⚠️ via deploy to empty stage | ✅ `POST /v1/workspaces` | ✅ `fabric_workspace` |
| Create/update items | ✅ supported items only | ⚠️ copied between stages | ✅ per-item definition APIs | ✅ per-item resources |
| Workspace role assignments | ❌ | ❌ never copied | ✅ `/roleAssignments` | ✅ `fabric_workspace_role_assignment` |
| Capacity | ❌ | ⚠️ stage workspace needs one | ⚠️ `assignToCapacity` only | ⚠️ data source only |
| Domain | ❌ | ❌ | ⚠️ `assignToDomain` (admin) | ✅ `fabric_domain` (admin) |
| Tenant settings | ❌ | ❌ | ❌ | ✅ `fabric_tenant_setting` (admin) |
| Service principal | ⚠️ `ConfiguredConnection` only | ✅ | ✅ | ✅ |

### 1. Fabric Git integration

Workspace-bound, one branch at a time, providers Azure DevOps / GitHub / GitHub Enterprise
(cloud only). Workspace structure, including folders (10 levels), is mirrored into the repo
([overview][git-intro], [process][git-process]).

- **Creates/updates:** items on the *supported items* list only — not workspaces, role
  assignments, capacity or domains. Items off the list can sit in a connected workspace but are
  "ignored… not saved or synced" and cannot be committed or updated; report and semantic model
  are marked *(preview)*, as are ML experiments/models and several RTI items
  ([overview][git-intro]).
- **Identity:** connect/sync/disconnect/switch-branch are workspace **Admin**; update/commit
  need workspace **Contributor** *with WRITE on all items*. Tenant side: **"Users can
  synchronize workspace items with their Git repositories"**, plus (GitHub, off by default)
  **"Users can sync workspace items with GitHub repositories"**; cross-geo Azure DevOps needs
  **"Users can export items to Git repositories in other geographical locations"**, and
  labelled items **"Users can export workspace items with applied sensitivity labels to Git
  repositories"** ([admin settings][git-admin]). `Connect` accepts a service principal "only
  when myGitCredentials.source is ConfiguredConnection" and is "blocked for GitHub provider and
  for Service Principal" with Automatic credentials ([Connect][git-connect]). The connection is
  per user, not per workspace ([process][git-process]).
- **Cannot:** create a workspace; grant roles; set capacity, domain or tenant settings; support
  submodules, sovereign clouds, MyWorkspace, template-app workspaces or B2B; export labels;
  exceed 1,000 items/workspace, 25 MB/file or 50 MB per GitHub commit.
- **Round-trip:** yes, but serialised and lossy at the edges. Portal edits appear as
  *uncommitted changes* and are committed out; `Update from Git` "always updates the entire
  branch" and overwrites the workspace, and "you can only sync in one direction at a time". A
  commit deletes files inside an item folder that are not part of the definition. Labels, data
  and item IDs are not restored by Git ([process][git-process]).

### 2. Fabric deployment pipelines

2–10 stages (default Development/Test/Production) whose stages are workspaces; deployment copies
content between adjacent stages, with *pairing* deciding overwrite vs duplicate. The native UI
is in **preview**, and Power BI item types are mostly *(preview)* ([overview][dp-intro]).

- **Creates/updates:** items stage-to-stage. A deploy to a stage with no workspace "creates a
  new workspace" on the capacity, so it can provision stage workspaces ([process][dp-process]).
  It does **not** manage role assignments: "Permissions - For a workspace or a specific item"
  and "Workspace settings - Each stage has its own workspace" are listed as *not copied*.
- **Identity:** pipeline permission is a single role, **Admin** ("Pipelines only have one
  permission, *Admin*"); deploying also needs **Contributor/Member/Admin in both source and
  target workspaces**; assigning a workspace to a stage needs pipeline admin **and** workspace
  **Admin** ([assign][dp-assign]). Service principals are supported (`POST
  /v1/deploymentPipelines`), gated by **"Service principals can create workspaces, connections,
  and deployment pipelines"** ([create][dp-create]).
- **Cannot:** copy permissions, workspace settings, app content, data, refresh schedules,
  credentials or semantic-model role assignments; deploy Dataflows via the Fabric API; exceed
  300 items per deployment; use Microsoft 365 groups as pipeline admins. Stage count and names
  are fixed at creation ([process][dp-process], [automation][dp-auto]).
- **Round-trip:** none with the repo — the pipeline never reads Git. It is workspace→workspace,
  so portal edits in a target stage are invisible to the source and are overwritten by the next
  deploy (item ID, URL and permissions preserved).

### 3. Item-definition REST APIs, and `fabric-cicd` over them

`Get Item Definition`, `Update Item Definition` and `Create Item with Definition` exchange the
part-based definition (`.platform` plus item parts) that a repo holds ([definition][itemdef]).
`fabric-cicd` is Microsoft's wrapper: it reads definition files from a directory and "passes the
content as a payload to the Fabric REST APIs".

- **Creates/updates:** items, and via the surrounding Core API workspaces (`POST /v1/workspaces`),
  workspace role assignments (`POST /v1/workspaces/{workspaceId}/roleAssignments`, roles
  `Admin`/`Member`/`Contributor`/`Viewer`), capacity assignment and domain assignment
  ([workspaces API][ws-api]). Workspace creation needs create-workspace permission *and*
  contributor/Admin on the capacity, plus, for a service principal, **"Service principals can
  create workspaces, connections, and deployment pipelines"** ([create workspace][ws-create]).
- **Identity:** item create/update needs workspace **Contributor**; `getDefinition` needs
  read-write on the item; adding a role assignment needs **Member or higher**, so a Contributor
  cannot administer users. Service principals are supported "when the item type in the call is
  supported" ([create item][item-create]). Tenant side: **"Service principals can call Fabric
  public APIs"** ([index][ts-index]).
- **`fabric-cicd` specifically:** full deployment every run, "without considering commit diffs";
  "only supports items that have Source Control, and Public Create/Update APIs";
  `FabricWorkspace(workspace_id=...)` assumes the workspace exists and unpublishing orphans is a
  separate call. Parameterisation is `parameter.yml` `find_replace` plus `$items.*` /
  `$workspaces.*`; `token_credential` is now required ([repo docs][cicd-docs]).
- **Cannot:** administer workspace users/roles, create workspaces, or set capacity/tenant
  settings; deploy item types lacking a public definition API.
- **Round-trip:** one-way by design. `getDefinition` could export, but nothing in `fabric-cicd`
  does; because it deploys everything every run, a portal edit is silently overwritten rather
  than surfaced as drift.

### 4. Terraform provider for Microsoft Fabric

Verified to exist and be actively released: `microsoft/terraform-provider-fabric`, **v1.15.1
published 2026-11-11**, Terraform >= 1.8 ([repo][tf-repo]).

- **Creates/updates:** `fabric_workspace`, `fabric_workspace_role_assignment` (roles
  `Admin`/`Member`/`Contributor`/`Viewer`; principals `User`/`Group`/`ServicePrincipal`/
  `ServicePrincipalProfile`), `fabric_workspace_git`, `fabric_domain`,
  `fabric_domain_role_assignments`, `fabric_domain_workspace_assignments`,
  `fabric_deployment_pipeline`, `fabric_tenant_setting`, and item resources for roughly 40
  item types ([resources][tf-res]).
- **Identity:** service principals supported per resource; `fabric_domain` states "The caller
  must be a Fabric administrator"; tenant settings are tenant-admin operations — only the
  "Fabric (tenant) admin controls a Git integration tenant setting" ([admin][git-admin]).
- **Cannot:** create a capacity (`fabric_capacity` is a *data source* only); perform `Commit To
  Git`/`Update From Git` (`fabric_workspace_git` manages the *connection* and
  `initialization_strategy`). Item definitions are HCL `definition` blocks pointing at source
  files with token substitution, not the Git-sync folder layout as authored. The repo states the
  provider "is **NOT** covered by the Microsoft Fabric or Microsoft support policies"
  ([repo][tf-repo]); I could not establish any Learn page declaring it GA or preview.
- **Round-trip:** state-based, not repo-based. Portal edits surface as drift on refresh/plan and
  are overwritten by `apply`; nothing writes platform state back into the repo layout.

### Cross-cutting: service principal tenant settings

The settings index (2026-11-05) lists **"Service principals can create workspaces, connections,
and deployment pipelines"** and **"Service principals can call Fabric public APIs"**
([index][ts-index]); admin-API settings add **"Service principals can access read-only admin
APIs"** and **"Service principals can access admin APIs used for updates"**, both requiring an
allowed security group ([admin API][admin-api]). ⚠️ The older identity-support article
(2026-04-08) still says **"Service principals can use Fabric APIs"** ([identity][identity]) —
treat that as a stale name, not a second setting, and check the tenant's own portal first.

## What this settles

- **Recommendation:** repo-as-source-of-truth. Hold items in Fabric's source-control definition
  format (the only layout Git integration, `fabric-cicd` and the item-definition APIs share);
  deploy with `fabric-cicd`/item-definition REST per environment under one service principal;
  own workspaces, role assignments, capacity assignment, domains and tenant settings in
  Terraform (or equivalent Core API calls). Bind Git integration only to non-production/feature
  workspaces, per `fabric-cicd`'s documented flow ("`Deployed` branches are not connected to
  workspaces via Git Sync").
- Deployment pipelines are not the deployment mechanism for a Git-first repo: they never read
  the repo and cannot carry role assignments.
- The "administer workspace users and roles" half must be REST or Terraform.
- Two identities in practice: a **Contributor**-level deployment principal and a
  **Member/Admin**-level administration principal, or one Member/Admin principal trusted with both.

## What this does not establish

- Per-item-type parity: **answered** in
  [`item-type-deployment-coverage.md`](item-type-deployment-coverage.md) — 23 item types are
  deployable, 7 are manual-only. What remains open there is whether the API support table is
  complete.
- Whether Terraform item resources can import and round-trip every item definition, or what
  happens to an item created outside Terraform.
- Whether Fabric admin REST APIs can set tenant settings directly; only the Terraform resource
  was confirmed, and no Learn page establishes the provider's own GA/preview status.
- Behaviour of preview items in any mechanism (the lists change monthly), and cost, licensing or
  throttling headroom for a real pipeline.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [Git integration overview][git-intro] / [process][git-process] | supported items, scope, roles, sync direction, limits | 2026-09-01 / upd. 2026-10-26 |
| [Git integration admin settings][git-admin] | exact Git tenant setting names | upd. 2026-10-07 |
| [Git - Connect][git-connect] / [Core Git API][git-api] | SP only with `ConfiguredConnection`; commit/update endpoints exist | upd. 2026-11-10 / 2026-10-05 |
| [Deployment pipelines overview][dp-intro] | stage model, preview UI, supported items | upd. 2026-11-06 |
| [Deployment pipelines process][dp-process] | what is not copied, permissions table, limits | upd. 2026-11-02 |
| [Pipelines automation][dp-auto] + [API group][dp-api] | API capabilities, dataflow gap | upd. 2026-09-29 / 2025-07-02 |
| [Assign Workspace To Stage][dp-assign] / [Create Pipeline][dp-create] | admin+admin, SP gating setting | upd. 2026-11-10 |
| [Workspaces API][ws-api] / [Create Workspace][ws-create] | create, roles, capacity/domain, SP perms | upd. 2026-07-14 / 2026-09-24 |
| [Add Workspace Role Assignment][ws-role] | Member-or-higher, role/principal enums | upd. 2026-11-10 |
| [Item definition overview][itemdef] / [Create Item][item-create] / [Get Definition][item-get] | definition APIs, Contributor, SP caveat | upd. 2026-11-11 / 2026-11-10 |
| [Tenant settings index][ts-index] / [Developer settings][dev-settings] / [admin API][admin-api] | exact current setting names, security-group gate | upd. 2026-11-05 / 2026-09-29 |
| [Identity support][identity] | stale "use Fabric APIs" wording ⚠️ | upd. 2026-04-08 |
| [terraform-provider-fabric][tf-repo] / [resources][tf-res] / [data sources][tf-ds] | v1.15.1, resource surface, support caveat | release 2026-11-11 |
| [fabric-cicd docs][cicd-docs] | philosophy, item constraint, auth | read 2026-11-11 |

[git-intro]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration
[git-process]: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-integration-process
[git-admin]: https://learn.microsoft.com/en-us/fabric/admin/git-integration-admin-settings
[git-connect]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git/connect
[git-api]: https://learn.microsoft.com/en-us/rest/api/fabric/core/git
[dp-intro]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines
[dp-process]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/understand-the-deployment-process
[dp-auto]: https://learn.microsoft.com/en-us/fabric/cicd/deployment-pipelines/pipeline-automation-fabric
[dp-api]: https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines
[dp-assign]: https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines/assign-workspace-to-stage
[dp-create]: https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines/create-deployment-pipeline
[ws-api]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces
[ws-create]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/create-workspace
[ws-role]: https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/add-workspace-role-assignment
[itemdef]: https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/item-definition-overview
[item-create]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/create-item
[item-get]: https://learn.microsoft.com/en-us/rest/api/fabric/core/items/get-item-definition
[ts-index]: https://learn.microsoft.com/en-us/fabric/admin/tenant-settings-index
[dev-settings]: https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-developer
[admin-api]: https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-admin-api-settings
[identity]: https://learn.microsoft.com/en-us/rest/api/fabric/articles/identity-support
[tf-repo]: https://github.com/microsoft/terraform-provider-fabric
[tf-res]: https://github.com/microsoft/terraform-provider-fabric/tree/main/docs/resources
[tf-ds]: https://github.com/microsoft/terraform-provider-fabric/tree/main/docs/data-sources
[cicd-docs]: https://github.com/microsoft/fabric-cicd/tree/main/docs

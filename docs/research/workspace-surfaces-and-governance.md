# Which workspace-level and governance surfaces can be automated, and which are portal-only?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the nine "not assessed" rows of [`automation-coverage.md`](../guides/automation-coverage.md) — apps, tags, folders, network controls, CMK, external shares, endorsement, domains; the permission run-book in the work repo.

## Short answer

Six of the eight surface families are automatable, two are not. **Portal-only: workspace apps and
endorsement** — neither has a write operation anywhere in `fabric-rest-api-specs` (0 occurrences of
"endorse" across all 61 specs; no `/apps` route at all), and the Power BI REST `Apps` group is
read-only. **Automatable: org apps, tags and folders, all six network controls, CMK encryption,
external data shares, domains** — but each carries a different blocker: Fabric administrator for
domains and tenant-scope tags, a preview flag for folders and CMK-in-Terraform, and a second tenant
for external-share acceptance. The dividing line is whether the feature is an **object** with a
create/update operation or a **view published over** other objects.

## Detail

### 1. Workspace apps — portal-only; org apps — automatable

Two different things share the word "app", and only one is addressable.

- **Workspace app** (the thing formerly called a Power BI app). `fabric-rest-api-specs` @ `3f8600f`
  has **no app route**: the only app-shaped paths are `/workspaces/{workspaceId}/orgApps`. The
  Power BI REST reference (`rest/api/power-bi/toc.json`, 313 entries, read 2026-11-12) lists only
  `Get App`, `Get Apps`, `Apps GetAppsAsAdmin`, `Apps GetAppUsersAsAdmin` — all reads. There is no
  publish, update, audience or unpublish operation on either surface. Verdict: **portal-only**, and
  the block is total: there is no object to call.
- **Org app** (`fabric_org_app`) is a Fabric *item*, and Learn says so explicitly: "Org apps are a
  newer evolution of workspace apps, implemented as Fabric items… they don't automatically rename,
  upgrade, migrate, or replace existing workspace apps" (org-app-items, ms.date 2026-09-24). It has
  the full item lifecycle — `POST`/`GET`/`PATCH`/`DELETE /v1/workspaces/{workspaceId}/orgApps[/{orgAppId}]`
  plus `getDefinition`/`updateDefinition` — and **audiences are a second item type**:
  `POST`…`/orgAppAudiences`, with the parent named by `parentAppId` inside the audience definition.
  All 14 operations are GA (no `?beta=true`, no Preview note) and all declare "Service principal and
  Managed identities: Yes". `fabric_org_app` and `fabric_org_app_audience` are both non-preview.
  Publishing = create, updating = `PATCH`/`updateDefinition`, unpublishing = `DELETE`. Verdict:
  **automatable**.

### 2. Tags — automatable (creation is admin-gated); folders — partial

**Tags.** `fabric_tag` (`display_name` ≤ 40 chars, `scope` ForceNew, `type` ∈ `Domain`|`Tenant`) is
non-preview and its doc carries no preview warning. Creation is `/v1/admin`:
`POST /v1/admin/tags/bulkCreateTags` — "The caller must have administrator rights such as Fabric
administrator", 25 requests/min, SP Yes; `PATCH`/`DELETE /v1/admin/tags/{tagId}` likewise. Reading is
not admin: `GET /v1/tags` needs only `Tag.Read.All`. Assignment is a separate verb and is *not* in
Terraform: `POST /v1/workspaces/{workspaceId}/items/{itemId}/applyTags` requires contributor or
higher, is capped at 25 requests/min, and is **not** marked preview. The workspace-level twin
`POST /v1/workspaces/{workspaceId}/applyTags` **is** preview and needs workspace admin. Learn
confirms the split: "Admins define tags… Workspace admins apply tags to workspaces… Users with Write
or Contributor permissions can apply up to 10 tags per item" (tags-overview, ms.date 2026-03-11).
Verdict: **automatable**, with tag *creation* behind Fabric administrator at tenant scope.

**Folders.** Full CRUD exists — `/v1/workspaces/{workspaceId}/folders`, `…/{folderId}`,
`POST …/{folderId}/move`, `POST /items/bulkMove`, `POST /items/{itemId}/move` — and item creation
takes a `folderId`. **Every one of those operations carries the preview note** ("This API is part of
a Preview release"), and `fabric_folder` is one of the provider's 15 preview resources. Learn adds
the product limits: 10 nesting levels, delete only when empty, Admin/Member/Contributor may create and
move (workspaces-folders, ms.date 2024-12-16). Note this is *folder* movement only — the coverage
matrix's "no cross-workspace move" still holds. Verdict: **partial** (preview on both surfaces).

### 3. Workspace network controls — automatable, and the order is the whole problem

| Terraform resource | Controls | REST operation (all `/{ws}` = `/workspaces/{workspaceId}`) | Preview |
| --- | --- | --- | --- |
| `fabric_workspace_network_communication_policy` | the two `default_action`s: `inbound` and `outbound` public access | `GET`/`PUT {ws}/networking/communicationPolicy | no |
| `fabric_workspace_inbound_azure_resource_rules` | allow-list of Azure resource IDs that may reach OneLake | `GET`/`PUT …/communicationPolicy/inbound/azureResources | **API yes** |
| `fabric_workspace_outbound_cloud_connection_rules` | which cloud connectors / workspaces may be reached | `GET`/`PUT …/communicationPolicy/outbound/connections | no |
| `fabric_workspace_outbound_gateway_rules` | which gateways may be reached | `GET`/`PUT …/communicationPolicy/outbound/gateways | no |
| `fabric_workspace_git_outbound_policy` | whether Git traffic may leave the region | `GET`/`PUT …/communicationPolicy/outbound/git | no |
| `fabric_workspace_firewall_rules` | inbound IP allow-list, up to 256 rules | `GET`/`PUT …/communicationPolicy/inbound/firewall | **API yes** |

**None of them can be set at workspace creation.** `CreateWorkspaceRequest` carries only
`displayName`, `description`, `capacityId`, `domainId`; all six resources take `workspace_id` as
ForceNew. So they are always applied to an existing workspace — but *when* still matters:

- **Outbound before content.** "If unsupported items already exist in a workspace, you can't enable
  outbound access protection on that workspace"; once enabled, unsupported items can't be created
  (workspace-outbound-access-protection-overview, ms.date 2026-11-10). Enable it between workspace
  create and item deploy.
- **Policy before rules.** `fabric_workspace_inbound_azure_resource_rules` and
  `fabric_workspace_firewall_rules` state they are "only enforced when `inbound.public_access_rules.default_action`
  … is set to `Deny`". The provider's own firewall example wires `depends_on` to the policy.
- **Git policy last.** `PUT …/outbound/git` "will fail" when the workspace has no outbound
  restriction — so it must follow a `Deny` outbound policy, and without it a `Deny` workspace cannot
  use Git integration.
- **One missing Terraform resource:** the inbound external-data-shares bypass policy
  (`GET`/`PUT …/communicationPolicy/inbound/externalDataShares`, preview) has no `fabric_*`
  equivalent, so that one is REST-only.

Two cautions worth quoting because both cause outages: `PUT` on the policy **overwrites all
settings** and "If `defaultAction` is omitted from the request body, it defaults to `Allow`, which may
unintentionally open inbound and outbound network access"; and the *portal* cannot configure data
connection rules when private links are on — "To set up outbound access protection with data
connection rules…", the API is the only route. Verdict: **automatable**, with inbound rules and
firewall still preview in the API while the provider exposes them ungated.

### 4. Encryption — automatable, gated on work outside Fabric

Three GA operations, no preview marker in the spec: `GET /workspaces/{workspaceId}/encryption`
(viewer+), `POST …/encryption/assign` and `POST …/encryption/reset` (workspace **admin**), all SP Yes,
100 calls/min. `keyIdentifier` "must be a versionless key URI". `fabric_workspace_encryption` is
**preview** in the provider; `workspace_id` is ForceNew but `encryption_details` is not, so key
rotation is in place.

Prerequisites, in the order Learn gives them: the **Apply customer-managed keys** tenant setting on;
a service principal for the **Fabric Platform CMK** app (app ID `61d6811f-7544-4e75-a1e6-1c59c0383311`);
Key Vault with soft delete **and** purge protection; the CMK app granted **Key Vault Crypto Service
Encryption User**. Learn states the API route outright: "You can enable CMK by using the Fabric portal
or APIs. Workspace administrators can use APIs Assign Workspace Encryption, Get Workspace Encryption,
and Reset Workspace Encryption" (workspace-customer-managed-keys, ms.date 2025-10-15).

Enabled on an existing workspace: **yes** — `assign` takes a bare workspace, and reset reverts to
Microsoft-managed keys. The constraint is content, not timing: "This feature can't be enabled for a
workspace that contains unsupported items", and afterwards only supported items may be created there.
So enable it early, or not at all. Verdict: **automatable**, blocked only by tenant setting + Key
Vault role — neither of which the deploy principal can grant itself.

### 5. External data shares — partial, because the customer has to accept

Provider side is fully wired: `POST`/`GET …/items/{itemId}/externalDataShares`,
`GET`/`DELETE …/{externalDataShareId}`, `POST …/{externalDataShareId}/revoke` ("This action cannot be
undone"). Requires item Read **and Reshare**, the **External data sharing** tenant switch, 10
requests/min. `fabric_external_data_share` is non-preview; `recipient` may be a `ServicePrincipal`
with a `tenant_id`, and the resource reads back `status` ∈ `Pending`/`Active`/`InvitationExpired`/`Revoked`
plus `invitation_url`.

Acceptance is the asymmetry. Learn: the creator "invites a user from another tenant to accept… Upon
accepting the share, the recipient chooses a lakehouse" (external-data-sharing-overview, ms.date
2025-06-10). There *is* an API — `GET /externalDataShares/invitations/{invitationId}` and
`POST …/accept`, scope `ExternalDataShare.Accept.All`, tenant switch **Users can accept external data
shares** — so no browser is needed, but the call must run under a principal **in the consuming
tenant**. The sharing tenant's pipeline cannot complete the share. Also: "Fabric admins need to turn
on external data sharing both in the sharer's tenant and in the external tenant." Verdict:
**partial** — create and revoke automatable, acceptance automatable only across a trust boundary.

### 6. Endorsement — portal-only, and plainly so

There is **no endorsement API**. Searching all 61 `swagger.json` files for "endorse" returns zero
hits; `CreateWorkspaceRequest`/item schemas carry no endorsement field (the only label-ish property is
`sensitivityLabelSettings`, which is a Purview label, not a badge). The Power BI REST toc has no
endorsement page either. Learn describes only portal actions — "Any user with write permissions on an
item can promote it", certification "only [by] users specified by a Fabric administrator" — gated by
the **Enable item certification** and **Enable master data endorsement** tenant settings
(endorsement-overview, last updated 2024-07-11). Verdict: **portal-only**. Do not promise an
"endorsed on deploy" step; the best available control is a post-deploy audit against the portal.

### 7. Domains — automatable, but only by a Fabric administrator

Everything is under `/v1/admin/domains` and everything says "The caller must be a Fabric
administrator": `POST`/`GET`/`PATCH`/`DELETE /domains[/{domainId}]`, `assignWorkspaces`,
`unassignWorkspaces`, `unassignAllWorkspaces`, `roleAssignments/bulkAssign` and `bulkUnassign`,
`syncToSubdomains`, `assignWorkspacesByCapacities`, `assignWorkspacesByPrincipals` — 10–25
requests/min, SP Yes. Core offers read-only `GET /v1/domains` and `/domains/{domainId}`.

Terraform: `fabric_domain` non-preview (note `parent_domain_id` is ForceNew);
`fabric_domain_role_assignments` non-preview but **every field is ForceNew** — changing one principal
recreates the whole `Admins`/`Contributors` set; `fabric_domain_workspace_assignments` is **preview**.
Blocker is a role, not a surface: Fabric administrator **and** "the Azure application must not have any
Fabric permissions that require admin consent configured in the Azure portal". Assignment precedence
has its own preview gate — overrides apply "only if the **Allow tenant and domain admins to override
workspace assignments** (preview) tenant setting is enabled" (domains, ms.date 2025-05-01). Verdict:
**automatable, gated** in a separate root, as the coverage matrix already assumes.

### 8. The pattern

What separates the two groups is not the workload, the licence, or how new the feature is — it is
whether the feature **has a body**.

- **Automatable** surfaces are objects with a create/update operation: an org app and its audience are
  items with public definitions; a network policy and an encryption setting are singletons with `PUT`;
  a tag and a domain are tenant-scoped records with `POST`. Each of those writes exists, each identity
  table says "Service principal … Yes", and each has a Terraform resource that manages the object
  rather than a view of it.
- **Portal-only** surfaces are **projections**: a workspace app is a curated set of *other* items plus
  an audience rule, and publishing is a verb over that set, so there is no object to address; an
  endorsement is a badge on an item that no item schema carries, so no `PATCH` can set it. Both are
  `GET`-only or absent.
- **Partial** surfaces are the ones where only half the lifecycle is object-shaped: tags exist but
  assignment is a second verb with no Terraform resource; external shares exist but acceptance lives
  in someone else's tenant; folders exist but every operation is preview.

The rule to apply to a feature that does not exist yet: **find the object, then the verb.** If
`fabric-rest-api-specs` has a `POST`/`PUT`/`PATCH` on the thing itself and its identity table says
"Service principal … Yes", it is automatable — then check only for a Terraform `preview` marker and
for a prerequisite in another admin plane (Fabric admin role, tenant setting, Key Vault, the other
tenant). If the surface is a `GET`, a view assembled from other objects, or a verb over a *set* of
items, it is portal-only, and no amount of scripting changes that.

## What this settles

| Surface | Verdict | Mechanism | Blocker |
| --- | :-: | --- | --- |
| Workspace app (publish, audience, unpublish) | **Portal-only** | none — no route in 61 specs; Power BI `Apps` is read-only | No object exists to call |
| Org app | **Automatable** | `fabric_org_app`; `POST/PATCH/DELETE …/orgApps` | None; item licence required |
| Org app audience | **Automatable** | `fabric_org_app_audience`; `…/orgAppAudiences` | `parentAppId` immutable; parent delete cascades |
| Tag creation (tenant) | Automatable, gated | `fabric_tag`; `POST /v1/admin/tags/bulkCreateTags` | Fabric administrator |
| Tag assignment | Automatable, no Terraform | `POST …/items/{itemId}/applyTags` | Contributor+; 10 tags/item; workspace-level variant is preview |
| Folder | **Partial** | `fabric_folder` (preview); `/folders` CRUD + `move` | Preview on both surfaces |
| Network communication policy | Automatable | `fabric_workspace_network_communication_policy` | `PUT` overwrites; omitted `defaultAction` ⇒ `Allow` |
| Inbound Azure resource rules | Automatable (API preview) | `fabric_workspace_inbound_azure_resource_rules` | Only enforced when inbound = `Deny` |
| Outbound cloud / gateway rules | Automatable | `fabric_workspace_outbound_*_rules` | Only meaningful when outbound = `Deny` |
| Git outbound policy | Automatable | `fabric_workspace_git_outbound_policy` | Fails unless outbound already `Deny` |
| Workspace firewall rules | Automatable (API preview) | `fabric_workspace_firewall_rules` | Only enforced when inbound = `Deny`; ≤256 rules |
| External-share inbound bypass | **Partial** | `PUT …/inbound/externalDataShares` (preview) | No Terraform resource |
| CMK encryption | Automatable, gated | `fabric_workspace_encryption` (preview); `…/encryption/assign` | Tenant setting, CMK app SP, Key Vault role |
| External data share (create/revoke) | Automatable | `fabric_external_data_share` | Item Reshare + tenant switch; 10/min |
| External data share (accept) | **Partial** | `POST /externalDataShares/invitations/{id}/accept` | Must run in the consuming tenant |
| Endorsement | **Portal-only** | none — 0 spec occurrences | Badge is not in any item schema |
| Domain / domain roles | Automatable, gated | `fabric_domain`, `fabric_domain_role_assignments` | Fabric administrator; no admin-consent permissions; roles all ForceNew |
| Domain workspace assignment | Automatable (preview) | `fabric_domain_workspace_assignments` | Preview; override needs a preview tenant setting |

**One-line rule:** automatable ⟺ a write operation exists on the object itself and its identity table
says "Service principal … Yes"; a `GET`-only surface, a view over other items, or a verb over a set is
portal-only no matter how central it looks.

## What this does not establish

- Whether a hidden or undocumented route exists behind the portal for workspace-app publish — I can
  only report that no operation appears in `fabric-rest-api-specs` or the Power BI REST reference.
- Whether `fabric_tag` actually requires Fabric administrator at tenant scope: the provider doc states
  no permission at all and omits the usual "supports Service Principal authentication" line, while the
  admin API it wraps requires the role.
- Whether the inbound firewall / Azure-resource-rules features are GA in the product: the API text says
  preview, the Learn articles (2026-03-09, 2026-07-21) carry no preview banner, and the provider does
  not gate them. Three sources, three answers; treat as preview until the spec drops the note.
- Whether assigning `fabric_workspace_encryption` to a workspace that already contains unsupported
  items fails at plan time or apply time.
- Whether an org-app audience definition can express a *new* Entra group, or only reference one that
  already exists — the definition format was not read.
- Real behaviour of `PUT …/communicationPolicy` when only one of `inbound`/`outbound` is supplied; the
  spec says the rest reset to defaults, which implies `Allow`.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`fabric-rest-api-specs` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/tree/3f8600f9cbe3105b91015db31a6cd96915eeebd4) | all 61 `swagger.json`: operation lists, preview notes, identity tables, `CreateWorkspaceRequest`, `workspaceCmk`, `tags`, `workspaceNetworkingPolicy`, `externaldatasharing` | commit 2026-11-10, read 2026-11-12 |
| [`orgApp/swagger.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/orgApp/swagger.json) · [`orgAppAudience/swagger.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/orgAppAudience/swagger.json) | 7 + 7 GA operations, all SP Yes | read 2026-11-12 |
| [`admin/swagger.json`](https://github.com/microsoft/fabric-rest-api-specs/blob/3f8600f9cbe3105b91015db31a6cd96915eeebd4/admin/swagger.json) | tag and domain operations, admin permission wording, `bulkSetLabels` SP No | read 2026-11-12 |
| [Org app items](https://learn.microsoft.com/en-us/power-bi/explore-reports/org-app-items) | org apps as items, workspace apps distinct, audiences | ms.date 2026-09-24 |
| [Customer-managed keys for Fabric workspaces](https://learn.microsoft.com/en-us/fabric/security/workspace-customer-managed-keys) | three CMK APIs, tenant setting, CMK app ID, Key Vault role, unsupported-item rule | ms.date 2025-10-15 |
| [Workspace outbound access protection](https://learn.microsoft.com/en-us/fabric/security/workspace-outbound-access-protection-overview) | outbound default-deny, unsupported artifacts, portal gap with private links | ms.date 2026-11-10 |
| [Workspace IP firewall rules](https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-firewall-overview) | inbound-only scope, 256 rules, no preview banner | ms.date 2026-03-09 |
| [Resource Instance Rules](https://learn.microsoft.com/en-us/fabric/onelake/onelake-manage-inbound-access-trusted-resources) | trusted Azure resource IDs, layering with private links | ms.date 2026-07-21 |
| [External data sharing](https://learn.microsoft.com/en-us/fabric/governance/external-data-sharing-overview) | invite/accept flow, both tenants' switches, revoke | ms.date 2025-06-10 |
| [Tags in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/governance/tags-overview) | tenant vs domain tags, admin defines / users apply, 10 per item | ms.date 2026-03-11 |
| [Folders in workspaces](https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces-folders) | 10-level nesting, role matrix, empty-only delete | ms.date 2024-12-16 |
| [Fabric domains](https://learn.microsoft.com/en-us/fabric/governance/domains) | admin/contributor roles, override tenant setting (preview) | ms.date 2025-05-01 |
| [Endorsement overview](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) | who may promote/certify, tenant settings, no API mentioned | last updated 2024-07-11 |
| [`microsoft/terraform-provider-fabric` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/resources) | schemas, ForceNew markers, preview warnings, SP notes for all 15 resources | checked 2026-11-12 |
| [Power BI REST toc](https://learn.microsoft.com/en-us/rest/api/power-bi/toc.json) | `Apps` group is read-only; no endorsement or tag group | read 2026-11-12 |

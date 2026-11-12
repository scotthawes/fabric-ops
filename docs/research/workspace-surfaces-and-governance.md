# Which workspace-level and governance surfaces can be automated, and which are portal-only?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the nine "not assessed" rows of [`automation-coverage.md`](../guides/automation-coverage.md) — apps, tags, folders, network controls, CMK, external shares, endorsement, domains; the work repo's permission run-book.

## Short answer

Six of the eight families are automatable; **workspace apps and endorsement are portal-only**. Neither has a write operation anywhere in `fabric-rest-api-specs` — zero hits for "endorse" across all 61 specs, and no `/apps` route at all; the Power BI REST `Apps` group is read-only. Everything else automates, but each with a different blocker: Fabric administrator for domains and tenant-scope tags, a preview flag for folders and CMK-in-Terraform, and a second tenant for external-share acceptance. The dividing line is whether the feature is an **object** with a create/update operation, or a **view published over** other objects.

## Detail

### 1. Workspace apps — portal-only; org apps — automatable

Two different things share the word "app", and only one is addressable.

- **Workspace app** (the thing formerly called a Power BI app). `fabric-rest-api-specs` @ `3f8600f` has **no app route** — the only app-shaped paths are `/workspaces/{workspaceId}/orgApps`. The Power BI REST reference (313 toc entries, read 2026-11-12) lists only `Get App`, `Get Apps`, `Apps GetAppsAsAdmin`, `Apps GetAppUsersAsAdmin`: all reads. No publish, update, audience or unpublish operation exists on either surface. Verdict: **portal-only**, and totally so — there is no object to call.
- **Org app** (`fabric_org_app`) is a Fabric *item*: "Org apps are a newer evolution of workspace apps, implemented as Fabric items… they don't automatically rename, upgrade, migrate, or replace existing workspace apps" (org-app-items, ms.date 2026-09-24). Full lifecycle at `/v1/workspaces/{workspaceId}/orgApps[/{orgAppId}]` with `getDefinition`/`updateDefinition`, and **audiences are a second item type** (`…/orgAppAudiences`, parent referenced as `parentAppId` inside the audience definition). All 14 operations are GA, all say "Service principal and Managed identities: Yes", and both resources are non-preview. Publish = create, update = `PATCH`/`updateDefinition`, unpublish = `DELETE`. Verdict: **automatable**.

### 2. Tags — automatable, creation admin-gated; folders — partial

**Tags.** `fabric_tag` (`display_name` ≤ 40, `scope` ForceNew, `type` ∈ `Domain`|`Tenant`) is non-preview. Creation lives under `/v1/admin`: `POST /v1/admin/tags/bulkCreateTags` — "The caller must have administrator rights such as Fabric administrator", 25/min, SP Yes — likewise `PATCH`/`DELETE /v1/admin/tags/{tagId}`. Reading is not admin: `GET /v1/tags` needs only `Tag.Read.All`. Assignment is a separate verb and has **no Terraform resource**: `POST …/items/{itemId}/applyTags` needs contributor or higher, 25/min, and is not marked preview; the workspace-level twin `POST …/applyTags` **is** preview and needs workspace admin. Learn agrees on the split — "Admins define tags… Workspace admins apply tags to workspaces… Users with Write or Contributor permissions can apply up to 10 tags per item" (tags-overview, 2026-03-11). Verdict: **automatable**, creation behind Fabric administrator at tenant scope.

**Folders.** Full CRUD exists — `/v1/workspaces/{workspaceId}/folders`, `…/{folderId}`, `POST …/{folderId}/move`, `POST /items/bulkMove`, `POST /items/{itemId}/move` — and item creation takes a `folderId`. **Every operation carries the preview note**, and `fabric_folder` is one of the provider's 15 preview resources. Product limits: 10 nesting levels, delete only when empty, Admin/Member/Contributor may create and move (workspaces-folders, 2024-12-16). This is folder movement only, so "no cross-workspace move" still holds. Verdict: **partial**.

### 3. Workspace network controls — automatable, and the order is the whole problem

`{ws}` = `/workspaces/{workspaceId}`.

| Terraform resource | Controls | REST operation | Preview |
| --- | --- | --- | --- |
| `fabric_workspace_network_communication_policy` | the `inbound`/`outbound` `default_action`s | `GET`/`PUT {ws}/networking/communicationPolicy | no |
| `fabric_workspace_inbound_azure_resource_rules` | allow-list of Azure resource IDs | `…/communicationPolicy/inbound/azureResources | **API yes** |
| `fabric_workspace_outbound_cloud_connection_rules` | reachable cloud connectors / workspaces | `…/outbound/connections | no |
| `fabric_workspace_outbound_gateway_rules` | reachable gateways | `…/outbound/gateways | no |
| `fabric_workspace_git_outbound_policy` | whether Git traffic may leave the region | `…/outbound/git | no |
| `fabric_workspace_firewall_rules` | inbound IP allow-list, ≤ 256 rules | `…/inbound/firewall | **API yes** |

**None can be set at creation.** `CreateWorkspaceRequest` carries only `displayName`, `description`, `capacityId`, `domainId`, and all six take `workspace_id` as ForceNew. They always attach to an existing workspace — but *when* still matters:

- **Outbound before content.** "If unsupported items already exist in a workspace, you can't enable outbound access protection on that workspace"; once on, unsupported items can't be created (outbound-access-protection-overview, 2026-11-10). Enable between create and item deploy.
- **Policy before rules.** The Azure-resource and firewall resources are "only enforced when `inbound.public_access_rules.default_action` … is set to `Deny`"; the provider's firewall example uses `depends_on` on the policy.
- **Git policy last.** `PUT …/outbound/git` "will fail" when there is no outbound restriction, so it must follow a `Deny` policy — and without it a `Deny` workspace cannot use Git integration.
- **One missing resource:** the inbound external-data-shares bypass (`…/inbound/externalDataShares`, preview) has no `fabric_*` equivalent, so it is REST-only.

Two cautions that cause outages: `PUT` **overwrites all settings** and "If `defaultAction` is omitted … it defaults to `Allow`, which may unintentionally open inbound and outbound network access"; and the *portal* cannot configure data connection rules when private links are on, so the API is the only route. Verdict: **automatable**, with inbound rules and firewall still preview in the API while the provider exposes them ungated.

### 4. Encryption — automatable, gated on work outside Fabric

Three GA operations, no preview marker in the spec: `GET /workspaces/{workspaceId}/encryption` (viewer+), `POST …/encryption/assign` and `…/encryption/reset` (workspace **admin**), SP Yes, 100/min; `keyIdentifier` "must be a versionless key URI". `fabric_workspace_encryption` is **preview** in the provider, `workspace_id` ForceNew but `encryption_details` not, so key rotation is in place.

Prerequisites, in Learn's order: the **Apply customer-managed keys** tenant setting; a service principal for the **Fabric Platform CMK** app (app ID `61d6811f-7544-4e75-a1e6-1c59c0383311`); Key Vault with soft delete **and** purge protection; that app granted **Key Vault Crypto Service Encryption User**. Learn states the API route outright: "You can enable CMK by using the Fabric portal or APIs. Workspace administrators can use APIs Assign Workspace Encryption, Get Workspace Encryption, and Reset Workspace Encryption" (workspace-customer-managed-keys, 2025-10-15).

On an existing workspace: **yes** — `assign` takes a bare workspace, reset reverts to Microsoft-managed keys. The constraint is content, not timing: "This feature can't be enabled for a workspace that contains unsupported items", and afterwards only supported items may be created there. Verdict: **automatable**, blocked only by a tenant setting and a Key Vault role the deploy principal cannot grant itself.

### 5. External data shares — partial, because the customer has to accept

Provider side is complete: `POST`/`GET …/items/{itemId}/externalDataShares`, `GET`/`DELETE …/{externalDataShareId}`, `POST …/{externalDataShareId}/revoke` ("cannot be undone"). Needs item Read **and Reshare**, the **External data sharing** tenant switch, 10/min. `fabric_external_data_share` is non-preview; `recipient` may be a `ServicePrincipal` with a `tenant_id`, and the resource reads back `status` ∈ `Pending`/`Active`/`InvitationExpired`/`Revoked` plus `invitation_url`.

Acceptance is the asymmetry: the creator "invites a user from another tenant to accept… Upon accepting the share, the recipient chooses a lakehouse" (external-data-sharing-overview, 2025-06-10). There **is** an API — `GET /externalDataShares/invitations/{invitationId}` and `POST …/accept`, scope `ExternalDataShare.Accept.All`, switch **Users can accept external data shares** — so no browser is needed, but it must run under a principal **in the consuming tenant**. "Fabric admins need to turn on external data sharing both in the sharer's tenant and in the external tenant." Verdict: **partial** — create and revoke automatable; acceptance automatable only across a trust boundary.

### 6. Endorsement — portal-only, plainly

There is **no endorsement API**. All 61 `swagger.json` files: zero hits for "endorse". No item schema carries a badge field (the only label-ish property is `sensitivityLabelSettings`, a Purview label). The Power BI REST toc has no endorsement page either. Learn describes portal actions only — "Any user with write permissions on an item can promote it", certification "only [by] users specified by a Fabric administrator" — gated by **Enable item certification** and **Enable master data endorsement** (endorsement-overview, updated 2024-07-11). Verdict: **portal-only**; the only control is a post-deploy audit against the portal.

### 7. Domains — automatable, but only by a Fabric administrator

Everything sits under `/v1/admin/domains` and everything says "The caller must be a Fabric administrator": `POST`/`GET`/`PATCH`/`DELETE /domains[/{domainId}]`, `assignWorkspaces`, `unassignWorkspaces`, `unassignAllWorkspaces`, `roleAssignments/bulkAssign` and `bulkUnassign`, `syncToSubdomains`, `assignWorkspacesByCapacities`, `assignWorkspacesByPrincipals` — 10–25/min, SP Yes. Core offers read-only `GET /v1/domains` and `/domains/{domainId}`.

Terraform: `fabric_domain` non-preview (`parent_domain_id` ForceNew); `fabric_domain_role_assignments` non-preview but **every field ForceNew** — one principal change recreates the whole `Admins`/`Contributors` set; `fabric_domain_workspace_assignments` is **preview**. The blocker is a role, not a surface: Fabric administrator **and** "the Azure application must not have any Fabric permissions that require admin consent configured in the Azure portal". Overrides have their own preview gate — "only if the **Allow tenant and domain admins to override workspace assignments** (preview) tenant setting is enabled" (domains, 2025-05-01). Verdict: **automatable, gated** in a separate root.

### 8. The pattern

What separates the groups is not workload, licence or newness — it is whether the feature **has a body**.

- **Automatable** surfaces are objects with a create/update operation: an org app and its audience are items with public definitions; a network policy and an encryption setting are singletons with `PUT`; a tag and a domain are tenant-scoped records with `POST`. Each has the write, each identity table says "Service principal … Yes", and each Terraform resource manages the object rather than a view of it.
- **Portal-only** surfaces are **projections**: a workspace app is a curated set of *other* items plus an audience rule, and publishing is a verb over that set, so there is nothing to address; an endorsement is a badge no item schema carries, so no `PATCH` can set it. Both are `GET`-only or absent.
- **Partial** surfaces are where only half the lifecycle is object-shaped: tags exist but assignment is a second verb with no Terraform resource; external shares exist but acceptance lives in the other tenant; folders exist but every operation is preview.

The rule for a feature that does not exist yet: **find the object, then the verb.** If `fabric-rest-api-specs` has a `POST`/`PUT`/`PATCH` on the thing itself and its identity table says "Service principal … Yes", it is automatable — then check only for a Terraform `preview` marker and for a prerequisite in another admin plane (Fabric admin role, tenant setting, Key Vault, the other tenant). If the surface is a `GET`, a view assembled from other objects, or a verb over a *set* of items, it is portal-only, and no amount of scripting changes that.

## What this settles

| Surface | Verdict | Mechanism | Blocker |
| --- | :-: | --- | --- |
| Workspace app (publish, audience, unpublish) | **Portal-only** | none — absent from 61 specs; PBI `Apps` read-only | No object exists to call |
| Org app | **Automatable** | `fabric_org_app`; `POST/PATCH/DELETE …/orgApps` | Item licence only |
| Org app audience | **Automatable** | `fabric_org_app_audience`; `…/orgAppAudiences` | `parentAppId` immutable; parent delete cascades |
| Tag creation (tenant) | Automatable, gated | `fabric_tag`; `POST /v1/admin/tags/bulkCreateTags` | Fabric administrator |
| Tag assignment | Automatable, no Terraform | `POST …/items/{itemId}/applyTags` | Contributor+; 10/item; workspace variant preview |
| Folder | **Partial** | `fabric_folder` (preview); `/folders` CRUD + `move` | Preview on both surfaces |
| Network communication policy | Automatable | `fabric_workspace_network_communication_policy` | `PUT` overwrites; omitted `defaultAction` ⇒ `Allow` |
| Inbound Azure resource rules | Automatable (API preview) | `fabric_workspace_inbound_azure_resource_rules` | Only enforced when inbound = `Deny` |
| Outbound cloud / gateway rules | Automatable | `fabric_workspace_outbound_*_rules` | Only meaningful when outbound = `Deny` |
| Git outbound policy | Automatable | `fabric_workspace_git_outbound_policy` | Fails unless outbound already `Deny` |
| Workspace firewall rules | Automatable (API preview) | `fabric_workspace_firewall_rules` | Only enforced when inbound = `Deny` |
| External-share inbound bypass | **Partial** | `PUT …/inbound/externalDataShares` (preview) | No Terraform resource |
| CMK encryption | Automatable, gated | `fabric_workspace_encryption` (preview); `…/encryption/assign` | Tenant setting, CMK app SP, Key Vault role |
| External data share (create/revoke) | Automatable | `fabric_external_data_share` | Item Reshare + tenant switch; 10/min |
| External data share (accept) | **Partial** | `POST /externalDataShares/invitations/{id}/accept` | Must run in the consuming tenant |
| Endorsement | **Portal-only** | none — 0 spec occurrences | Badge is in no item schema |
| Domain / domain roles | Automatable, gated | `fabric_domain`, `fabric_domain_role_assignments` | Fabric administrator; no admin-consent permissions; roles all ForceNew |
| Domain workspace assignment | Automatable (preview) | `fabric_domain_workspace_assignments` | Preview; override needs a preview tenant setting |

**One-line rule:** automatable ⟺ a write operation exists on the object itself and its identity table says "Service principal … Yes"; a `GET`-only surface, a view over other items, or a verb over a set is portal-only no matter how central it looks.

## What this does not establish

- Whether an undocumented route exists behind the portal for workspace-app publish — only that no operation appears in either spec repo or the Power BI REST reference.
- Whether `fabric_tag` really needs Fabric administrator at tenant scope: its doc states no permission and omits the usual SP line, while the admin API it wraps requires the role.
- Whether the inbound firewall / Azure-resource-rules features are GA: the API text says preview, the Learn articles (2026-03-09, 2026-07-21) carry no banner, and the provider does not gate them. Three sources, three answers — treat as preview until the spec drops the note.
- Whether `fabric_workspace_encryption` fails at plan or apply time on a workspace that already holds unsupported items, and whether an org-app audience definition can express a *new* Entra group or only reference an existing one (definition format not read).

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`fabric-rest-api-specs` @ `3f8600f`](https://github.com/microsoft/fabric-rest-api-specs/tree/3f8600f9cbe3105b91015db31a6cd96915eeebd4) | all 61 `swagger.json`: operation lists, preview notes, identity tables, `CreateWorkspaceRequest`, `workspaceCmk`, `tags`, `workspaceNetworkingPolicy`, `externaldatasharing`; `orgApp`/`orgAppAudience`/`admin` per-file | commit 2026-11-10, read 2026-11-12 |
| [Org app items](https://learn.microsoft.com/en-us/power-bi/explore-reports/org-app-items) | org apps as items; workspace apps distinct; audiences | ms.date 2026-09-24 |
| [Customer-managed keys for Fabric workspaces](https://learn.microsoft.com/en-us/fabric/security/workspace-customer-managed-keys) | three CMK APIs, tenant setting, CMK app ID, Key Vault role, unsupported-item rule | ms.date 2025-10-15 |
| [Workspace outbound access protection](https://learn.microsoft.com/en-us/fabric/security/workspace-outbound-access-protection-overview) | outbound default-deny, unsupported artifacts, portal gap with private links | ms.date 2026-11-10 |
| [Workspace IP firewall rules](https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-firewall-overview) · [Resource Instance Rules](https://learn.microsoft.com/en-us/fabric/onelake/onelake-manage-inbound-access-trusted-resources) | inbound-only scope, 256 rules; trusted Azure resource IDs | ms.date 2026-03-09 / 2026-07-21 |
| [External data sharing](https://learn.microsoft.com/en-us/fabric/governance/external-data-sharing-overview) | invite/accept flow, both tenants' switches, revoke | ms.date 2025-06-10 |
| [Tags in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/governance/tags-overview) · [Folders in workspaces](https://learn.microsoft.com/en-us/fabric/fundamentals/workspaces-folders) | tenant vs domain tags, 10 per item; 10-level nesting, role matrix | ms.date 2026-03-11 / 2024-12-16 |
| [Fabric domains](https://learn.microsoft.com/en-us/fabric/governance/domains) | admin/contributor roles, override tenant setting (preview) | ms.date 2025-05-01 |
| [Endorsement overview](https://learn.microsoft.com/en-us/fabric/governance/endorsement-overview) | who may promote/certify, tenant settings, no API mentioned | last updated 2024-07-11 |
| [`terraform-provider-fabric` @ v1.15.1](https://github.com/microsoft/terraform-provider-fabric/tree/v1.15.1/docs/resources) | schemas, ForceNew markers, preview warnings, SP notes for all 15 resources | checked 2026-11-12 |
| [Power BI REST toc](https://learn.microsoft.com/en-us/rest/api/power-bi/toc.json) | `Apps` group is read-only; no endorsement or tag group | read 2026-11-12 |

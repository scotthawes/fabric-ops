# Which Entra and Azure DevOps operations does this design depend on, and can our principals run them unattended?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** [ADR 0002](../adr/0002-two-service-principals-federated.md) (federated principals), [ADR 0006](../adr/0006-access-through-entra-groups.md) (groups per workspace), [ADO note](ado-pipeline-mechanics.md) (environment and connection setup)

## Short answer

Every operation this design needs is **app-only capable on the Microsoft Graph side** (`Group.Create`, `GroupMember.*`, `Application.ReadWrite.All`) and **scriptable on the Azure DevOps side** with an Entra token belonging to a service principal — but only *after* two human bootstrap steps: a **Privileged Role Administrator** must consent to the Graph application permissions, and a **Project Collection Administrator** must add the first service principal to the ADO organisation. A third step is human permanently and by design: approving the production stage. Two exact payload tokens (the `{resourceType}` for a service connection and the environment's check `resource.type`) are **not stated on Learn** and are the only mechanical gaps left.

## Detail

### Part A — Microsoft Entra / Microsoft Graph

All paths are `https://graph.microsoft.com/v1.0`. "App-only" means an application permission used by a service principal with a federated credential or secret — no signed-in user.

| # | Operation | Method + path | Delegated | Application (least → higher) | App-only? |
| --- | --- | --- | --- | --- | --- |
| 1a | Create security group | `POST /groups` | `Group.ReadWrite.All` | `Group.Create` → `Group.ReadWrite.All`, `Directory.ReadWrite.All` | **Yes** |
| 1b | Delete group | `DELETE /groups/{id}` | `Group.ReadWrite.All` | `Group.ReadWrite.All` | **Yes** |
| 1c | Read direct members | `GET /groups/{id}/members` | `GroupMember.ReadBasic.All` | `GroupMember.ReadBasic.All` → `Group.Read.All`, `Directory.Read.All` | **Yes** |
| 1d | Read transitive members | `GET /groups/{id}/transitiveMembers` | `GroupMember.ReadBasic.All` | `GroupMember.ReadBasic.All` → `Group.Read.All`, `Directory.Read.All` | **Yes** |
| 2a | Add member | `POST /groups/{group-id}/members/$ref` (body `@odata.id`) | `GroupMember.ReadWrite.All` | `GroupMember.ReadWrite.All` (+ `Application.ReadWrite.All` when the member is a servicePrincipal) | **Yes** |
| 2b | Remove member | `DELETE /groups/{id}/members/{id}/$ref` | `GroupMember.ReadWrite.All` | `GroupMember.ReadWrite.All` | **Yes** |
| 3a | Create app registration | `POST /applications` | `AppRegistration.Create` | `AppRegistration.Create` → `Application.ReadWrite.OwnedBy`, `Application.ReadWrite.All` | **Yes** |
| 3b | Create its service principal | `POST /servicePrincipals` (`appId` required) | `Application.ReadWrite.All` | `Application.ReadWrite.OwnedBy` → `Application.ReadWrite.All` | **Yes** |
| 4 | Create / rotate federated identity credential | `POST /applications/{id}/federatedIdentityCredentials`; rotate with `PATCH /applications/{id}/federatedIdentityCredentials/{federatedIdentityCredentialId}` | `Application.ReadWrite.All` | `Application.ReadWrite.OwnedBy` → `Application.ReadWrite.All` | **Yes** |
| 5 | Access report reads | same as 1c/1d | as 1c/1d | as 1c/1d | **Yes** |

**4 — the credential hangs off the application object, not the service principal.** `POST /applications/{id}/federatedIdentityCredentials` (or `.../applications(appId='{appId}')/...`) is the only form Graph v1.0 documents; there is no `/servicePrincipals/.../federatedIdentityCredentials` page in v1.0 — the service-principal route could not be established, and user-assigned managed identities get the same credential type through the ARM resource instead. Body: `name` (3–120 chars, URL-friendly, immutable), `issuer` (≤600), `subject` (≤600), `audiences` (a **single** value, recommended `api://AzureADTokenExchange`), optional `description`. Maximum **20** credentials per application; **no wildcards in any property**; `issuer` + `subject` must be unique on the app.

**4 — turning this into an ADO trust.** The pairing is documented in the reverse of the obvious order: create the service connection first, read back `workloadIdentityFederationIssuer` and `workloadIdentityFederationSubject`, then create the credential, then finish. "The federated credential can only be created after the service connection is created." For a new connection the issuer is `https://login.microsoftonline.com/<tenant>/v2.0`; the subject is bound to org/project/connection identifiers, so a rename silently breaks the exchange (see the ADO note).

**1a trap.** A group created with `Group.Create` application permission **without owners** "creates the group anonymously and the group isn't modifiable". An app may make itself owner or member, but then it needs `User.Read.All` / `Application.Read.All` / `Directory.Read.All` depending on the member types it binds. Our automation must set `owners@odata.bind` to itself; at most 20 owner/member relationships can be set in the create call.

**1c trap, load-bearing for the access report.** `GET /groups/{id}/members` is explicitly **not transitive** and has a known v1.0 defect: **service principals are not listed as members**. The documented workarounds are the `beta` endpoint or `GET /groups/{id}?$expand=members`. Since ADR 0006's whole concern is a group as a principal, a report built on the v1.0 `/members` call would miss exactly the case that matters.

**5 — nesting and paging.** `transitiveMembers` "is transitive and returns a flat list of all nested members", so one call per workspace group resolves nesting; `members` does not. Both page at **100 by default, 999 maximum**, with `@odata.nextLink` to follow; `$count`, `$filter`, `$search` require `ConsistencyLevel: eventual` and advanced query parameters, and `$expand` cannot be combined with them. A report over 3N groups is N paged calls, so budget for throttling and honour `Retry-After`.

**No licence tier is needed for any of the above.** The Graph reference pages for these operations state no licence prerequisite, and the workload-identity pages state none either. Entra ID **P1/P2** is required for **role-assignable groups** ("With Microsoft Entra ID P1 or P2, you can create role-assignable groups and assign Microsoft Entra roles to these groups") — we create plain security groups, so this does not apply — and for dynamic membership and group-based licensing, neither of which we use. Could not establish a positive statement that federated credentials are free; only the absence of a requirement.

**Human-only in Entra.** Consenting to **application permissions** is admin-only ("Only admin can consent"), and for **Microsoft Graph app roles** specifically the role is **Privileged Role Administrator** — Application Administrator and Cloud Application Administrator are explicitly excluded from consenting to Graph app roles. Assigning a directory role, or creating a group with `isAssignableToRole`, needs Privileged Role Administrator / Global Administrator class rights; we do neither.

### Part B — Azure DevOps

PAT scopes are `vso.*`; an **Entra-token caller does not use them**. "Azure DevOps doesn't use Microsoft Entra application permissions to authorize an application identity" — it uses the access level, ADO group membership and resource permissions, with a token for `https://app.vssps.visualstudio.com/.default`. Nothing below needs a pipeline/agent context; each is a plain REST call.

| # | Operation | Method + URL | PAT scope | SP with Entra token? |
| --- | --- | --- | --- | --- |
| 1 | Create ARM connection, WIF | `POST https://dev.azure.com/{org}/_apis/serviceendpoint/endpoints?api-version=7.1` | `vso.serviceendpoint_manage` | **Yes**, with project permission to create connections |
| 2 | Authorise one pipeline | `PATCH https://dev.azure.com/{org}/{project}/_apis/pipelines/pipelinepermissions/{resourceType}/{resourceId}?api-version=7.1-preview.1` | `vso.pipelineresources_manage` | **Yes**, as resource Administrator |
| 3 | Create environment | `POST https://dev.azure.com/{org}/{project}/_apis/distributedtask/environments?api-version=7.1` | `vso.environment_manage` | **Yes**, with the project **Creator** role |
| 4a | Add approval check | `POST https://dev.azure.com/{org}/{project}/_apis/pipelines/checks/configurations?api-version=7.1-preview.1` | `vso.build_execute` **and** `vso.pipelineresources_manage` | **Yes**, as environment Administrator |
| 4b | Read approval record | `GET https://dev.azure.com/{org}/{project}/_apis/pipelines/approvals/{approvalId}?api-version=7.1` | `vso.build` | **Yes** |
| 5 | Require reviewers on `main` | `POST https://dev.azure.com/{org}/{project}/_apis/policy/configurations?api-version=7.1` | `vso.code_write` | **Yes**, with repository **Edit policies** |
| — | Add the SP to the org | `POST https://vsaex.dev.azure.com/{org}/_apis/serviceprincipalentitlements?api-version=7.1-preview.1` | — | **Yes**, but only for a caller who is already Project Collection Administrator |

**1 — payload.** The configuration file in the automation doc is the request body:

```json
{"data":{"subscriptionId":"…","subscriptionName":"…","environment":"AzureCloud",
         "scopeLevel":"Subscription","creationMode":"Manual"},
 "name":"sc-fabric-deploy","type":"AzureRM","url":"https://management.azure.com/",
 "authorization":{"scheme":"WorkloadIdentityFederation",
   "parameters":{"tenantid":"…","serviceprincipalid":"<appId>"}},
 "isShared":false,"isReady":true,
 "serviceEndpointProjectReferences":[{"projectReference":{"id":"…","name":"…"},"name":"sc-fabric-deploy"}]}
```

`creationMode` must be `"Manual"`: "Azure DevOps doesn't support the use of `"creationMode": "Automatic"` for non-user principals", because automatic mode needs an on-behalf-of flow the platform will not run for an app. So ADO never creates the app registration for us; the order is identity → connection → credential → role assignment. **The federated credential must exist before the connection is used, but not before it is created.**

**2 — one unverified token.** The body is `{"pipelines":[{"id":16,"authorized":true}]}`, but the reference documents `{resourceType}` only by example (`queue`) and gives no enumeration. `resourceType` for a service connection is **not established**; do not assume `endpoint` without a smoke test. Authorisation also needs the caller to be an **Administrator** of that connection.

**3 — environment.** Creating one needs the project-level **Creator** role (default: Build Administrators, Release Administrators, Project Administrators), and "its creator is added as Administrator by default" — so the service principal that creates the environment can then attach its own checks.

**4a — check body.** `type.id` for an Approval is `8c6f20a7-a545-4486-9777-f762fafe0d4d` (`"name":"Approval"`); `settings` carries `approvers[]`, `executionOrder`, `minRequiredApprovers`, `instructions`, `blockedApprovers`; `timeout` is in minutes (43200 = 30 days). The reference exemplifies only `"resource":{"type":"queue","id":"1"}`; the token for an environment is **not established**, though the resource is identified by `{type, id}` and the environment's integer `id` comes from the create response.

**4b — reading the record.** `vso.build` is enough, and the response is the object the ADO note already describes (`status`, `createdOn`, `lastModifiedOn`, `minRequiredApprovers`, `steps[]`). Approving is a separate `PATCH .../approvals/{id}` and is a **human decision**; whether a service principal may be listed as an approver could not be established, and the design does not want it.

**5 — reviewer policy.** `type.id` `fa4e907d-c16b-4a4c-9dfa-4906e5d171dd` ("Minimum approval count"), `settings.minimumApproverCount`, `creatorVoteCounts`, and `scope[]` of `{repositoryId, refName:"refs/heads/main", matchKind:"exact"}`. Creating policies needs Project Administrators or repository-level **Edit policies**.

## What this settles

| Operation | Automatable with | Used by our design |
| --- | --- | --- |
| Create/delete security group, set owner | `sp-fabric-admin`, `Group.Create`/`Group.ReadWrite.All` | **Yes** — 3N workspace groups |
| Read direct + nested members | either SP, `GroupMember.ReadBasic.All`/`Group.Read.All` | **Yes** — access report |
| Add/remove group member | `sp-fabric-admin`, `GroupMember.ReadWrite.All` | **No** — humans manage membership (ADR 0006) |
| Create app registration + service principal | `Application.ReadWrite.All` | One-time, per principal |
| Create/rotate federated credential | `Application.ReadWrite.All` | **Yes** — rotation run-book |
| Consent Graph app permissions | **Privileged Role Administrator (human)** | One-time bootstrap |
| Create ARM connection on WIF | SP with Entra token + ADO project permission | **Yes** — two connections |
| Authorise one pipeline per resource | SP as resource Administrator | **Yes** |
| Create environment | SP with Creator role | **Yes** — one per stage |
| Attach approval check | SP as environment Administrator | **Yes** |
| Read approval record | SP, `vso.build` | **Yes** — audit |
| Add SP to ADO org | **Project Collection Administrator (human)** | One-time bootstrap |
| Require reviewers on `main` | SP with Edit policies | **Yes** |
| Approve a production run | **Human approver** | **Yes**, deliberately |

The three human-only operations:

1. **Consenting the Graph application permissions.** Application Administrator cannot consent to Microsoft Graph app roles; only Privileged Role Administrator (or a custom role with the consent permission) can. Everything app-only in Part A depends on this having happened once.
2. **Adding the first automation service principal to the ADO organisation** with an access level and project membership. It is API-able (`serviceprincipalentitlements`) but only by an existing Project Collection Administrator, so the first one is a person.
3. **Approving the production stage.** A person, every run; the approval record is the audit trail and no automation should be able to satisfy it.

## What this does not establish

- The `{resourceType}` value for a service connection in the pipeline-permissions API, and the `resource.type` value for an environment in the checks API. Both are the difference between a script that runs and one that 400s; verify with one call each.
- Whether `transitiveMembers` shares the v1.0 defect that hides service principals from `/members`.
- Whether a service principal can be *listed as an approver* on a check, or only a user or group.
- Any Microsoft statement that federated identity credentials require no premium licence — inferred only from the absence of a stated requirement.
- Whether a service principal's ADO **Basic** access level consumes a paid Basic slot; the doc says only that Visual Studio subscription benefits do not apply to application identities.
- Anything executed against a real tenant or organisation; no call in this note was run.

## Sources

| Source (ms.date) | Used for |
| --- | --- |
| [group-post-groups](https://learn.microsoft.com/en-us/graph/api/group-post-groups?view=graph-rest-1.0) (2024-09-13) | `POST /groups`, `Group.Create`, anonymous-group trap, owner/member binding rules |
| [group-delete](https://learn.microsoft.com/en-us/graph/api/group-delete?view=graph-rest-1.0) (2024-04-04) | `DELETE /groups/{id}`, `Group.ReadWrite.All` |
| [group-list-members](https://learn.microsoft.com/en-us/graph/api/group-list-members?view=graph-rest-1.0) (2024-09-12) | direct-only read, service-principal known issue, 100/999 paging |
| [group-list-transitivemembers](https://learn.microsoft.com/en-us/graph/api/group-list-transitivemembers?view=graph-rest-1.0) (2024-05-20) | "flat list of all nested members" |
| [group-post-members](https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0) (2025-09-09) | `$ref` add, `Application.ReadWrite.All` for SP members |
| [group-delete-members](https://learn.microsoft.com/en-us/graph/api/group-delete-members?view=graph-rest-1.0) (2024-05-23) | `$ref` remove, `/$ref` caution |
| [application-post-applications](https://learn.microsoft.com/en-us/graph/api/application-post-applications?view=graph-rest-1.0) (2024-05-14) | `POST /applications`, `AppRegistration.Create` |
| [serviceprincipal-post-serviceprincipals](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-serviceprincipals?view=graph-rest-1.0) (2024-05-20) | `POST /servicePrincipals`, `appId` required |
| [app-objects-and-service-principals](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals) (2024-10-01) | SP creation is a separate Graph step |
| [federatedidentitycredential-post](https://learn.microsoft.com/en-us/graph/api/federatedidentitycredential-post?view=graph-rest-1.0) (2025-12-04), [.../update](https://learn.microsoft.com/en-us/graph/api/federatedidentitycredential-update?view=graph-rest-1.0) (2024-04-04) | FIC parent path and rotation, permission pairs |
| [workload-identity-federation-create-trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust) (2024-12-13) | body fields, 20-credential limit, no wildcards, owner-or-role rule |
| [workload-identity-federation-considerations](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-considerations) (2024-02-28) | no licence requirement stated |
| [grant-admin-consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent) (2025-03-25) | PRA for Graph app roles, other admins excluded |
| [permissions-overview](https://learn.microsoft.com/en-us/graph/permissions-overview) (2025-12-26) | "Only admin can consent" for application permissions |
| [groups-concept](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/groups-concept) (2026-03-16) | role-assignable groups need P1/P2 |
| [Service Endpoints - Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpoints/create?view=azure-devops-rest-7.1) (checked 2026-11-12) | path, `api-version=7.1`, `vso.serviceendpoint_manage` |
| [automate-service-connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/automate-service-connections) (2026-04-22) | WIF payload, `creationMode: Manual`, forced order, issuer/subject outputs |
| [Check Configurations - Add](https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/check-configurations/add?view=azure-devops-rest-7.1) (checked 2026-11-12) | checks path, `7.1-preview.1`, scopes, Approval `type.id` |
| [Approvals - Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/approvals/get?view=azure-devops-rest-7.1) (checked 2026-11-12) | approval read path, `vso.build` |
| [Pipeline Permissions - Update](https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/pipeline-permissions/update-pipeline-permisions-for-resource?view=azure-devops-rest-7.1) (checked 2026-11-12) | PATCH path, body, `vso.pipelineresources_manage` |
| [Environments - Add](https://learn.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/add?view=azure-devops-rest-7.1) (checked 2026-11-12) | create path, `vso.environment_manage` |
| [environments concept](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments) (2026-06-17) | Creator role, creator becomes Administrator |
| [Policy Configurations - Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/policy/configurations/create?view=azure-devops-rest-7.1) (checked 2026-11-12) | reviewer policy body, `fa4e907d-…`, `vso.code_write` |
| [branch-policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies) (2026-11-08) | Project Administrators or Edit policies |
| [Service Principals and Managed Identities](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/service-principal-managed-identity) (2026-09-21) | no Entra app permissions, access level + groups, PCA gate, token resource |
| [Service Principal Entitlements](https://learn.microsoft.com/en-us/rest/api/azure/devops/memberentitlementmanagement/service-principal-entitlements?view=azure-devops-rest-7.1) (checked 2026-11-12) | automated SP onboarding path |

# Pipeline contract — the interface the design pack builds against

**Dated 2026-11-26. Illustrative.** This file fixes the names, variables, state keys and stage
graph that the reference artefacts share. It exists so four files can be written independently and
still compose. It is not a manifest and nothing here runs (ADR 0001).

Source of truth for the design: [`../research/deployment-what-does-a-unified-terraform-pipeline-look-like.md`](../research/deployment-what-does-a-unified-terraform-pipeline-look-like.md).

## 1. Fixed names

| Thing | Value |
| --- | --- |
| Workspaces | `fabric-sales-forecast-dev` · `-test` · `-prod` |
| Shared capacity | `fabric-sales-forecast-shared` |
| Resource group | `rg-fabric-sales-forecast` |
| Contributor groups | `fabric-sales-forecast-<env>-contributors` |
| Viewer groups | `fabric-sales-forecast-<env>-viewers` |
| ADO service connections | `sc-fabric-admin` · `sc-fabric-deploy` |
| ADO environments | `fabric-platform` · `fabric-dev` · `fabric-test` · `fabric-prod` |
| Pipeline file (work repo) | `pipelines/cicd.yml` |

Environment is always the **last** segment. Item names carry no environment token
([`naming.md`](naming.md)).

## 2. Bands and state

| Band | Root | State key | Principal |
| --- | --- | --- | --- |
| Build | — | — | none |
| Platform | `terraform/platform/` | `platform.tfstate` | `sc-fabric-admin` |
| Containers | `terraform/workspaces/` | `workspaces/{dev,test,prod}.tfstate` | `sc-fabric-admin` |
| Content | `content/` + `scripts/deploy_items.py` | none | `sc-fabric-deploy` |

One storage container, one blob per state. The capacity exists only in `platform.tfstate`; every
workspaces state consumes it as `data "fabric_capacity"` with a `postcondition` on
`state == "Active"`.

## 3. Root interfaces

### `platform`

Inputs: `subscription_id`, `tenant_id`, `location`, `resource_group_name`, `capacity_name`,
`capacity_sku` (default `F2`), `capacity_admin_object_ids` (list of Entra object IDs — the admin SP,
and only humans who must be able to administer it).

Outputs: `capacity_name`, `capacity_arm_id`, `resource_group_name`.

### `workspaces`

Inputs:

| Name | Type | Notes |
| --- | --- | --- |
| `environment` | string | `dev` \| `test` \| `prod` |
| `workspace_name` | string | from §1 |
| `workspace_description` | string | optional |
| `capacity_name` | string | from the platform output |
| `groups` | map(object) | `{ contributors = { role = "Contributor", owners = [object ids] }, viewers = { role = "Viewer", owners = [object ids] } }` |
| `enable_workspace_identity` | bool | default `true` |
| `identity_storage_account_id` | string | ARM ID, empty when there is no firewall-enabled storage |
| `bind_git` | bool | `true` only in dev (ADR 0005) |

Outputs: `workspace_id`, `workspace_identity_principal_id`, `group_object_ids`.

### `content` (script, not Terraform)

Inputs: `environment`, `workspace_name`, `content_dir`, `parameter_file`. Contract: an unknown
environment key fails before anything touches the tenant.

## 4. Stage graph

```
Build ──▶ Platform ──▶ Dev ──▶ Test ──▶ Prod
                       │        │        │
                       │        └── plan prod (last job, publishes tfplan)
                       └── control apply, then content
```

| Stage | Jobs | Gate |
| --- | --- | --- |
| Build | bundle content, `fmt -check`, `validate` — no credentials | branch policy on `main` |
| Platform | apply `platform` | optional approval on `fabric-platform` |
| Dev | control apply (`sc-fabric-admin`), content (`sc-fabric-deploy`) | none beyond branch policy |
| Test | control apply, content, **plan prod** (last job) | none, or a reviewer |
| Prod | apply `tfplan` (saved in Test), content | **Approvals check on `fabric-prod`** |

Rules that follow from the research note:

- The prod **plan** is produced in the Test stage so the approver sees it; the Prod stage does not
  re-plan.
- A saved plan is per state; it is never passed between environments.
- Content promotes as the artefact built once in Build; Terraform promotes as the commit plus the
  committed `.terraform.lock.hcl`.

## 5. Permissions the pipeline assumes

| Principal | Needs |
| --- | --- |
| `sp-fabric-admin` | capacity administrator (`administration_members`); Azure rights to create the resource group and capacity; Storage Blob Data Contributor on the state container; workspace roles are granted by creating the workspace |
| `sp-fabric-admin` on Graph | `Group.Create`, `User.Read.All` (user owners), admin consent once |
| `sp-fabric-deploy` | `Contributor` in each deployed workspace; "Service principals can call Fabric public APIs" |

Groups are **built as code** here. [ADR 0010](../adr/0010-delegation-and-administration-model.md) §2
was amended on 2026-11-26 to record that: creation is the pipeline's, while membership and ownership
stay human. The note's separate recommendation (manual at current scale) is the reasoning that was
weighed and not taken.

## 6. File ownership for the build wave

| Unit | Writes only |
| --- | --- |
| A — platform root | `docs/reference/terraform-capacity.tf` |
| B — containers root | `docs/reference/terraform-fabric.tf` |
| D — pipeline | `docs/reference/ado-pipeline.yml` |
| E — bootstrap | `docs/runbook/03-pipeline-bootstrap.md` |

One writer per file. No unit edits this contract, the research note, an ADR, or another unit's file.

## 7. Non-negotiables

- No real tenant, subscription, workspace, capacity, group or storage IDs. Use
  `00000000-0000-0000-0000-000000000000` for GUIDs and `1111…`/`2222…` for principal object IDs.
- No secrets, client secrets, PATs or connection strings.
- No `terraform apply`, no `az` login, no API call. `validate`/`fmt` only.
- Pin providers exactly (`fabric = 1.15.1` at time of writing) and commit the lock file in the work
  repo; the reference files show the pin, not a version range.
- Label every file "illustrative, dated 2026-11-26, not runnable from this repo".

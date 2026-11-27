# Terraform roots — module contract

**Pack: 2026-11-27.1 · dated 2026-11-26 · ILLUSTRATIVE ONLY.** Nothing here is applied from
`fabric-ops` (ADR 0001). The corporate work repo copies these skeletons, renames `*.tf.tmpl` to
`*.tf`, fills placeholders, and applies them **only** through the ADO pipeline.

The authoritative interface is [`spec/0002-contract.md`](../../spec/0002-contract.md). If this page
and the contract disagree, the contract wins. Every `PLACEHOLDER` and all-zero GUID below is
deliberate.

## 1. Four roots, six-plus states

| Root | State key | Applied by | Holds |
| --- | --- | --- | --- |
| `terraform/platform` | `platform/nonprod.tfstate` | Platform: `capacity-nonprod` | `azurerm_fabric_capacity` F2 |
| `terraform/platform` | `platform/prod.tfstate` | Platform: `capacity-prod` | `azurerm_fabric_capacity` F64 |
| `terraform/domains` | `domains.tfstate` | Platform `domains` job, **only if** `createDomains` and the SP is Fabric admin | `fabric_domain`, role assignments |
| `terraform/workspaces` | `workspaces/<domain>/nonprod.tfstate` | Nonprod: one job per domain | groups, workspace, grants, Git |
| `terraform/workspaces` | `workspaces/<domain>/prod.tfstate` | Prod-`<domain>`: saved plan | same code, different tfvars |
| `terraform/domain-assignments` | `assignments/<domain>.tfstate` | Prod-`<domain>`, after content, **only if** `assignDomains` | workspace → domain (preview) |

One container (`stfabriccorp`), one blob per key (`tfstate`). A key is never shared between
stages. The platform split is the point: destroying the nonprod capacity cannot reach prod's
state, and the nonprod capacity's blast radius is one environment.

The resource group `rg-fabric-corporate` is a **bootstrap object**, not owned by either platform
state. Both capacity jobs run in parallel; two states declaring the same resource group would
race on create, and a nonprod destroy would take prod's resource group with it. `platform/main.tf.tmpl`
reads it with `data "azurerm_resource_group"`. `runbook/00-bootstrap.md` creates it.

## 2. Order states are applied

```
platform/nonprod  ∥  platform/prod          (separate keys, no shared lock)
        └──────────────┬──────────────┘
                    domains (job in Platform; conditional on createDomains)
                       │
        workspaces/<domain>/nonprod         (one job per domain, in parallel)
                       │
                 PlanProd (per domain)      (read-only; artifact tfplan-<domain>)
                       │
        workspaces/<domain>/prod            (assert_plan → apply saved plan)
                       │
                 content (fabric-cicd)      (no Terraform state)
                       │
        assignments/<domain>                (preview; unassigns on destroy)
```

Rules that follow from the state map, not from preference:

- The same root at two keys is **two applies**, never one plan containing both environments.
- Platform and Nonprod plan and apply in the same job (no approval there); `PlanProd` runs outside the
  prod band, because an approval would otherwise fire before the plan exists.
  must not fire before a plan exists; `Guard` asserts every saved plan before prod.
- A plan artifact is applied to the state and domain that produced it, and to no other.
- Apply content only after the workspace apply for that domain/environment has completed. The
  workspace blocks until capacity assignment settles; an ambient workspace GUID has no such edge.
- Content is per domain: `content/<domain>/` with `config/parameter.<domain>.yml`.

## 3. Inputs and outputs

### `platform`

| Input | Type | Value |
| --- | --- | --- |
| `environment` | string | `nonprod` \| `prod` (additive to contract §5: tags and name validation) |
| `subscription_id` | string | subscription holding the capacity |
| `tenant_id` | string | Entra tenant |
| `location` | string | Azure region, e.g. `uksouth` |
| `capacity_name` | string | `fabric-capacity-nonprod` \| `fabric-capacity-prod` |
| `capacity_sku` | string | `F2` nonprod (smallest billable), `F64` prod (P1 parity); F2–F2048 only |
| `capacity_admin_object_ids` | list(string) | UPN for users, object ID for SPs; must include `sp-fabric-admin` |

Outputs: `capacity_name` (the join key), `capacity_id` (ARM ID — informational only; **never**
pass it to `fabric_workspace.capacity_id`), `capacity_sku`, `resource_group_name`.

**Not expressible in this root:** capacity overage (an ARM property on the preview API, default-on
at 25%, 3× rate, **reviewed and set by a human in the portal after the capacity exists**),
pause/resume (an ARM action, not a property), surge protection, retention. Configuring any of them
here would give one object two owners, and the pipeline does not manage overage at all. Pause,
surge protection and retention stay in the run-book / portal. See `capacity.tf.tmpl`.

### `domains`

| Input | Type | Value |
| --- | --- | --- |
| `fabric_administrator_confirmed` | bool | guard; `false` fails at plan |
| `domains` | map(object) | one entry per `config/domains.yaml` row |
| `tenant_id` | string | Entra tenant |
| `admin_client_id` | string | `sp-fabric-admin` application ID |
| `ado_service_connection_id` | string | `sc-fabric-admin` GUID |

`domains` entry: `display_name`, `description`, `parent_domain` (empty or another key),
`admins`/`contributors` (lists of `{ id, type }`, type `User`\|`Group`\|`EntireTenant`).
Outputs: `domain_ids`, `domain_display_names`.

**Conditional root.** `fabric_domain` requires Fabric administrator; the SP must also have no
Fabric permission that requires admin consent. It runs only when `createDomains=true` **and** the
probe returned `PROBE-ADMIN` 200; the default is `false`, with a human creating the domain in the
portal. Apply only after bootstrap has verified both with a real admin API call.
`fabric_domain_role_assignments.principals` is a **set with ForceNew**: adding one principal
replaces the whole assignment.

### `workspaces`

| Input | Type | Value |
| --- | --- | --- |
| `domain` | string | lowercase hyphenated, e.g. `sales` |
| `environment` | string | `nonprod` \| `prod` |
| `workspace_name` | string | must equal `fabric-<domain>-<environment>` |
| `workspace_description` | string | optional |
| `capacity_name` | string | must equal `fabric-capacity-<environment>` |
| `groups` | map(object) | exactly `viewers`/`contributors`/`members`, each `{ role, owners }` |
| `enable_workspace_identity` | bool | SystemAssigned identity |
| `identity_storage_account_id` | string | account-scope ARM ID, or `""` |
| `bind_git` | bool | `true` only in nonprod (preflight + resource precondition) |
| `tenant_id`, `subscription_id`, `admin_client_id`, `ado_service_connection_id` | string | federated inputs |
| `ado_organization`, `ado_project`, `git_branch`, `git_connection_id` | string | additive: needed only by the nonprod Git binding |

Outputs: `workspace_id` (consumed by content), `workspace_identity_principal_id` (null when
disabled), `group_object_ids`, `workspace_name`, `capacity_id`.

### `domain-assignments`

| Input | Type | Value |
| --- | --- | --- |
| `domain` | string | lowercase domain key, resolved case-insensitively to the Fabric display name |
| `workspace_ids` | list(string) | real Fabric GUIDs; at least one |
| `tenant_id`, `admin_client_id`, `ado_service_connection_id` | string | federated inputs |

Outputs: `domain_id`, `workspace_ids`. The provider block sets `preview = true`; this root is the
only place that flag belongs. It runs only when `assignDomains=true`; the default is `false`, with a
human assigning both workspaces in the portal. **Destroy unassigns workspaces from the domain** — it
does not delete them, but it removes domain governance silently, so `prevent_destroy` stays on.

## 4. `config/domains.yaml` (corporate repo)

The matrix truth, copied verbatim from contract §5:

```yaml
domains:
  - name: sales
    display_name: Sales
    project: forecast
    repo: fabric-sales-nonprod
    owners:
      viewers: ["00000000-0000-0000-0000-000000000000"]
      contributors: ["00000000-0000-0000-0000-000000000000"]
      members: ["00000000-0000-0000-0000-000000000000"]
```

One row produces: one `domains.tfvars` entry (only when `createDomains=true`); one
`workspaces/<name>/{nonprod,prod}.tfvars` pair; the group owners; and (nonprod only) the Git binding
to `fabric-<name>-nonprod`. Content is per domain too: `content/<name>/<project>/` with
`config/parameter.<name>.yml`. The tfvars are **committed per domain**; nothing materialises them
from YAML at run time. The Build stage compares `parameters.domains` and `parameters.matrix` with
`config/domains.yaml` on the non-secret columns, and fails on drift.

## 5. What not to rename

| Thing | Why |
| --- | --- |
| `nonprod` / `prod` | environment keys, state keys, parameter.yml keys, pipeline stages |
| `fabric-<domain>-<env>` | workspace name, group-name prefix, repository name |
| `fabric-capacity-<env>` | the only join between platform state and workspace data source |
| `rg-fabric-corporate`, `stfabriccorp`, `tfstate` | fixed by contract §3; bootstrap and backend |
| state keys | a changed key is a new empty state and a duplicate object |
| resource addresses (`fabric_workspace.this`, `azuread_group.viewers`, …) | `assert_plan` rules 3, 5, 6 and every baseline |
| variable names | the pipeline's `-var-file` / `-var` interface |
| root directory names | `terraform/<root>` is what the pipeline runs |

## 6. Deliberately absent

- **Items and their definitions.** `fabric-cicd` owns them. A Terraform item resource beside the
  deployer is two writers with no arbiter: Terraform cannot read a definition back.
- **Tenant settings.** Tenant-wide blast radius; not in this pack.
- **Overage, pause/resume, surge protection, retention.** See §3.
- **Human workspace members.** Membership is through the three Entra groups, not direct grants.
  The only direct principal grant is the workspace identity, and that exception is written down.

## 7. Scripts

All four live in `skeletons/scripts/` and are renamed without `.tmpl`. They use only the Python
standard library except `deploy_items.py`, which needs `fabric-cicd` and `azure-identity`.

```bash
python preflight.py --root workspaces terraform/workspaces/env/sales/nonprod.tfvars
python assert_plan.py plan.json --root workspaces --phase nonprod   # reads checks/known-good/nonprod.json
python deploy_items.py --environment nonprod --domain sales \
  --workspace-id <guid> --content-dir content/sales --parameter-file config/parameter.sales.yml
```

`probe.py` is the read-only prerequisite check; `preflight.py` exit 0 pass / 1 findings / 2
unparseable. It rejects remaining `PLACEHOLDER` or all-zero GUID values, a bad `environment`, a
wrong derived name, and a missing group.

`assert_plan.py` implements contract §7 and exits non-zero on any violation. A missing
`checks/known-good/<phase>.json` is a failure, not a skip. The baseline is created by a human,
once, with `--write-baseline` after reviewing a plan; the pipeline never passes that flag.

`deploy_items.py` fails on an unknown environment key before importing anything. `--check-only`
validates arguments and files without contacting Fabric. `--remove-orphans` is opt-in because
unpublishing deletes items.

## 8. Schema notes (checked 2026-11-26, provider v1.15.1)

The older reference in `docs/reference/terraform-fabric.tf` shows some of these as blocks. Follow
the provider docs, which this pack does:

- `fabric_workspace.identity` is an attribute object, so the conditional is a value
  (`identity = cond ? { type = "SystemAssigned" } : null`), not a `dynamic` block.
- `fabric_workspace_role_assignment.principal` is an attribute object (`{ id, type }`).
- `fabric_workspace_git.git_provider_details` and `.git_credentials` are attribute objects.
- `azuread` v3.1.0 has **no** Azure DevOps service-connection argument. It consumes
  `ARM_OIDC_TOKEN`; only the Fabric provider takes `azure_devops_service_connection_id`.

### VERIFY items left open

1. `fabric_workspace.identity = null` — whether removing an identity applies in place, and whether
   adding one to an existing workspace avoids replacement.
2. A capacity `sku.name` change (F2→F64) applying in place; no ForceNew marker is not proof.
3. The current azuread 3.x minor at build time (`~> 3.1` was the verified line).
4. The `azapi_update_resource` hatch: storage API version and `networkAcls.resourceAccessRules`
   body shape; read the live account before enabling it.
5. Whether `data "fabric_domains"` is readable by a non-Fabric-admin SP in the target tenant.

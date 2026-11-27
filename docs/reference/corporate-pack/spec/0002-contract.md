# 0002 — Corporate pack contract

Pack: 2026-11-27.1 · illustrative, not runnable from fabric-ops (ADR 0001)

**Dated 2026-11-26.** The interface every file in this pack composes against. Fixed names, state keys,
parameters and stage graph. A file that disagrees with this document is wrong, however plausible it
looks.

Source of the decisions: wayfinder map [#41](https://github.com/scotthawes/fabric-ops/issues/41).
Illustrative only; nothing here runs from `fabric-ops` (ADR 0001).

## 1. What the pack is

A build-ready pack for the corporate work repo: a spec, four Terraform roots as `.tmpl` skeletons, one
pipeline as `.tmpl`, an operator run-book, four agent briefs, and a checker. The corporate machine
**reads this repository** and copies the pack; it never runs anything from here.

The only apply path is the ADO pipeline. There is no local `terraform apply` in the design, no
credential on the corporate laptop, and no report channel back: the pack must diagnose itself.

## 2. Directory tree

Four **roots**; the platform root is applied twice, once per capacity, so root and state are not the
same thing.

```
corporate-pack/
├── README.md                     # index, reading order, what the pack does not decide
├── VERSION                       # pack date, source commit, supersedes line
├── forbid.md                     # greppable rules; cited by AGENTS.md and check-pack.sh
├── spec/
│   ├── 0001-decisions.md         # the closed decisions, one section each
│   ├── 0002-contract.md          # this file
│   ├── 0003-open-questions.md    # tenant facts, each VERIFY + date + owner
│   └── 0004-assumptions.md       # how every unknown is absorbed: assume, probe, fallback
├── skeletons/
│   ├── terraform/platform/{main,capacity,variables,outputs,versions}.tf.tmpl
│   ├── terraform/platform/env/{nonprod,prod}.tfvars
│   ├── terraform/domains/{main,variables,outputs,versions}.tf.tmpl
│   ├── terraform/domains/env/domains.tfvars
│   ├── terraform/workspaces/{main,groups,workspace,variables,outputs,versions}.tf.tmpl
│   ├── terraform/workspaces/env/<domain>/{nonprod,prod}.tfvars
│   ├── terraform/domain-assignments/{main,variables,outputs,versions}.tf.tmpl
│   ├── terraform/domain-assignments/env/<domain>.tfvars
│   ├── terraform/README.md       # module contract: inputs, outputs, what not to rename
│   ├── pipeline/cicd.yml.tmpl
│   ├── pipeline/parameter.yml.tmpl      # copy to config/parameter.<domain>.yml, one per domain
│   ├── config/domains.yaml.tmpl
│   └── scripts/{assert_plan.py.tmpl,preflight.py.tmpl,deploy_items.py.tmpl,probe.py.tmpl,
│                report.sh.tmpl,scaffold.sh.tmpl}
├── runbook/
│   ├── 00-bootstrap.md           # the human steps before the first run
│   ├── 01-first-run.md           # stage order, checks, stop conditions
│   ├── 02-readiness.md           # the pre-run gate
│   └── troubleshooting.md        # symptom -> cause -> action, keyed by error
├── agents/
│   ├── AGENTS.md                 # invariants and authority order
│   ├── architect.md
│   ├── reviewer.md
│   ├── bootstrap-guide.md
│   └── migration-assessor.md
└── checks/
    ├── check-pack.sh
    └── known-good/README.md      # how the first baseline is recorded
```

`config/`, `content/` and the copied `pipelines/` belong to the **corporate work repo**, not to this
pack:

```
<corporate-repo>/
├── terraform/                       # the copied roots, tfvars and README
├── pipelines/cicd.yml
├── config/domains.yaml              # the domain matrix
├── config/parameter.<domain>.yml    # one parameter file per domain
├── content/<domain>/<project>/      # one content tree per domain
├── scripts/
└── checks/known-good/
```

## 3. Fixed names

| Thing | Value |
| --- | --- |
| Environments | `nonprod`, `prod` — exactly these two |
| Workspaces | `fabric-<domain>-<env>` |
| Groups | `fabric-<domain>-<env>-viewers` · `-contributors` · `-members` |
| Capacities | `fabric-capacity-nonprod` · `fabric-capacity-prod` |
| Resource group | `rg-fabric-corporate` |
| State resource group | `rg-fabric-tfstate` — separate from the platform root's group |
| State account / container | `stfabriccorp` · `tfstate` |
| Ops repository | `PLACEHOLDER-ops-repo` — holds `pipelines/cicd.yml` and `config/domains.yaml` |
| Repositories | `fabric-<domain>-nonprod` (one per nonprod workspace) |
| ADO project | one; environments `fabric-platform`, `fabric-nonprod`, `fabric-prod` |
| Connections | `sc-fabric-admin`, `sc-fabric-deploy` |
| Pipeline | `pipelines/cicd.yml` |

Domain and project both use lowercase hyphenated words. One project per domain, so the project is part
of the workspace name and not of the state key.

## 4. State keys

One container, one blob per key:

| Key | Root |
| --- | --- |
| `platform/nonprod.tfstate` | `terraform/platform` |
| `platform/prod.tfstate` | `terraform/platform` |
| `domains.tfstate` | `terraform/domains` (only if `createDomains` is enabled) |
| `workspaces/<domain>/nonprod.tfstate` | `terraform/workspaces` |
| `workspaces/<domain>/prod.tfstate` | `terraform/workspaces` |
| `assignments/<domain>.tfstate` | `terraform/domain-assignments` (preview; only if `assignDomains`) |

The platform split is deliberate: destroying the nonprod capacity cannot reach the prod state.

## 5. Parameters

`config/domains.yaml` (corporate repo) is the matrix truth:

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

Terraform inputs per state:

- `terraform/platform/env/{nonprod,prod}.tfvars`: `environment`, `subscription_id`, `tenant_id`,
  `location`, `capacity_name`, `capacity_sku` (`F2` / `F64`), `capacity_admin_object_ids`.
- `terraform/workspaces/env/<domain>/<env>.tfvars`: `domain`, `environment`, `workspace_name`,
  `capacity_name`, `groups` (three roles with owners), `enable_workspace_identity`,
  `identity_storage_account_id`, `bind_git`, plus the Git binding's `ado_organization`,
  `ado_project`, `git_branch`, `git_connection_id`.
- `terraform/domains/env/domains.tfvars` — **only when `createDomains=true`**: `domains` (one entry
  per `config/domains.yaml` row), `fabric_administrator_confirmed`, and the provider variables below.
- `terraform/domain-assignments/env/<domain>.tfvars` — **only when `assignDomains=true`**: `domain`,
  `workspace_ids` (the domain's nonprod and prod workspaces), and the provider variables below.

Every root takes the same backend/provider variables:

| Variable | Value |
| --- | --- |
| `tenant_id` | Entra tenant |
| `subscription_id` | subscription holding the capacity (workspaces: optional storage grant only) |
| `admin_client_id` | `sp-fabric-admin` application (client) ID |
| `ado_service_connection_id` | GUID of `sc-fabric-admin` |

The backend is `rg-fabric-tfstate` / `stfabriccorp` / `tfstate` with `use_azuread_auth = true` and
`use_oidc = true`; only the key varies. `rg-fabric-corporate` is a **data source**, created by
bootstrap.

Pipeline parameters, and their defaults:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `domains` | the matrix | ordered domain list, expanded per job/stage |
| `matrix` | the matrix | non-secret columns: `display_name`, `project`, `repo` |
| `createDomains` | **`false`** | run `terraform/domains`; only after `PROBE-ADMIN` 200 |
| `assignDomains` | **`false`** | run `terraform/domain-assignments`; only after `PROBE-ADMIN` 200 |

`environment` is a fifth parameter and an inert run label; no key or path is derived from it. The five are `domains`, `matrix`, `environment`, `createDomains` and `assignDomains`.

Content and its parameter file are per domain:

- `content/<domain>/<project>/` — the item definitions Build bundles for that domain.
- `config/parameter.<domain>.yml` — the `fabric-cicd` parameter file for that domain.
- `deploy_items.py --domain <domain>` refuses a content directory or parameter file whose path does
  not carry that domain, failing `CONTENT-SCOPE` before it contacts Fabric.

Every value is a placeholder until the corporate repo supplies it. No real ID is committed.

## 6. Stage graph

```
Build ──▶ Probe ──▶ Platform ──▶ Nonprod ──▶ PlanProd ──▶ Guard ──▶ Prod-<domain>
```

| Stage | Jobs | Environment | Gate |
| --- | --- | --- | --- |
| Build | bundle one content tree per domain, `fmt -check`, `validate` per root, compare `parameters.domains`/`parameters.matrix` with `config/domains.yaml` | none | none |
| Probe | read-only checks; writes `probe.json`; fails with `PROBE-*` codes | none | none (a probe that writes is a deployment) |
| Platform | two capacity jobs in parallel (`capacity-nonprod`, `capacity-prod`), each plan-then-apply in the job, then the `domains` **job** | `fabric-platform` | none — never add an Approvals check; the plan is made in the job |
| Nonprod | two jobs per domain: `control` (plan → apply) and `content` | `fabric-nonprod` | none — the environment carries the lock and the deployment record |
| PlanProd | one plan job per domain, artifact `tfplan-<domain>` | **none** | none (read-only) |
| Guard | credential-free `assert_plan` over every prod plan; exit non-zero stops the prod band | **none** | none (fails closed) |
| Prod-`<domain>` | apply the guarded plan → content → optional assign | `fabric-prod` | **human approval** |

Rules that are not negotiable:

- `PlanProd` never runs inside a prod stage; the approval would fire before the plan exists.
- One artifact per domain; a plan is never applied to another state or domain.
- `assert_plan` runs before every apply and fails closed (§7): inline in Platform and Nonprod, and in
  `Guard` against every prod plan before the approval is requested.
- `isSkippable: false` on every prod stage; a timed-out approval marks a stage *skipped*, not failed.
- **Domains are a job inside Platform, not a stage**, and are off by default (`createDomains: false`).
  A human creates each domain **and assigns its two workspaces in the portal**; the Terraform domain
  roots run only when the probe proves the SP holds Fabric administrator. The same holds for
  `assignDomains: false`: the assign job is skipped, not failed.
- **Overage is not managed here.** After Platform creates a capacity, a human reviews and sets
  overage in the portal (default on at 25% / 3×); it never appears in a plan.
- `-refresh=false` and `-target` are forbidden.
- **No local plan.** There is no read-only `terraform plan` on the corporate laptop; the pipeline's
  plan is the only plan, and the saved artifact is the thing approved.
- **Monitoring is out of this pack.** Adopting ADR 0009's event-sourced store adds a third capacity
  (F4) with its own root and state; it is not one of the two.

## 7. `assert_plan` rules

Given `terraform show -json <plan>`, fail on any of:

1. `replace` on `fabric_workspace`, `azurerm_fabric_capacity` or `fabric_domain`.
2. `delete` on `azuread_group`, `fabric_workspace` or `azurerm_fabric_capacity`.
3. A workspace plan with fewer than three `fabric_workspace_role_assignment` resources.
4. `data.fabric_capacity` whose postcondition did not evaluate (`Active`).
5. A resource count that differs from `checks/known-good/<phase>.json`, **when that baseline
   exists**. The first run has none: it prints `BASELINE-MISSING root=… phase=… counts=…` for a
   human to record, and rules 1–4 and 6 still fail closed on that run.
6. Any resource whose address is not in the expected set for that root.

The script prints a one-line verdict and the offending addresses; exit non-zero blocks the apply.

## 8. Agent roles

Four briefs, governed by one rule: **agents plan, humans approve, the pipeline applies.**

| Role | May | Must return to a human |
| --- | --- | --- |
| `architect` | choose the pipeline row, read the spec, propose a pack change | any ADR change, any name/SKU/approver, any pack version bump |
| `reviewer` | read a plan artifact, block a PR, demand a re-plan | every prod approval; any replacement; any group destroy |
| `bootstrap-guide` | run the human checklist, date a VERIFY | any tenant role, any credential, closing a VERIFY without output |
| `migration-assessor` | inventory, map, recommend a stop | deleting a source, passing a gate |

No agent approves its own prod run. The pipeline's environment check is the approval record.

## 9. Editing rules

- `.tmpl` files are copied into the corporate repo and edited there; this pack is never edited to
  match a copy. Divergence is a dated finding.
- Every file carries the pack date; `VERSION` is the only place the version is written.
- `checks/check-pack.sh` fails on a real `.tf`, a non-placeholder GUID, a secret-shaped string, a
  broken relative link, an unindexed file, or a header that disagrees with `VERSION`.

## 10. Build ownership for this wave

| Unit | Writes only |
| --- | --- |
| A — spec | `spec/0001-decisions.md`, `spec/0003-open-questions.md` |
| B — Terraform | `skeletons/terraform/**`, `skeletons/scripts/**` |
| C — pipeline | `skeletons/pipeline/**` |
| D — operator | `runbook/**`, `agents/**`, `checks/check-pack.sh`, `README.md`, `forbid.md` |

The contract (`spec/0002-contract.md`) and `VERSION` are written before the wave and are read-only to
every unit.

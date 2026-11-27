# Corporate design pack

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

## What this pack is

A build-ready pack for the corporate work repo: four Terraform roots as `.tmpl` skeletons, one
Azure DevOps pipeline as `.tmpl`, four Python scripts and two shell scripts as `.tmpl`, a domain
registry example, a spec, an operator run-book, four agent briefs and a checker.

It describes **one estate**: N domains, two environments (`nonprod`, `prod`), one capacity each,
one platform resource group plus a separate state resource group, one state container, one pipeline,
and one content tree and parameter file per domain. The fixed names, state keys and stage graph are
in `spec/0002-contract.md`; a file here that disagrees with that contract is wrong.

By default a human creates each Fabric domain **and assigns its two workspaces in the portal**:
`createDomains` and `assignDomains` are both `false`, and the two Terraform domain roots run only
when the probe proves Fabric administrator.

**What it is not.** It is not a Terraform root, an applied pipeline or a credential store. Nothing
here executes. The corporate machine reads this repository and copies the pack into the work repo;
the only apply path is the pipeline described in `skeletons/pipeline/cicd.yml.tmpl`.

## The one-way channel

- **The corporate machine reads this repo. Nothing comes back through it.** No issue is filed from
  the corporate tenant, no log is uploaded, no pipeline writes here.
- **The only return path is a person.** A wrong fact comes back as a written, dated finding carried
  by hand; it is fixed here in a commit and released as a new pack version.
- **So the pack must diagnose itself.** `runbook/troubleshooting.md` is the debugger. A finding that
  cannot be carried — "it did not work" — is not a finding.
- **A report that can be carried** names: stage, run id, error code, the failing resource address or
  state key, and the last check that passed. Nothing else survives the trip.

`ADR 0001` (fabric-ops, 2026-11-11) makes the research-only shape permanent. `VERSION` is the only
place the pack version is written; every file's header repeats it for greppability.

## Installing the pack

A new corporate repo takes the pack in one command:

```bash
bash skeletons/scripts/scaffold.sh.tmpl --target <corporate-repo>
```

`scaffold.sh.tmpl` is the runnable name; only the copy becomes `scripts/scaffold.sh`. It copies the
tree, renames every `.tmpl` to the name the pipeline reads (`pipelines/cicd.yml`, `scripts/probe.py`,
…), copies `agents/`, `checks/known-good/README.md` and the pack docs, and seeds
`config/domains.yaml` from `skeletons/config/domains.yaml.tmpl`. These are v3 additions to the tree
in `spec/0002-contract.md` §2, together with the per-domain content and parameter files; the names
and state keys there are unchanged.

Then, in this order:

1. **Fill the placeholders.** Preflight refuses a plan while a `PLACEHOLDER-…` or an all-zero GUID
   survives; the values, and who supplies each, are in [runbook 00](runbook/00-bootstrap.md).
2. **Create the repositories and the content trees.** One `fabric-<domain>-nonprod` per registry
   row, `content/<domain>/<project>/` in each, plus the ops repo that holds `pipelines/cicd.yml`
   (runbook 00 §11).
3. **Create the domain rows in the portal**, once each (runbook 00 §12). Do not hand-create the
   workspaces.
4. **Run readiness.** Every row of [runbook 02](runbook/02-readiness.md) is answered by a repo file
   or a `Probe` output — including the scaffold's own output: no `.tmpl` remains, and
   `config/domains.yaml`, `scripts/report.sh` and `checks/known-good/README.md` exist.
5. **Run `Probe`.** Read-only, no environment, no state. It writes `probe.json` and fails `PROBE-*`;
   a red probe is a tenant setting, not a repo fix.
6. **Run the first pipeline.** [runbook 01](runbook/01-first-run.md): it prints `BASELINE-MISSING`
   once per root and phase and continues, and a human commits the `known-good-<phase>` files before
   the next run. The first apply stops short of content until the per-domain
   `config/parameter.<domain>.yml` exists (runbook 00 §14).
7. **Assign the workspaces, set overage, and record them.** Also runbook 00 §14: both are portal
   actions, and the pipeline never manages overage.

`report.sh` is the only thing a person carries out of the tenant: `bash scripts/report.sh` writes one
archive naming the stage, the run id, the error code, the failing resource address or state key, and
the last check that passed. Everything else stays in the corporate repo.

## Reading order

| # | Read | Why |
| --- | --- | --- |
| 1 | `README.md` | this page: what the pack is, how it is installed, and what it is not |
| 2 | `forbid.md` | the ten rules that are never negotiable |
| 3 | `spec/0002-contract.md` | the interface: names, state keys, parameters, stages |
| 4 | `spec/0001-decisions.md` | why each decision was taken |
| 5 | `spec/0003-open-questions.md` | tenant facts still unverified — each VERIFY, date, owner |
| 6 | `spec/0004-assumptions.md` | how each unknown is absorbed: assume, probe, fallback |
| 7 | `skeletons/scripts/scaffold.sh.tmpl` | how the pack becomes a corporate repo: copy, rename, agents |
| 8 | `skeletons/config/domains.yaml.tmpl` | the domain registry: one row per domain, in the contract's shape |
| 9 | `runbook/00-bootstrap.md` | the human steps before the first run |
| 10 | `runbook/01-first-run.md` | stage order, checks after each, and the stop conditions; read 02 before you queue |
| 11 | `runbook/02-readiness.md` | the pre-run gate: every row is a repo file or a `Probe` output |
| 12 | `runbook/troubleshooting.md` | keep open during the first run |
| 13 | `agents/AGENTS.md` | authority order and the invariants an agent works under |
| 14 | `agents/<role>.md` | the brief for the role you are acting as |
| 15 | `skeletons/terraform/README.md` | the module contract: inputs, outputs, what not to rename |
| 16 | `skeletons/pipeline/cicd.yml.tmpl`, `skeletons/scripts/*.tmpl` | the mechanism |
| 17 | `checks/known-good/README.md` | how the first baseline is recorded, reviewed and committed |
| 18 | `skeletons/scripts/report.sh.tmpl` | the one artefact carried out of the tenant |
| 19 | `checks/check-pack.sh` | what the pack checks about itself |

`forbid.md` outranks every runbook. Steps 3–5 outrank 6–19: if a runbook step and the contract
disagree, the contract wins and the runbook is wrong.

## Index

| Path | What it is |
| --- | --- |
| `README.md` | this index, the reading order, what the pack does not decide |
| `VERSION` | pack date, source commit, supersedes line |
| `forbid.md` | greppable prohibitions; cited by `agents/AGENTS.md` and the checker |
| `spec/0001-decisions.md` | the closed decisions, one section each |
| `spec/0002-contract.md` | the interface every file composes against |
| `spec/0003-open-questions.md` | tenant facts, each VERIFY + date + owner |
| `spec/0004-assumptions.md` | the assumption, probe and fallback for each unknown |
| `skeletons/terraform/README.md` | module contract for the four roots |
| `skeletons/pipeline/cicd.yml.tmpl` | the one pipeline: stages, environments, gates |
| `skeletons/pipeline/parameter.yml.tmpl` | `fabric-cicd` parameter template; copy once per domain to `config/parameter.<domain>.yml` |
| `skeletons/scripts/assert_plan.py.tmpl` | the fail-closed plan gate |
| `skeletons/scripts/preflight.py.tmpl` | parameter ↔ YAML parity, placeholder refusal |
| `skeletons/scripts/probe.py.tmpl` | read-only tenant probes; writes `probe.json`, fails `PROBE-*` |
| `skeletons/scripts/deploy_items.py.tmpl` | content deployment with `fabric-cicd` |
| `skeletons/scripts/scaffold.sh.tmpl` | installs the pack into a corporate repo: copies, renames `.tmpl`, copies agents |
| `skeletons/scripts/report.sh.tmpl` | builds the carryable report archive: stage, run id, code, address, last pass |
| `skeletons/config/domains.yaml.tmpl` | the domain registry example `config/domains.yaml` is copied from |
| `runbook/00-bootstrap.md` | the human steps before the first run |
| `runbook/01-first-run.md` | stage order, checks, stop conditions, half-states |
| `runbook/02-readiness.md` | the pre-run checklist: repository, Probe, people, stop conditions |
| `runbook/troubleshooting.md` | symptom → cause → action, keyed by error and stage |
| `agents/AGENTS.md` | invariants and authority order for every agent |
| `agents/architect.md` | chooses the pipeline row; may propose a pack change |
| `agents/reviewer.md` | reads a plan artifact; blocks or demands a re-plan |
| `agents/bootstrap-guide.md` | walks the human checklist; dates a VERIFY |
| `agents/migration-assessor.md` | inventories and maps an existing estate; recommends a stop |
| `checks/known-good/README.md` | how a first-run baseline is produced, reviewed and committed |
| `checks/check-pack.sh` | links, index, headers, placeholders, secrets, `VERSION`, v3 artefacts |

### Skeleton files

```
skeletons/terraform/platform/main.tf.tmpl
skeletons/terraform/platform/capacity.tf.tmpl
skeletons/terraform/platform/variables.tf.tmpl
skeletons/terraform/platform/outputs.tf.tmpl
skeletons/terraform/platform/versions.tf.tmpl
skeletons/terraform/platform/env/nonprod.tfvars
skeletons/terraform/platform/env/prod.tfvars
skeletons/terraform/domains/main.tf.tmpl
skeletons/terraform/domains/variables.tf.tmpl
skeletons/terraform/domains/outputs.tf.tmpl
skeletons/terraform/domains/versions.tf.tmpl
skeletons/terraform/domains/env/domains.tfvars
skeletons/terraform/workspaces/main.tf.tmpl
skeletons/terraform/workspaces/groups.tf.tmpl
skeletons/terraform/workspaces/workspace.tf.tmpl
skeletons/terraform/workspaces/variables.tf.tmpl
skeletons/terraform/workspaces/outputs.tf.tmpl
skeletons/terraform/workspaces/versions.tf.tmpl
skeletons/terraform/workspaces/env/sales/nonprod.tfvars
skeletons/terraform/workspaces/env/sales/prod.tfvars
skeletons/terraform/domain-assignments/main.tf.tmpl
skeletons/terraform/domain-assignments/variables.tf.tmpl
skeletons/terraform/domain-assignments/outputs.tf.tmpl
skeletons/terraform/domain-assignments/versions.tf.tmpl
skeletons/terraform/domain-assignments/env/sales.tfvars
```

## What this pack does not decide

| Not decided here | Where it is decided | Default if nobody decides |
| --- | --- | --- |
| **Capacity sizing** — SKU, overage, surge protection, pause/resume | the corporate tenant, recorded in the work repo; the pack only carries `capacity_sku` as `F2` or `F64` | nothing scales; overage stays at its default on 25% / 3× until a human sets it in the portal, and a paused capacity fails the plan |
| **Tenant settings** beyond the three switches in `runbook/00-bootstrap.md` §8 | the Fabric administrator; the full catalogue is a fabric-ops research note, not this pack | the pipeline's first Fabric call returns 401/403 |
| **Approver roster** — who may approve `fabric-prod`, how many, for how long | the corporate project administrator, expressed as the ADO environment approval | no prod stage can start; an approval timeout marks the stage *skipped*, not failed |
| **Region** — `location` for the capacity and the state account | the corporate Azure landing zone | every command containing `PLACEHOLDER-region` fails before it changes anything |
| **Corporate policy** — retention, naming exceptions, the exceptions register, security review, item-level sharing | the corporate governance owner | the pack's defaults apply, and any exception is undocumented |

Two further non-decisions, deliberately: the pack does **not** say whether the agent may run a
read-only `terraform plan` on the corporate laptop (default: no — the pipeline's plan is the plan),
and it does **not** name the ops repository that holds `pipelines/cicd.yml` (see
`runbook/00-bootstrap.md` §11). Both are carried in `spec/0003-open-questions.md`.

## Checking the pack

**This runs in the pack repository, not in the corporate copy.**

```bash
bash checks/check-pack.sh
```

Fails, printing the offending path, on: a broken relative link, an unindexed file, a header without
`Pack: 2026-11-27.1`, any `*.tf`, any GUID that is not the all-zero placeholder, a secret-shaped
string outside the two files that define or detect it, or a `VERSION` that disagrees with the
headers. It also checks that the scaffold and the report script parse (`bash -n`), that every v3
artefact exists and is indexed here, and that `skeletons/config/domains.yaml.tmpl` carries a
`domains:` key.

The corporate repo does **not** carry this script: the scaffold copies `checks/known-good/` only.
Its gates are Build's preflight and the pipeline's `assert_plan`.

## Divergence

The pack is never edited to match a copy. `.tmpl` files are copied into the corporate repo and
edited there. A difference discovered later is a dated finding in `spec/0003-open-questions.md`,
never a silent rewrite of this tree (contract §9). A new pack version bumps `VERSION` and every
header together, in one commit.

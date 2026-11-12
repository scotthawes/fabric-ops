# What pipeline designs do the open-source Microsoft Fabric CI/CD examples actually implement, and how do they differ on the decisions that matter?

- **Status:** answered · **Checked:** 2026-11-12
- **Blocks:** nothing yet — input for whoever builds a Fabric platform elsewhere (ADR 0001, amended 2026-11-12)

## Short answer

Every example that deploys uses one of **four** promotion mechanisms, and the one their
READMEs advertise is not what separates them. Repo → REST publish dominates — ten of the
fifteen, of which six use the `fabric-cicd` library or the `fab deploy` CLI that wraps it,
three hand-roll the per-item loop (`pyfabricops`, `FabricPS-PBIP`, `fab api`) and one drives
`fab` from a notebook. One calls Fabric's **native deployment pipelines** over REST. The
designs that hold together share one shape — **dev is the only Git-bound workspace, upper
environments are repo-published** — and they diverge on the three decisions that matter:
whether schema/DDL is deployed at all, whether item ordering is declared or assumed, and
whether anything reads the tenant back after the deploy.

This note compares what practitioners built. A design being popular, or being the shape
most examples copy, is **not** evidence that it is correct or supported by Microsoft;
community repositories are craft, not authority.

## Detail

### 0. What was actually read

Every row was shallow-cloned (`git clone --depth 1`) and read from its pipeline YAML,
deploy scripts and module layout — not from its README. Commit is the clone HEAD; licence
and last push come from the GitHub API on 2026-11-12. None is archived.

| Repo | HEAD commit | HEAD date | Licence | What the code is |
| --- | --- | --- | --- | --- |
| `kevchant/AzureDevOps-fabric-cicd-sample` | `c32e4e1e` | 2025-10-16 | MIT | 4 ADO YAML variants + one Python wrapper around `fabric-cicd` |
| `kevchant/GitHub-fabric-cicd-sample` | `49e3ac1f` | 2025-07-10 | **none** | Same wrapper, 2 GitHub Actions workflows |
| `kevchant/AzureDevOps-AutomateFabricDeploymentPipeline` | `90cee6d7` | 2024-06-11 | **none** | One YAML + one PowerShell script calling the deployment-pipeline API |
| `alisonpezzott/fabricopsflow` | `3d7f3595` | 2026-03-14 | MIT | ADO YAML + `deploy.py` over the external `pyfabricops` package |
| `kerski/fabric-dataops-patterns` | `6ec433bb` | 2025-10-12 | MIT | ADO YAML deploying **only** semantic models/reports, then DAX tests |
| `michaeldeongreen/microsoft-fabric-sdlc-patterns` | `188f0339` | 2026-10-20 | **none** | 19 workflows; three deploy mechanisms, selectable by a repo variable |
| `gronnerup/FabricOps` | `e2d34a23` | 2026-10-01 | MIT | A Python engine (recipe → plan → actions) + ADO and GitHub entry points |
| `EvaluationContext/fabric-cicd-example` | `3f04b289` | 2026-11-07 | **none** | ADO YAML only, workload-identity federation, feature-workspace lifecycle |
| `chantifiedlens/deploy-microsoft-fabric-items` | `8cb71858` | 2026-01-10 | MIT | A composite GitHub Action wrapping `fabric-cicd` |
| `FabricDevCamp/fabric-cicd-whitepaper` | `402c5f7e` | 2026-06-17 | **none** | Prose only (2,889-line Markdown + .docx). No pipeline |
| `edkreuk/FMD_FRAMEWORK` | `1ff1684f` | 2026-09-08 | MIT | A setup notebook that drives `fab`; one CI job (dacpac guard) |
| `bennyaustin/fabric-accelerator` | `00b7252a` | 2026-10-04 | GPL-2.0 | One 1,306-line workflow: control plane + per-item REST + dacpac |
| `calvinchengx/fabric-emulator` | `af3278c8` | 2026-11-09 | Apache-2.0 | A local Fabric; `e2e/fabric-cicd/` runs the real library offline |
| `microsoft/fabric-cicd` | `59a0fe86` | 2026-11-12 | MIT | v1.4.0 — the library most of the above wrap |
| `microsoft/fabric-terraform-quickstart` | `46b21587` | 2026-11-12 | MIT | Terraform roots; **no** deployment pipeline of its own |

Five of fifteen carry **no licence at all**, which is the default of "all rights reserved" —
read them, do not copy them. `microsoft/fabric-toolbox` was not sampled: it is not on the
list, and the index notes it is 560 MB.

### 1. Promotion mechanism — the crux, per example

Four distinct mechanisms are actually implemented. Evidence is the file that decides it.

| Repo | Mechanism | Evidence |
| --- | --- | --- |
| kevchant ADO sample | `fabric-cicd` library: `publish_all_items` + `unpublish_all_orphan_items` | `auth_spn_secret_AzDo.py:42-45`; invoked per stage from the YAML |
| kevchant GitHub sample | same library, same wrapper file (byte-identical) | `auth_spn_secret_AzDo.py`; `.github/workflows/fabric-cicd-demo-variables.yml:63` |
| chantifiedlens action | same library, wrapped as a composite action | `scripts/auth_spn_deploy_all_workspace.py:28-31`, `action.yml:95` |
| alisonpezzott | **hand-rolled REST loop** through `pyfabricops`, not `fabric-cicd` | `scripts/deploy.py:116` (`pf.deploy_item(...)`); `pip install pyfabricops` at `azure_pipelines/deploy.yml:62` |
| kerski | **`FabricPS-PBIP` PowerShell module** (`Import-FabricItem`), fetched at run time | `Run-CICD.yml:52-55` (download), `:134` and `:199` (import) |
| michaeldeongreen | **three**, mutually exclusive via `vars.DEPLOY_METHOD`: `fabric-cicd` library, raw **Bulk Import Item Definitions API**, or a committed **Deployment Plan** | `reusable-deploy-fabric-cicd.yml:111`, `scripts/deploy_fabric_rest_bulk.py`, `scripts/deploy_fabric_cicd_non_bulk_plan.py` |
| gronnerup | `fabric-cicd` behind `fabricops.release.runner` — the only module that imports it — plus `fab` for the control plane and for `fab import`/`fab export` (`fabric/cli.py:381-401`) | `automation/src/fabricops/release/runner.py:1-8`; `engine/actions.py`, `ImportDefinition` |
| EvaluationContext | **`fab deploy`** (fabric-cli's config-driven wrapper over `fabric-cicd`) | `.azure-pipelines/templates/fab-deploy-steps.yml:65`; `fabric/foo/config.yml` |
| kevchant AutomateDeploymentPipeline | **native deployment pipelines over REST** | `scripts/DeploymentPipelines-DeployAll.ps1:121-127` (`POST /deploymentPipelines/{id}/deploy` with `sourceStageId`/`targetStageId`) |
| bennyaustin | **hand-rolled REST loop** via `fab api` per item type | `.github/workflows/deploy-fabric-accelerator.yml:611-618` and following |
| FMD_FRAMEWORK | **a notebook** driving `fab` per item, from metadata JSON | `setup/NB_SETUP_FMD.ipynb` (`run_fab_command`, `config/item_deployment.json`) |
| fabric-terraform-quickstart | none — control plane only | `quickstarts/102-fabric-capacity/main.tf` |
| fabric-emulator | none — it *provides the API* so the real library can be run offline | `e2e/fabric-cicd/driver.py`, `docs/11-testing-with-fabric-cicd.md` |

Only **one** of the fifteen publishes through Fabric's own deployment pipelines, and it is a
2024 PowerShell script (`kevchant/AzureDevOps-AutomateFabricDeploymentPipeline`) whose own
header tells the reader to run it by hand — and whose `catch` writes the error with
`Write-Host` and returns, so a failed deploy still exits 0 (`DeploymentPipelines-DeployAll.ps1:163-166`).
That mechanism is not a real contender in this sample; the community's centre of gravity is
repo → REST.

### 2. Trigger and topology

| Repo | Trigger | Shape |
| --- | --- | --- |
| kevchant ADO sample | `trigger: none`, manual | 2 stages (Test job, Prod **deployment** job); 4 template variants (parameters / variable groups / workspace parameters / +Fabric CLI) |
| kevchant GitHub sample | `workflow_dispatch` | 2 jobs, `needs: Deploy_to_Test` |
| kevchant deployment-pipeline | `trigger: [main]` | 2 stages, both `deployment` jobs on ADO environments `Test`, `Production` |
| alisonpezzott | push to `main` **and** `develop`, path-filtered to `src/**` | **one job, no stages** |
| kerski | push to `main` | one job; a second, separate pipeline runs DAX tests on a 6-hour cron |
| michaeldeongreen | push to `dev`/`test`/`main` (per-branch orchestrator) + `workflow_dispatch` | reusable workflows; one orchestrator per branch per method |
| gronnerup | ADO: push to `releases/release*`; GitHub: same + `workflow_dispatch` | Build → ReleaseTst → ReleasePrd, artefacts passed between |
| EvaluationContext | `main` → dev (batched); `release/*` → test → prod; feature provisioning is manual | 3 pipelines + 2 step templates |
| bennyaustin | `workflow_dispatch` only | 2 jobs (deploy, then gold dacpac) |
| FMD_FRAMEWORK | none | a human runs the notebook |

Branch-as-environment is the dominant topology (`dev`/`test`/`main` long-lived branches,
with `feature/*` short-lived), which is also what `microsoft/fabric-cicd` documents as its
"hero scenario": feature branches are Git-connected, deployed branches are **not**
(`docs/how_to/deployment_overview.md:5-11`).

### 3. What each stage does — and what is skipped

Four separable jobs exist across the field. No single example does all four.

| Repo | Control plane (capacity/workspace/roles/connections) | Item definitions | Schema/DDL | Post-deploy check |
| --- | --- | --- | --- | --- |
| kevchant ADO (+CLI variant) | **partial** — one variant creates the workspace and grants `-R admin` via `fab` (`fabric-cli-and-fabric-cicd-demo.yml:73,81`) | yes | no | no |
| alisonpezzott | not in the pipeline; infrastructure is a one-off notebook (`support/init_fabricopsflow.ipynb`) | yes | no | counts successes only |
| kerski | no | semantic models + reports only | no | **yes** — refresh + DAX assertions |
| michaeldeongreen | **connections** (workspace-identity pairs) as a separate manually-dispatched workflow; workspaces assumed to exist | yes | no | unit tests + post-deploy ETL pipeline run |
| gronnerup | **yes** — workspaces, roles, workspace identities, Git wiring, connections (`fabricops setup`) | yes | **yes** — dacpac via `sqlpackage` | `drift` = dry run |
| EvaluationContext | **feature workspaces** only (create, `acl set`, Git connect, relate, teardown); dev/test/prod workspaces are declared infrastructure | yes | no | deploy log as a build artefact |
| bennyaustin | **yes** — capacity (`fab create .capacities/...`), workspace, workspace identity, ACL | yes | **yes** — gold warehouse dacpac |
| FMD_FRAMEWORK | **yes** — domains, workspaces, lakehouses, variable libraries | yes | **yes** — SQL database dacpac as an item |
| fabric-terraform-quickstart | **yes**, Terraform | no | no | no |

Three observations that matter more than the table:

- **`fabric-cicd` cannot create a workspace and does not try.** Every sample that uses it
  therefore treats the workspace as pre-existing infrastructure — EvaluationContext says so
  explicitly (`fab-deploy-steps.yml:6-8`: "THE WORKSPACE MUST ALREADY EXIST"). The
  control-plane gap is filled by hand, by Terraform, or by `fab`.
- **Schema/DDL is a different toolchain, and only three examples have one.** gronnerup,
  bennyaustin and FMD all ship `.sqlproj` → `.dacpac` and deploy with `sqlpackage` or
  `Azure/sql-action`. The CI/CD samples deploy an empty warehouse/lakehouse shell and
  leave tables to notebooks at runtime. FMD's dacpac is a *committed artefact* and its
  only CI job rebuilds it and fails if the committed copy differs
  (`.github/workflows/dacpac-guard.yml:38-51`) — the one place in the sample where a
  generated binary in Git is guarded.
- **Post-deploy is where the field thins out.** Only kerski asserts anything about the
  deployed content (semantic-model refresh, then DAX query-view tests:
  `Run-CICD.yml:216-229`); michaeldeongreen runs the deployed ETL pipeline and a validation
  notebook (`deploy-prod.yml:41-50`). Everyone else stops at "the API returned 2xx".

### 4. Environment parameterisation

| Repo | Mechanism | Where the values live |
| --- | --- | --- |
| kevchant (all variants) | `parameter.yml` `find_replace` with `Test:`/`Prod:` keys | `workspace/parameter.yml` |
| chantifiedlens | `parameter.yml`, `--Environment` input | caller's repo |
| alisonpezzott | **Variable Library `valueSets/<branch>.json`** — the *branch name* is the environment key, read at deploy time | `src/utils/vl_variables.VariableLibrary/valueSets/` (`deploy.py:20`) |
| kerski | **none** — the workspace is a pipeline parameter | n/a |
| michaeldeongreen | `parameter.yml` with `$items.<Type>.<Name>.$id`, `$workspace.$id`, `$ENV:<name>`; plus a Variable Library with `Test`/`Prod` value sets; plus `FABRIC_WORKSPACE_ID` as a **GitHub Environment secret** | `data/fabric/parameter.yml`, `data/fabric/Patterns_Variables.VariableLibrary/valueSets/` |
| gronnerup | `parameter.yml` + a **generated overlay** (`extend: ./generated/dynamic.parameter.yml`) so the committed file is never rewritten | `automation/resources/parameters/parameter.yml` |
| EvaluationContext | **`config.yml` names the workspace per env by name, never by id**; `parameter.yml` rules are **regex anchored on structure**, because a feature-workspace commit rewrites the ids | `fabric/foo/config.yml:17-35`, `fabric/foo/parameter.yml:33-43` |
| bennyaustin | **`OLD_*` design-time GUIDs committed as env vars**, `sed`-replaced with `NEW_*` at deploy | `.github/workflows/deploy-fabric-accelerator.yml:44-66` |
| FMD_FRAMEWORK | Variable Library value sets (`Test`/`Production`/`Acceptance`) **plus real tenant GUIDs committed** in `config/item_config.yaml` | `config/item_config.yaml` |

Two of these are worth naming plainly.

**Committed dev GUIDs are the normal answer, not a smell.** gronnerup's parameter file
explains why (`automation/resources/parameters/parameter.yml:1-8`): dev is Git-connected, so
whatever is committed is synced verbatim and Fabric resolves report→model and pipeline→notebook
as real dependencies at sync time, rejecting a commit whose ids do not exist. Placeholder ids
in the repo therefore break dev sync. The committed artefact carries dev's real ids; the
parameter file maps them onward. EvaluationContext reaches the same conclusion from the other
direction and makes its rules regex-based *because* a feature workspace's `Commit to Git`
rewrites those ids (`fabric/foo/parameter.yml:33-43`).

**One example commits tenant GUIDs and edits them by hand.** FMD's `config/item_config.yaml`
holds workspace ids, connection ids and a SQL endpoint, and the same file is used for every
environment — environment selection is a variable inside the setup notebook. That is a
configuration file, not a pipeline, and it is the clearest illustration of the gap between
"an accelerator you run once" and "a pipeline".

### 5. Approval gates and promotion criteria

| Repo | Gate | Evidence |
| --- | --- | --- |
| EvaluationContext | **ADO environment `fabric-prod` with a manual-approval check**, and a **prod plan as the last job of the Test stage** so the approver reads a plan, not a commit hash | `deploy-release.yml:19-23,72-93` |
| kevchant deployment-pipeline | Prod is a `deployment` job on environment `Production` — an approval check *can* be attached; nothing in the repo configures or documents one | `automate-fabric-deployment-pipelines.yml:48-50` |
| michaeldeongreen | Test/Prod are GitHub **Environments** (`environment: ${{ inputs.environment }}`) plus a branch-policy workflow that refuses `dev→main` and anything but `dev→test` | `reusable-deploy-fabric-cicd.yml:45`, `enforce-promotion-path.yml:21-33` |
| gronnerup | **none** — `ReleasePrd` depends on `ReleaseTst` and nothing else; GH version has no `environment:` key | `.azure-pipelines/solution_release_multistages.yml:38-45`, `.github/workflows/_template_release_solution.yml:10-23` |
| alisonpezzott | **none** — a push to `develop` deploys dev, a push to `main` deploys prod, in the same job | `azure_pipelines/deploy.yml:1-10` |
| kerski | none; main-push deploys straight to whatever workspace is named | `Run-CICD.yml:7-10` |
| kevchant ADO/GitHub samples | Prod job on ADO environment `Production` / a second GitHub job; no check configured | `fabric-cicd-demo-gblparameters.yml:95` |
| bennyaustin, FMD | manual dispatch / manual notebook — the human *is* the gate | — |

Only one example treats the approval as an engineering problem rather than a checkbox:
EvaluationContext puts the prod **plan** in the last job of the Test stage, because ADO
evaluates an environment's checks when the *stage* starts, so anything in the Prod stage runs
after approval. That is a design decision taken from ADO's semantics
(`deploy-release.yml:19-23`), not from a template.

### 6. Authentication

| Repo | Identity | Secret stored? |
| --- | --- | --- |
| EvaluationContext | **workload identity federation** — `AzureCLI@2` with `addSpnToEnvironment: true`, then `fab auth login --federated-token "$idToken"` | **no secret in ADO at all** (`fab-setup-steps.yml:4-7,50-62`) |
| kevchant (all) | SP id + secret → `Connect-AzAccount -ServicePrincipal` → `Get-AzAccessToken`; `fabric-cicd` then picks up the ambient credential | yes, in variable groups or GitHub secrets |
| kevchant ADO "gblparameters" variant | **SP secret passed as a pipeline *parameter*** with `default: SECRETVALUE` | yes, and it lands in run history (`:20-22`) |
| alisonpezzott | SP secret via Key Vault-backed variable group `FAB_CREDENTIALS` (`pyfabricops` auth provider `"env"`) | yes, in Key Vault |
| kerski | variable group `TestingCredentials`, `USERNAME_OR_CLIENTSECRET` — **supports a user account or an SP**, detected by GUID regex | yes |
| michaeldeongreen | SP secret in GitHub Environment secrets; runtime connections use **`WorkspaceIdentity`**, explicitly not the deploy credential | yes, in the environment |
| gronnerup | `TENANT_ID`/`CLIENT_ID`/`CLIENT_SECRET` from an ADO variable group `Fabric_Automation` | yes |
| chantifiedlens | SP secret passed as **action inputs** (env for the step) | yes |
| bennyaustin | `fab auth login -u ... -p ...` with three repo secrets; a `GOLD_DW_CONNECTION_STRING` is assembled with the **client secret embedded** | yes |
| FMD | SP/workspace identity, credentials not in the repo; the notebook assumes a logged-in `fab` | n/a |

Workload identity federation appears **once**. Everything else stores a client secret
somewhere, and three examples handle it in a way that widens exposure: a secret as a
pipeline parameter (kevchant's "global parameters" variant, `:20-22`); a secret
concatenated into a SQL connection string (`bennyaustin:1252`,
`gronnerup/automation/scripts/generate_connection_string.py:44-52`); and that same string
then **echoed into the build log** as a non-secret ADO variable
(`gronnerup/.azure-pipelines/_template_release_solution.yml:99-105` — `echo "$(connection_string)"`,
with no `issecret=true` and no `##vso[task.setsecret]`).

michaeldeongreen is the only example that separates the *deployment* identity from the
*content* identity: pipelines and notebooks authenticate as the workspace identity, and the
deployer SP secret is only used for the publish. `prepare_fabric_workspace.py:45-50` fails
the run if `FABRIC_RUNTIME_AUTHENTICATION` is anything but `WorkspaceIdentity`.

### 7. Ordering and dependencies

| Repo | How order is decided |
| --- | --- |
| `fabric-cicd` itself | a **fixed type order**, `SERIAL_ITEM_PUBLISH_ORDER` (`src/fabric_cicd/constants.py:86-120`): VariableLibrary → Warehouse → Lakehouse → … → SemanticModel → Report → … → DataPipeline → … → Ontology → DataAgent |
| gronnerup | layers in the recipe with declared references; `plan.py` orders actions from `depends_on` |
| michaeldeongreen | **three phases** by hand (Lakehouse+Ontology, then everything, then DataPipeline) written to work around type ordering, **or** a committed `DeploymentPlan.DeploymentPlan/plan.yml` whose `groups` carry `dependsOn` |
| kerski | semantic models first, then **read `/items` back from the workspace** to resolve each report's model id by display name before importing the report (`Run-CICD.yml:141,192-200`) |
| bennyaustin | a hand-written step sequence, with `sed` rewriting each newly created id into the checkout before the next item |
| alisonpezzott | `sorted()` of the item paths — i.e. **alphabetical**, not dependency order (`deploy.py:39`; `utils.py:91` returns `sorted(items)`) |
| kevchant, chantifiedlens, EvaluationContext | inherited from `fabric-cicd`'s fixed order |

Two contradictions are visible in the code, and both are worth knowing before copying a
pattern:

- michaeldeongreen's `parameter.yml:48-50` asserts "fabric-cicd deploys the Lakehouse before
  the Variable Library, so the ID is guaranteed to be available". The library's
  `SERIAL_ITEM_PUBLISH_ORDER` puts **VariableLibrary at 1 and Lakehouse at 4**
  (`constants.py:87,90`). `$items.` resolution does re-read the deployed workspace per
  substitution (`_parameter/_utils.py:527`), so the substitution may still succeed — but the
  stated reason is wrong, and a reader who copies the comment will not know why the rule
  works.
- alisonpezzott's selective deploy iterates item paths in alphabetical order. Nothing in
  `deploy.py` sequences a lakehouse before the notebook that references it, so correctness
  depends entirely on `pyfabricops.find_and_replace` having rewritten the ids and on Fabric
  tolerating a forward reference. This is the one design in the sample where a bad ordering
  is a plausible first-run failure, not a theoretical one.

### 8. Test, dry-run and validation before deploy

This is the axis where the field is weakest, and the two examples with real validation are the
two that treat the pipeline as software rather than YAML.

| Repo | Pre-deploy validation |
| --- | --- |
| michaeldeongreen | `pytest tests/` on every PR (`run-tests.yml:28`); `workspace_swap.py --check-ready` on PRs into `dev`, which **scans the committed items for non-dev GUIDs** (`check-pr-ready.yml:29`); a `--dry-run` plan validator before the plan-driven deploy |
| gronnerup | offline unit suite against a **fake `fab`** binary; `fabricops recipe validate --all`; `plan --dry-run` performs every read and no write; Best Practice Analyzer over every semantic model as a separate ADO job, and it **fails rather than passes when it finds no models** (`pr-validation.yml:99-103`) |
| kerski | none before deploy; all validation is after |
| EvaluationContext | none before publish; the *plan* is produced for the approver, after the test deploy |
| bennyaustin | none |
| FMD | `dacpac-guard` only — proves the committed binary matches the SQL sources |
| kevchant, chantifiedlens, alisonpezzott | none |
| `fabric-cicd` | has **no dry run** — it publishes. This is why `fabric-emulator` matters: it serves the Fabric API locally so the real library can be exercised offline (`e2e/fabric-cicd/run.py`, `docs/11-testing-with-fabric-cicd.md`) |

`microsoft/fabric-cicd`'s own guidance contradicts the selective deploys that two examples
implement. `docs/how_to/deployment_overview.md:14-20`: "fabric-cicd applies a **full
deployment** on every run — it does not inspect commit history or compute diffs", and
selective deployment is "not recommended due to the risk of broken deployments caused by
unresolved item dependencies" (`docs/how_to/optional_feature.md:233-235`). alisonpezzott
deploys only what `git diff` touched, kerski does the same for models and reports, and
michaeldeongreen exposes `items_to_include` per plan group. Each is defensible for the item
types it names; none of them is the library's recommendation.

### 9. Drift and post-deploy verification

| Repo | Reads anything back? |
| --- | --- |
| gronnerup | **yes, and compares content** — `ExportDefinition`, hash it, skip the import when it matches (`engine/actions.py`, `ImportDefinition.apply` / `_current_hash`). "Drift" is the same code path as a dry run (`engine/drift.py:1-10`), and there is no state file: the tenant is the source of truth |
| kerski | yes — lists `/items` to bind reports, refreshes each promoted model, runs DAX tests, publishes results |
| michaeldeongreen | no definition read-back; verifies by running the deployed pipeline and asserting its output |
| EvaluationContext | polls `git/status` until `workspaceHead` equals `remoteCommitHash` after a feature-workspace commit — a real read-back, but only of Git state |
| bennyaustin | reads item ids back to wire the next item; not verification |
| kevchant, chantifiedlens, alisonpezzott | no |
| `fabric-cicd` | refreshes deployed *metadata* to decide create vs update; it does not compare definitions and does not report drift |

gronnerup's approach is the only one that answers "is the tenant still what the repo says?"
without deploying. The cost is a full export per item per run.

### 10. Secrets, state and `.gitignore` discipline

- **No Terraform state is committed** anywhere in the sample; only
  `fabric-terraform-quickstart` uses Terraform at all, and it has no remote backend
  configuration in the quickstarts — local state, by omission.
- **Generated artefacts in Git:** FMD commits a `.dacpac` and guards it with CI; gronnerup
  writes its generated parameter overlay to a path that is gitignored
  (`automation/resources/parameters/generated/`) and keeps the committed `parameter.yml`
  as the source of truth; michaeldeongreen commits a `DeploymentPlan` item whose YAML *is*
  the deploy order.
- **`.gitignore` is thin where it matters most.** kevchant's ADO sample ignores only
  `**/.pbi/localSettings.json` and `**/.pbi/cache.abf` — no `*.pbix`, no `.env`. The
  GitHub sample has **no `.gitignore` at all**. alisonpezzott's is better (`.env`, `.venv`,
  `roles.json`, `tmp`). EvaluationContext's ignores `.pbi/`, `*.pbix`, `*.pbit` — correct
  for a PBIP repo.
- **Committed identifiers, not committed secrets.** bennyaustin commits the *design-time*
  tenant's capacity id, workspace id, tenant id and connection ids as workflow env vars
  (`deploy-fabric-accelerator.yml:44-66`). They are not credentials, but they are the kind of
  value that makes a repo tenant-specific, and the kind this repo's `AGENTS.md` asks to keep
  out even when a placeholder would do.

### 11. What the designs agree on

Worth recording because it is the closest thing to a consensus in the sample:

1. **The workspace is infrastructure; the repo is content.** No example lets the deploy
   create the workspace it publishes into — except via an explicit `fab`/Terraform step.
2. **Dev is the branch-connected workspace; upper environments are not.** Stated by
   `fabric-cicd`'s own docs, by gronnerup (`parameter.yml:1-8`), and enforced in
   michaeldeongreen's code (`prepare_fabric_workspace.py:53-63` refuses a target that is
   the Git-synced dev workspace).
3. **Orphan removal is part of the deploy**, not a separate job — `unpublish_all_orphan_items`
   is called in every `fabric-cicd` wrapper in the sample, including the one inside the
   composite action. Note what that means: a definition missing from the repo is **deleted**
   from the target workspace on the next run.
4. **The deploy log is the primary evidence.** EvaluationContext publishes it as a build
   artefact on failure *and* success (`fab-deploy-steps.yml:68-72`); nothing else in the
   sample records what a run changed.

## What this settles

- **The promotion mechanism is repo → REST in practice.** Of the fifteen repos, nine publish
  item definitions from the repo (`fabric-cicd` library, `fab deploy`, `FabricPS-PBIP`,
  `pyfabricops`, or a bespoke loop), one calls Fabric's native deployment pipelines, one
  drives `fab` from a notebook, one is Terraform-only, one is prose, one emulates the API so
  the real deployer can be run offline, and one *is* the library the others wrap.
- **Four mechanisms, one recommendation:** publish from the repo into a workspace that
  already exists; bind only feature branches to Git; keep upper environments unbound.
  An example diverging from that is either solving a feature-workspace problem
  (EvaluationContext) or is a one-tenant accelerator (FMD, bennyaustin).
- **Ordering is where the sample is least careful.** Most examples inherit one fixed type
  order; two deploy selectively, which the library advises against; one of those iterates
  items alphabetically; one writes a three-phase workaround whose stated rationale
  contradicts the library constant it depends on; one declares order in a committed plan
  file.
- **Schema/DDL is a separate pipeline, and only the accelerators have one.** If the target
  platform needs warehouse tables and views versioned, the sample offers `sqlproj` →
  `dacpac` → `sqlpackage` (gronnerup, bennyaustin) or a guarded committed `.dacpac` (FMD),
  and nothing else.
- **Substantive validation before deploy exists in two repos** (michaeldeongreen, gronnerup),
  plus FMD's single dacpac guard. "Nothing was run against a tenant" is the default, and the
  emulator is the only path in the sample to exercising the real deployer offline.
- **Gates are usually configuration nobody wrote down.** Where a gate exists
  (EvaluationContext, michaeldeongreen), it is an environment with a check; where it looks
  like one exists (kevchant's `environment: Production`), the repository does not say.

## What this does not establish

- **Nothing here was executed.** No example was run against a tenant, a capacity or a
  service principal; every claim about what a pipeline *does* is read from its YAML and
  scripts. A pipeline that reads correctly can still fail on the day — several would, on the
  evidence above (alisonpezzott's ordering, chantifiedlens's dead token plumbing).
- **The Fabric API's own behaviour is not re-verified here.** Deployment-pipeline semantics,
  the Bulk Import API's preview contract and the `git/initializeConnection` actions are
  taken from the code that calls them; the authoritative surface is
  [`fabric-api-inventory.md`](fabric-api-inventory.md).
- **Licence status is the API's answer, not legal advice.** Five repos report no licence;
  that means no grant of rights, and the note treats them as read-only reference.
- **Popularity is not evidence.** Star counts in the index range from 2 to 347 in this
  sample and several of the more careful designs are the least-starred.
- **The whitepaper is community opinion.** It is cited once, for the shape of the release
  process, and it is not authority — `learn.microsoft.com` and `microsoft/*` repos are.
- **Not sampled:** `microsoft/fabric-toolbox` (560 MB, not on the brief),
  `chantifiedlens/GH-fabric-cicd-sample` and the other chantifiedlens siblings,
  `kerski`'s OneLake variant. Each is another copy of a design already represented.
- **Support status.** None of these patterns is supported by Microsoft — they are third-party
  code, and `fabric-cicd` is the only component in the sample that is.

## Sources

| Source | What it was used for | Dated |
| --- | --- | --- |
| [`kevchant/AzureDevOps-fabric-cicd-sample`](https://github.com/kevchant/AzureDevOps-fabric-cicd-sample/tree/c32e4e1e211db423f18c5c3a46bacb06674a5962) | ADO stages, secret-as-parameter, `fabric-cicd` wrapper, `unpublish_all_orphan_items` | read 2026-11-12 |
| [`kevchant/GitHub-fabric-cicd-sample`](https://github.com/kevchant/GitHub-fabric-cicd-sample/tree/49e3ac1f0b357df12daef1fe861728b951266012) | GitHub Actions equivalent; same wrapper; no licence file, no `.gitignore` | read 2026-11-12 |
| [`kevchant/AzureDevOps-AutomateFabricDeploymentPipeline`](https://github.com/kevchant/AzureDevOps-AutomateFabricDeploymentPipeline/tree/90cee6d7834fcce18dc0c38f606d6f9660ce2813) | Native deployment-pipeline `deploy` call; error-swallowing `catch` | read 2026-11-12 |
| [`alisonpezzott/fabricopsflow`](https://github.com/alisonpezzott/fabricopsflow/tree/3d7f3595c8beec69abc45dd3314ef91f119c13a7) | Variable-Library-as-environment, git-diff selective deploy, alphabetical ordering | read 2026-11-12 |
| [`kerski/fabric-dataops-patterns`](https://github.com/kerski/fabric-dataops-patterns/tree/6ec433bb7dbe1dcebe26cf29dc34658cd627a810) | `FabricPS-PBIP` import, model-before-report read-back, DAX test assertions | read 2026-11-12 |
| [`michaeldeongreen/microsoft-fabric-sdlc-patterns`](https://github.com/michaeldeongreen/microsoft-fabric-sdlc-patterns/tree/188f0339c07aa792ee836b80174cd1cb6cc4c292) | Three selectable mechanisms, phased publish, `DeploymentPlan`, PR gates | read 2026-11-12 |
| [`gronnerup/FabricOps`](https://github.com/gronnerup/FabricOps/tree/e2d34a23204c0d97746a93f4ca1eaa4615c31d44) | Recipe→plan engine, export-and-hash drift check, dacpac deploy, offline tests | read 2026-11-12 |
| [`EvaluationContext/fabric-cicd-example`](https://github.com/EvaluationContext/fabric-cicd-example/tree/3f04b2898dfe9f92eb90fb021057ce278464a83d) | WIF auth, `fab deploy` config, approval-with-plan, feature workspace lifecycle | read 2026-11-12 |
| [`chantifiedlens/deploy-microsoft-fabric-items`](https://github.com/chantifiedlens/deploy-microsoft-fabric-items/tree/8cb718586e190f8a52d9132ef3553c4064946bbe) | Composite action; secret as input; unreferenced token output | read 2026-11-12 |
| [`FabricDevCamp/fabric-cicd-whitepaper`](https://github.com/FabricDevCamp/fabric-cicd-whitepaper/tree/402c5f7eb4ef4c0725b0a5be4949f7eff1d66029) | Community rationale for feature workspaces, post-deploy/post-sync jobs, deployment-pipeline limits (community opinion) | read 2026-11-12 |
| [`edkreuk/FMD_FRAMEWORK`](https://github.com/edkreuk/FMD_FRAMEWORK/tree/1ff1684f001af54a8722d331078a52a0196abeb8) | Notebook-driven deploy, committed `.dacpac` + guard job, tenant GUIDs in config | read 2026-11-12 |
| [`bennyaustin/fabric-accelerator`](https://github.com/bennyaustin/fabric-accelerator/tree/00b7252adb61e4ff2c72c9f5f457165764ae1bc0) | Control plane via `fab`, per-item REST loop, `OLD_*`/`NEW_*` substitution, dacpac | read 2026-11-12 |
| [`calvinchengx/fabric-emulator`](https://github.com/calvinchengx/fabric-emulator/tree/af3278c862812f83c8a434c043ee3508a628fc57) | Running the real `fabric-cicd` offline as a test | read 2026-11-12 |
| [`microsoft/fabric-cicd` @ v1.4.0](https://github.com/microsoft/fabric-cicd/tree/59a0fe8612dd90cd7d7c2021ee6bad71b08cf477) | `SERIAL_ITEM_PUBLISH_ORDER`, full-deployment philosophy, selective-deploy warning, `$items` resolution, no CLI entry point | read 2026-11-12 |
| [`microsoft/fabric-terraform-quickstart`](https://github.com/microsoft/fabric-terraform-quickstart/tree/46b2158750340c8a13b7797e171da4b38b4aec2c) | Control-plane-only pattern; capacity `postcondition`; no item deploy | read 2026-11-12 |
| [`microsoft/fabric-cli`](https://github.com/microsoft/fabric-cli) | Named only for `fab deploy` / `fab auth login --federated-token` as used and documented by `EvaluationContext`; not read directly | not read |
| [GitHub REST API `/repos/{owner}/{repo}`](https://docs.github.com/en/rest/repos/repos) | Licence, last push, archived status for all fifteen | queried 2026-11-12 |

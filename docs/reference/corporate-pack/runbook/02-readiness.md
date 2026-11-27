# Runbook 02 — Readiness

**Illustrative · Pack: 2026-11-27.1 · dated 2026-11-26 · not runnable from `fabric-ops` (ADR 0001).**

The gate before the first pipeline run. Every row is answered by an artefact — a file in the
corporate repo or an output of the `Probe` stage — and by nothing else. A row that cannot be
answered that way is not a readiness row: it is a VERIFY in
[`../spec/0003-open-questions.md`](../spec/0003-open-questions.md) or out of scope. Do not ask the
pack's authors; there is no return channel ([`../README.md`](../README.md)).

Run this after the scaffold ([01-first-run](01-first-run.md) step 0), after
[00-bootstrap](00-bootstrap.md)'s verifies pass, and after one `Probe` run exists.
[01-first-run](01-first-run.md) describes what happens once every row is green.

## What you need open

1. The corporate repo as it will run: `terraform/`, `pipelines/`, `config/`, `scripts/`.
2. The `Probe` run's `probe.json` — the artifact if it was published, otherwise the same lines in
   the job log.
3. The bootstrap record: dated lines for the human steps.

## Repository

| Check | How to see it | Pass looks like | If it fails |
| --- | --- | --- | --- |
| **R0 — the scaffold ran and left no template.** | `find . -name '*.tmpl'` at the corporate repo root; `ls config/domains.yaml checks/known-good/README.md`; the scaffold's own summary line. | The `find` prints nothing; `config/domains.yaml` is present and opens with a `domains:` list; `scripts/report.sh` and `checks/known-good/README.md` exist (both are copied by the scaffold). | Stop and re-scaffold into a clean path from a fresh checkout of the pack: `bash scaffold.sh.tmpl --target <path>`. Running it against the corporate repo it already seeded is refused, because `terraform/` exists. A surviving `.tmpl` means the real filename is missing, so the stage that reads it fails one step later with a path error that looks like a config error. |
| **R1 — no placeholder survives into an apply.** No `PLACEHOLDER`, no all-zero GUID in the committed tfvars or the pipeline. | `python3 scripts/preflight.py --root <root> <tfvars>` for every tfvars file the run will use; `grep -rn 'PLACEHOLDER\|00000000-0000-0000-0000-000000000000' $(find terraform -name '*.tfvars') pipelines` (scope it to the tfvars and `pipelines/`; the spec and this runbook keep placeholders on purpose). Skip `terraform/domains/env/domains.tfvars` when `createDomains=false` and `terraform/domain-assignments/env/<domain>.tfvars` when `assignDomains=false` — those roots do not run. | Every file prints `PASS preflight … findings=0`; the grep prints nothing. The guard constants are **not** placeholders and must not be flagged or "fixed": `createDomains=false`, `assignDomains=false`, `fabric_administrator_confirmed=false`, `bind_git=false` in prod. | Stop. Preflight names the path; the owner is the row it came from in [00-bootstrap §Placeholders](00-bootstrap.md#placeholders). Copy the value; never invent one. |
| **R2 — `config/domains.yaml` names equal `parameters.domains` and the `parameters.matrix` keys**, and `parameters.createDomains` is the intended branch. | The Build log line `domain matrix parity OK for <n> domain(s): …`; the five parameters in `pipelines/cicd.yml` (`domains`, `matrix`, `environment`, `createDomains`, `assignDomains`); the YAML itself. `environment` is an inert label. | Same names, same count, no duplicates; every `repo:` is `fabric-<name>-nonprod`; `createDomains` is `true` only with `PROBE-ADMIN` 200. | Build fails, so nothing after it runs. Add the row to all three places; a name in one place only is the failure this row exists to catch. |
| **R3 — one repository per nonprod workspace**, named exactly. | Project → Repos, beside the `repo:` column of `config/domains.yaml`. | One repository per domain row, `fabric-<domain>-nonprod`, default branch `main`. No prod repository: prod is never bound (`../forbid.md` rule 8). | Stop for that domain. A human creates it from the template ([00-bootstrap](00-bootstrap.md) §11); the pipeline only binds. |
| **R4 — `checks/known-good/` holds no baseline on the first run, and that is expected.** | `ls checks/known-good`; the first run's `assert_plan` lines `BASELINE-MISSING root=… phase=… counts=…`. | Only `README.md` is present — the scaffold copies it; no `<phase>.json` for any root; one `BASELINE-MISSING` line per root and phase; rules 1–4 and 6 still fail closed (contract §7). | A `<phase>.json` present before the first run has no provenance: stop and find who added it. Never create one to quiet a count; a human records the counts after a clean run, in its own reviewed change. |
| **R5 — the copied pipeline keeps the stage graph.** | Read the `stages:` block of `pipelines/cicd.yml`; search for `environment:` and `createDomains`/`assignDomains`. | `Build` → `Probe` → `Platform` → `Nonprod` → `PlanProd` → `Guard` → `Prod_<domain>`; `environment:` only where contract §6 puts it; `PlanProd` and `Guard` have none; Platform and Nonprod carry an environment but **no Approvals check**; `isSkippable: false` on every prod stage; both domain flags default `false`. | Stop before queueing. The gate is the `environment:` line; a missing one deploys ungated and silently. |
| **R6 — the report path exists.** | `ls scripts/report.sh`; run `scripts/report.sh --help`. | Present and executable; it names the archive it writes. | Stop. `report.sh` is the only thing a person carries out of the tenant; without it a stop leaves as "it did not work". Re-run the scaffold, or copy `skeletons/scripts/report.sh.tmpl` and drop the suffix. |
| **R7 — content and its parameter file are per domain.** | `find content -maxdepth 2 -type d`; `ls config/parameter.<domain>.yml` for every domain. | Each domain has `content/<domain>/` and `config/parameter.<domain>.yml`; Build bundles that tree only. | Stop for that domain. `deploy_items.py` refuses a path that does not carry the domain (`CONTENT-SCOPE`); fix the path, never widen the script's check. |

## Tenant prerequisites — read `probe.json`, not the portal

| Check | How to see it | Pass looks like | If it fails |
| --- | --- | --- | --- |
| **P1 — AUTH, FABRIC and PROVIDER green.** | The `Probe` run's `probe.json` (artifact or log). `PROBE-AUTH` = ARM token and `az account show`; `PROBE-FABRIC` = `GET /v1/capacities`; `PROBE-PROVIDER` = `Microsoft.Fabric` registration. | Three green; the capacity call returns a readable list (empty is correct before Platform has created them); provider `Registered`. | Stop. Each code has its entry in [troubleshooting](troubleshooting.md); fix the tenant setting, re-run `Probe`. A cached token can repeat the old answer for minutes to an hour. |
| **P2 — DOMAINS and GRAPH green where the run uses them.** | Same `probe.json`: `PROBE-DOMAINS` = `GET /v1/domains`; `PROBE-GRAPH` = `GET /groups?$top=1`. GRAPH is used while the workspaces root creates groups (the default); DOMAINS while a Terraform domain root (or its job) is enabled. | Both green. | Stop while that path exists. If the pipeline no longer creates groups or no longer has a domains or assign job, delete the probe with the job in the same change — a probe you ignore is a stage you will ignore. |
| **P3 — `PROBE-ADMIN` is 403 on the portal path, or 200 with both Terraform roots enabled.** | The status for `GET /v1/admin/domains` in `probe.json`; `createDomains`, `assignDomains` and `fabric_administrator_confirmed` in the pipeline and `terraform/domains/env/domains.tfvars`. | 403 + `createDomains=false` + `assignDomains=false` + the `domains` and `assign` jobs skipped; or 200 + `createDomains=true` + `assignDomains=true` + `fabric_administrator_confirmed = true`. | 401/5xx is not information: fix the token and re-run. 200 with the flags false does not license enabling them later without a change. 403 with either flag true is stop condition 4. |

## People

| Check | How to see it | Pass looks like | If it fails |
| --- | --- | --- | --- |
| **H1 — three ADO environments exist with the approvals described.** | Pipelines → Environments: the names, then each one's **Approvals and checks**. | Exactly `fabric-platform`, `fabric-nonprod`, `fabric-prod`. On `fabric-prod`: Approvals with two named humans, instructions, a Timeout, self-approval off; Branch control `refs/heads/main`; Exclusive lock on all three; pipeline permissions restricted to this pipeline. | Stop. A typo creates a new environment that gates nothing; create the right one and re-point the stage. Prove it with the comment-only run in [00-bootstrap](00-bootstrap.md) §7: pause, reject, stage fails. |
| **H2 — approvers are named, and the author of the first run is not one.** | `fabric-prod` → Approvals; the rehearsal's Approval record (`approver`, `createdOn`, `minRequiredApprovers`). | Two named humans, roster written down in the corporate repo, neither is the person who will queue the first prod run. | Stop. A one-name roster, or the author on it, is no gate for that run. Approval is a human act; no agent may stand in (`../agents/AGENTS.md`). |
| **H3 — the human-only facts are dated with a name in the corporate repo.** | The corporate repo's own bootstrap record. `spec/0003-open-questions.md` rows stay VERIFY and are not this record. | Dated lines with an observer: the Fabric-administrator proof (§1), the Graph consent (§5), the agent pool's smoke job (§10), the Fabric Git connection (§11), the prod-approval rehearsal (§7), and — after the first apply — the domain assignment, the per-domain parameter file and the overage setting (§14). | Stop. An undated "done" is not a fact (`../forbid.md` rule 9); the probe finds it one stage later, where it costs more. |

## Stop conditions

Stop the run — do not queue it, do not retry it — when any of these is true:

1. **Any `Probe` code is red.** `PROBE-ADMIN` 403 is *not* red: it keeps domains and assignments on
   the portal path. An ADMIN 401/5xx is red.
2. **Any placeholder survives** in the committed tfvars or `pipelines/` — a `PLACEHOLDER` or an
   all-zero GUID on a path that reaches a plan.
3. **Any domain row has no repository** named `fabric-<domain>-nonprod`.
4. **`createDomains=true` or `assignDomains=true` without `PROBE-ADMIN` 200** in the same
   `probe.json`.

A failed row in the tables above stops the run too; these four are the ones a weak model argues past.

## What this page proves, and what it does not

It proves the run can start: the repo is filled in, the Probe found the tenant prerequisites, the
gates and their humans exist. It does **not** prove capacity sizing or overage, viewer licences,
that an approver is awake, or any tenant setting the design deliberately never reads — those are
assumptions, absorbed in [`../spec/0004-assumptions.md`](../spec/0004-assumptions.md), not gates.

If a row fails and cannot be fixed here, carry the four facts from [`../README.md`](../README.md):
stage, run id, error code, failing address or state key.

# What does Azure DevOps actually provide for this pipeline, and where are its sharp edges?

- **Status:** answered
- **Checked:** 2026-11-12
- **Blocks:** the ADO-side configuration of the work repo's pipeline (ADR 0002)

## Short answer

One primitive does the identity work: an **Azure Resource Manager** service connection with the
**Workload identity federation** credential, which hands the job a short-lived assertion and stores no
secret. Everything else is generic ADO machinery, and its edges are quiet rather than loud: a stage with
no `environment:` has no approval and no error, a wrong federated subject fails only at token exchange,
and a stage behind a failed dependency reports "skipped", not "failed".

## Detail

### 1. Service connections

**There is no Fabric service connection type.** The list of default connection types (ms.date
2026-10-15) runs from Azure Classic to Visual Studio App Center — 25 entries including Azure DevOps,
Azure Resource Manager, Generic, Jenkins, Kubernetes, SSH — with no Fabric, Power BI or Microsoft 365
entry. People look for a "Microsoft Fabric", "Power BI" or workspace-scoped connection, or for the
**Azure DevOps** type, which is real but connects *to Azure DevOps* (PAT-free repo and feed access), not
to Fabric. The correct choice is **Azure Resource Manager**.

That type offers three credentials. **Workload identity federation** is recommended — "App registration
(automatic)", "Managed identity", or "App registration or managed identity (manual)" — because it
"eliminates the need for secrets and secret management". A **service principal key** survives in the
manual and legacy-automatic flows, "for backwards compatibility and edge cases and not recommended". A
**certificate** appears only in the ADO **Server 2022** manual flow, where the field is `Credential` =
`Service Principal Key` | `Certificate`; the Services federation flows do not offer it.

Manual creation, the reliable route when ADO may not create the app: create the app registration; create
the connection as "App registration or managed identity (manual)" + "Workload identity federation"; copy
the generated **Issuer** and **Subject identifier**; **Keep as draft**; in Entra go **Certificates &
secrets > Federated credentials > Add credentials > Other issuer**, `Type` = *Explicit subject
identifier*, paste both, save; back in ADO **Finish setup > Verify and save**. The order is forced:
"the federated credential can only be created after the service connection is created".

- Entra issuer (new connections, default): `https://login.microsoftonline.com/<tenant id>/v2.0`, subject
  `<microsoft entra prefix>/sc/<organization id>/<service connection id>`.
- Azure DevOps issuer (deprecated, retires 2027-07-01): `https://vstoken.dev.azure.com/<org id>`, subject
  `sc://<organization name>/<project name>/<service connection name>`.

Entra matches `issuer` and `subject` against the token's `iss` and `sub`; `audiences` takes a single
value, recommended `api://AzureADTokenExchange`. No wildcards; 20 credentials maximum per app.

What the pipeline receives: `addSpnToEnvironment: true` on `AzureCLI@2` "adds the service principal ID,
service principal key or workload identity federation token, and tenant ID … You can use the
`servicePrincipalId`, `servicePrincipalKey` or `idToken`, and `tenantId` variables", honoured "only when
the Azure endpoint has service principal authentication scheme or workload identity federation
authentication scheme". The inputs that matter are `azureSubscription` (alias
`connectedServiceNameARM`), `scriptType`, `scriptLocation`, `inlineScript`/`scriptPath` and
`addSpnToEnvironment` (default `false`). Two standing hazards: connections "have standing access to the
services they connect to", and ADO "might automatically disable connections that you didn't use for 100
days". `Grant access permission to all pipelines` "isn't recommended".

### 2. Approvals and checks

Checks attach to **resources, never to YAML**: "Approvals and other checks aren't defined in the yaml
file. Users modifying the pipeline yaml file can't modify the checks performed before start of a stage."
Eligible resources are environments, service connections, repositories, variable groups, secure files and
agent pools, evaluated in order: static checks (Branch control, Required template, Evaluate artifact),
pre-check approvals, dynamic checks (Approval, Invoke Azure Function, Invoke REST API, Business Hours,
Query Azure Monitor alerts), post-check approvals, Exclusive lock.

**A per-stage approval is an environment approval.** An **Approvals** check on
`fabric-sales-forecast-prod` gates the stage whose deployment job targets that environment, and only
that one; a stage that lost its `environment:` is never gated and never complains. Settings are
**Approvers**, **instructions for the approvers**, "permit or restrict approvers from approving their own
runs", and **Timeout**. The trap: "If approvals aren't completed within the specified Timeout, the stage
is marked as skipped." The approver list is frozen at check start. A rejection is final ("A single final
negative decision causes the pipeline to be denied access and the stage to fail"); Branch control fails a
stage and needs `refs/heads/<branch name>` fully qualified; Business Hours *fails* rather than skips;
Exclusive lock is opt-in via `lockBehavior` = `runLatest` (default) | `sequential`.

The record is the `Approval` object — `status`, `createdOn`, `lastModifiedOn`, `minRequiredApprovers`,
`instructions`, `blockedApprovers`, and `steps[]` with `assignedApprover`, `actualApprover`, `comment`,
`initiatedOn`, `lastModifiedOn`, `history`. Who and when are there; **what ran is not** — that is the run
and the environment's **Deployments** history, which is why the run link is the audit trail.

### 3. Identity in the pipeline

`$idToken` is a token for the Entra audience `api://AzureADTokenExchange`; each tool exchanges it for a
token for *its own* resource, so one connection can serve Terraform, the CLI and fabric-cicd — but the
access tokens are not interchangeable, and an ARM token is useless to Fabric.

- **Azure CLI**: nothing extra; `AzureCLI@2` logs in itself. Needs Azure CLI **2.30 or later**, or the
  agent fails with `unrecognized arguments: --federated-token`.
- **Terraform**: `ARM_USE_OIDC=true`, `ARM_CLIENT_ID=$servicePrincipalId`, `ARM_TENANT_ID=$tenantId`,
  `ARM_OIDC_TOKEN=$idToken` — azurerm provider inputs documented by **HashiCorp, not Microsoft**, so
  outside this note's permitted sources and unverified here.
- **Python SDK**: an `azure-identity` credential built from the same three values, then a token for
  `https://api.fabric.microsoft.com/.default`.

The assertion expires before long jobs finish: `AADSTS700024: Client assertion is not within its valid
time range` "if the error happens after approximately 1 hour". Re-acquire per long step.

### 4. Agent requirements

The 4.x Linux agent is .NET 8 based, supported on Debian 12, Ubuntu 20.04/22.04/24.04, RHEL 8/9, Oracle
Linux 8/9, Fedora 39/40, openSUSE 15.5/15.6, SUSE 15.5, Azure Linux 2.0 and Alpine 3.17–3.20, and needs
**Git 2.9.0 or higher**; `./bin/installdependencies.sh` covers the rest. The image must also carry
**azure CLI ≥ 2.30** ("if you are using private agents, install Azure CLI on the computer(s) that run the
build and release agent"), **terraform** and **python3 + pip**.

There is **no built-in Terraform tool installer** in the task reference's Tool tasks, which do include
`UsePythonVersion@0`, `NodeTool@0`, `GoTool@0`, `JavaToolInstaller@1`, `KubectlInstaller@0`,
`HelmInstaller@1`, `DockerInstaller@0`. So Terraform is baked into the image or installed by script; for
a stable pool, bake it. Capabilities are snapshotted: "After you install new software on an agent, you
must restart the agent for the new capability to show up."

Network, per the Linux-agent firewall FAQ: `https://dev.azure.com`, `https://*.dev.azure.com`,
`https://login.microsoftonline.com` ("Microsoft Entra sign-in"), `https://management.core.windows.net`
("Azure Management APIs") and `https://download.agent.dev.azure.com`, on port 443, plus port 22 only for
SSH git. Proxy is set at configuration (`--proxyurl`, `--proxyusername`, `--proxypassword`,
`--usebasicauthforproxy`) with a `.proxybypass` file of ECMAScript regexes — but "many tools do not
automatically use the agent configured proxy settings … `curl` and `dotnet` may require proxy environment
variables such as `http_proxy`". Terraform and pip are in that category.

### 5. Secrets

Variable groups share values across pipelines; secret variables are "encrypted at rest with a 2048-bit
RSA key", are not auto-exported as environment variables, and must be mapped per task. Masking is
best-effort: "We make an effort to mask secrets … We never mask substrings of secrets. If, for example,
"abc123" is set as a secret, "abc" isn't masked" — hence "secrets should not contain structured data". A
Key Vault–linked group maps "only the secret names … not the secret values", fetches at run time, supports
secrets only, and rejects RBAC vaults behind private endpoints.

Nothing here needs to be a secret, and that is achievable: both identities are federated, Terraform
reaches state with `ARM_USE_OIDC` (avoid `ARM_ACCESS_KEY`; grant the SP a data-plane role), and
fabric-cicd uses the same assertion. Conditional on every external system the pipeline touches being
Entra-authenticated; a non-Azure dependency reintroduces a secret, and a variable group or Key Vault link.

### 6. Pipeline structure

A **deployment job** targets an `environment`, records deployment history and applies a strategy —
`runOnce`, `rolling`, `canary`, with `rolling` VM-only. `runOnce` fits here: one target, no traffic to
shift. A deployment job "doesn't automatically clone the source repo … use `checkout: self`", and the
Download Artifact task "is auto injected only in the `deploy` hook" (suppress with `download: none`).

Stages run in declared order unless `dependsOn` says otherwise; `dependsOn: []` runs in parallel and a
list fans in. A custom `condition` "remove[s] the conditions for completion and success", so write
`and(succeeded(), …)` unless you mean otherwise. `trigger: manual` makes a stage manually startable;
`isSkippable: false` removes it from **Stages to run**.

To promote identical bytes: publish once in `Build` (`- publish:` or `PublishPipelineArtifact@1` with
`targetPath`, `artifactName`), then `download: current` + `artifact:` per deploy stage, landing at
`$(Pipeline.Workspace)/<artifact name>`. No deploy stage rebuilds; the artifact belongs to the run, so
every stage consumes the same content, and deleting the run deletes it.

### 7. Failure and recovery

A completed run offers **Run new**; a stage whose checks timed out can be retried ("You can retry a stage
when approvals and checks time out"), and on a rolling deployment a retry "re-runs the deployment on all
VMs not just failed targets". Every stage execution re-evaluates its checks, so expect a fresh approval.

**There is no rollback.** ADO supplies a place to put one — `on: failure` under the strategy, "used to run
steps for rollback actions or clean-up" — and nothing more. The alternatives are to revert the commit and
re-run (Terraform state records what exists) or to redeploy the previous run's artifact with
`DownloadPipelineArtifact@2` (`buildType: specific`, `pipelineId`, `buildVersionToDownload: specific`).
Neither undoes a Fabric item deletion; fabric-cicd orphan removal is one-way.

Retention is project-level only — "Azure DevOps no longer supports per-pipeline retention rules" — and
deleting a run removes "Logs, All pipeline and build artifacts, … Run metadata". Critically, "Retention
policy retains only the succeeded and partially-succeeded runs", so a failed prod run is not protected by
the recent-runs count.

## Sharp edges, with the symptom

| Symptom | Mechanism | Response |
| --- | --- | --- |
| A stage is **skipped**; the run looks nearly green | Default stage condition needs every `dependsOn` stage to succeed; an approval **timeout** also marks the stage skipped, not failed | Read skipped as "did not run"; add `failed()`/`always()` stages only deliberately; `isSkippable: false` on guards |
| Prod deploys with no approval after a refactor | The gate is on the environment, and a stage that lost `environment:` (or points at a new auto-created one) has no checks; environment names cannot be variables | Diff `environment:` per stage; restrict each environment's pipeline permissions so an unknown one fails loudly |
| `AADSTS700213` / `AADSTS70021: No matching federated identity record found` | Subject binds org/project/connection names or IDs, so a rename or copied connection breaks it, and "the error does not become apparent until the token exchange fails" | Keep connection names stable, recopy Issuer and Subject after renames, track the issuer migration |
| Contributors can change what prod runs | Default permissions grant Contributors **Create build pipeline** and **Delete or edit build pipeline**, so YAML can use any connection the pipeline is authorised for | Deny *Edit build pipeline* to Contributors; authorise connections per pipeline |
| `az` works; `terraform` and `pip` cannot reach the network | Agent proxy settings are not exported to third-party tools | Export `http_proxy`/`https_proxy`/`no_proxy` in the image or job |
| Auth failures an hour into a long job | `AADSTS700024`: the assertion, not the access token, expired | Re-authenticate per long step; give a long `apply` its own job |

## What this settles

Minimum ADO configuration for this design:

- [ ] One project, Azure Repos repo, self-hosted Linux pool (`pool: { name: fabric-self-hosted }`).
- [ ] Two **Azure Resource Manager** connections, `sc-fabric-deploy` and `sc-fabric-admin`, credential
      **Workload identity federation**, one **Explicit subject identifier** federated credential each,
      pipeline permissions restricted.
- [ ] One **environment per deployed stage** (`fabric-sales-forecast-dev|test|prod`), each with an
      **Approvals** check (approvers, instructions, Timeout, self-approval rule); **Branch control**
      (`refs/heads/main`) on prod; **Exclusive lock** with `lockBehavior: sequential` if runs must not
      overlap.
- [ ] Agent image with terraform, python3 + pip, az CLI ≥ 2.30, git ≥ 2.9.0; proxy at `config.sh` time
      *and* `http_proxy`/`https_proxy` exported; egress to `dev.azure.com`, `login.microsoftonline.com`,
      `management.core.windows.net`, `download.agent.dev.azure.com`.
- [ ] `Build` stage with no connection and no backend, then `runOnce` deployment jobs per environment
      chained by `dependsOn`, each `checkout: self`; artifacts published once in `Build`.
- [ ] No variable group, no Key Vault link, no secret variable — with a comment saying why.
- [ ] Project retention reviewed, knowing failed runs are not counted.
- [ ] Pipeline permissions tightened on the release pipeline, not only on the connections.

The three settings most likely to be missed:

1. **The approval Timeout on the environment** — expiry marks the stage *skipped*, which reads as "not
   deployed yet", so nobody investigates.
2. **Per-pipeline permission on each service connection** — "grant access to all pipelines" hands every
   pipeline the same standing access.
3. **Project retention** — a failed prod run's logs, metadata and artifacts can expire before the
   post-mortem.

## What this does not establish

- Whether retrying a *stage* (rather than a new run) re-requests an approval. Checks re-evaluate per stage
  execution, so it should; no Learn page states it.
- Any retention period specific to approval records; only the run's retention is documented.
- `ARM_USE_OIDC`/`ARM_OIDC_TOKEN` — HashiCorp documentation, named but not vouched for.
- Whether environment auto-creation still grants the creating user Administrator on every current path.
- Whether az CLI 2.30 is the current effective floor or only the version named in troubleshooting.
- Anything observed in a real organisation: nothing here was executed.

## Sources

| Source | Used for |
| --- | --- |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints (2026-10-15) | Default connection types (no Fabric), standing access, 100-day disable, grant-to-all |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure (2026-08-18) | WIF options, recommended vs legacy credentials, Server 2022 `Service Principal Key`/`Certificate` |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/release/configure-workload-identity and .../troubleshoot-workload-identity (2026-08-18, 2026-04-22) | Setup order, `Issuer`/`Subject identifier`, `Other issuer` + `Explicit subject identifier`, subject formats, AADSTS codes, 2.30 floor |
| https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust (2024-12-13) | issuer/subject matching, `api://AzureADTokenExchange`, no wildcards, silent misconfiguration |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/azure-cli-v2 (2026-09-23) | Input names, `addSpnToEnvironment`, exposed variables, private-agent CLI prerequisite |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals (2024-08-29) | Checks not in YAML, evaluation order, Timeout→skipped, frozen approvers, lock, branch format |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments (2026-06-17) | Environment as the approval carrier, roles, pipeline permissions, auto-creation failure |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/process/stages (2025-03-28) | `dependsOn`, default success condition, `trigger: manual`, `isSkippable` |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/process/deployment-jobs (2025-07-17) | `runOnce`/`rolling`/`canary`, `on: failure`, auto-download, retry-all-targets |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/artifacts/pipeline-artifacts (2021-08-30) | `publish`, `download: current`, `$(Pipeline.Workspace)`, download-by-run |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/process/variables (2026-03-04) | Secret encryption, no env auto-mapping, "never mask substrings" |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups and .../link-variable-groups-to-key-vaults (2024-08-15, 2025-09-10) | Variable groups, per-pipeline authorization, names-only Key Vault mapping, secrets-only |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/agents and .../linux-agent and .../proxy (2026-08-18, 2025-11-07, 2025-09-08) | Self-hosted model, distros, Git 2.9.0, firewall table, `--proxy*`, `.proxybypass` |
| https://learn.microsoft.com/en-us/azure/devops/organizations/security/allow-list-ip-url (2026-02-10) | `dev.azure.com`, `login.microsoftonline.com`, `management.core.windows.net`, ports |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/ (2026-10-28) | No Terraform installer; names of the installers that exist |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/policies/permissions (2025-12-22) | Default Contributor pipeline permissions; environment and library roles |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/policies/retention (2026-03-30) | Project-only retention, what deletion removes, succeeded-only counting |
| https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/approvals/get (2025-03-18) | Approval record fields |
| https://learn.microsoft.com/en-us/azure/devops/pipelines/create-first-pipeline (2026-03-10) | "Run new" for a completed run |

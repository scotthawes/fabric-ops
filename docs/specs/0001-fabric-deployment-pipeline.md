# Spec 0001 — Fabric deployment pipeline for the work repo

- **Status:** draft — seams need confirming before tickets
- **Date:** 2026-11-12
- **Derived from:** [recommendations](../recommendations/), [ADRs 0002–0006](../adr/), and the six research notes
- **Builds in:** the work repo (Azure Repos, same ADO organisation) — **not** this repository, per [ADR 0001](../adr/0001-research-artefact-not-deployment-tool.md)

Vocabulary is the project glossary: [work repo](../GLOSSARY.md), workspace, item, capacity, deployment.

## Problem Statement

Fabric content and access are managed by hand in the portal. That means:

- nothing is reviewable before it reaches production, and there is no record of what changed;
- the same solution is rebuilt in each environment by hand, so dev and prod drift silently;
- granting access is a per-workspace, per-person activity with no audit, so nobody can answer
  "who can see this data" without clicking through every workspace;
- provisioning a new environment takes days of portal work that nobody can repeat the same way,
  and the one thing that is repeatable — the capacity — is an Azure resource managed outside any
  pipeline.

The team cannot promote a change from dev to prod in a way that is tested, approved, auditable
and repeatable.

## Solution

A work repository that holds both the containers and the content as code, and an Azure DevOps
YAML pipeline that deploys them environment by environment:

- **Terraform** owns the control plane: the Fabric capacity (Azure resource), workspaces, role
  assignments and workspace-level settings.
- **`fabric-cicd`** owns the content: item definitions committed from the dev workspace.
- **Three environments** — dev, test, prod — deployed by the same pipeline, with a human approval
  before prod and the promoted artefact pinned to a commit SHA.
- **Group-based access**, one Entra security group per workspace, so offboarding happens in one
  place.
- **Two federated service principals**, one that deploys and one that administers, so a content
  deployment cannot grant access.

The observable outcome: merging a pull request can put a reviewed notebook, report or pipeline
into any environment, and the resulting state can be verified and audited without opening the
portal.

## User Stories

1. As a platform engineer, I want the Fabric capacity created from code, so that a rebuild is a
   pipeline run rather than a portal session.
2. As a platform engineer, I want capacities per environment expressible as configuration even
   though only one exists today, so that splitting later is a variable change rather than a
   rewrite.
3. As a platform engineer, I want workspaces created and assigned to a capacity by the pipeline,
   so that a new environment does not require manual setup.
4. As a platform engineer, I want workspace creation to fail loudly when the capacity is paused
   or unassigned, so that I do not chase a permissions error that is really a capacity state.
5. As a data engineer, I want to deploy a notebook, data pipeline and semantic model by merging a
   pull request, so that I stop hand-rebuilding solutions in each environment.
6. As a data engineer, I want to know before I start which item types the pipeline cannot deploy,
   so that I do not promise a dashboard or an ML model through CI/CD.
7. As a data engineer, I want my dev workspace connected to Git, so that I keep the browser tools
   and still get review.
8. As a data engineer, I want my commits to appear as a pull request, so that someone reads the
   change before it reaches test.
9. As a data engineer, I want per-environment values substituted at deploy time, so that a
   notebook that reads a lakehouse reads the right one in each environment.
10. As a data engineer, I want a typo in an environment key to fail the deployment, so that prod
    never silently points at dev data.
11. As a data engineer, I want deploying an unchanged branch to be harmless, so that re-running a
    failed pipeline is safe.
12. As a data engineer, I want the whole solution deployed in one run, so that I do not assemble
    the order myself.
13. As a data engineer, I want the pipeline to deploy containers before content, so that items do
    not fail against a workspace that does not exist yet.
14. As a data engineer, I want warehouse and lakehouse schema changes handled as their own step,
    so that a "successful" deploy does not leave an empty warehouse behind.
15. As a reviewer, I want every prod deployment to require an explicit approval, so that a bad
    merge cannot reach production unreviewed.
16. As a reviewer, I want prod to deploy the artefact that was tested, not a rebuild of it, so
    that what was approved is what runs.
17. As a reviewer, I want the pipeline to report which commit, which environment and which items
    it touched, so that an incident has a starting point.
18. As a data engineer, I want an edit made directly in test or prod to be overwritten on the next
    deploy, and to know that is the rule, so that I do not lose work by surprise.
19. As a data engineer, I want the pipeline to tell me when a deployed item no longer matches the
    repository, so that drift is visible rather than discovered during an incident.
20. As a platform engineer, I want role assignments managed from code, so that access changes are
    reviewable.
21. As a platform engineer, I want workspace Admin granted only to named humans, so that group
    membership can never quietly become admin.
22. As a security reviewer, I want the deploy identity unable to grant access, so that a
    compromised pipeline cannot read production data.
23. As a security reviewer, I want no long-lived credentials on the agent VMs, so that a disk image
    or log leak is not a tenant compromise.
24. As a security reviewer, I want the administration identity used only from an approved stage, so
    that routine deployments do not carry tenant-wide rights.
25. As a security reviewer, I want a nightly report of who can see what, so that the answer is a
    query rather than an afternoon of clicking.
26. As a security reviewer, I want the report to include group membership from Entra, so that it
    names people rather than group object IDs.
27. As a security reviewer, I want to be told which workspaces have no admin, so that orphaned
    workspaces are found before someone discovers them by accident.
28. As a security reviewer, I want to know which access paths the report cannot see, so that I do
    not treat an incomplete report as authoritative.
29. As a capacity owner, I want utilisation and throttling visible without opening the portal, so
    that I can see a problem before a user reports it.
30. As a capacity owner, I want the overage threshold set deliberately rather than left at the
    default, so that a runaway workload does not bill at three times the rate.
31. As a capacity owner, I want a clear answer on whether production may be down out of hours, so
    that I know whether pausing the shared capacity is available as a saving.
32. As an operations engineer, I want a deployment to fail with a clear error when the capacity is
    paused or throttled, so that the failure is not diagnosed as a broken item.
33. As an operations engineer, I want the pipeline to resume a paused capacity before deploying,
    so that a maintenance pause does not block a release.
34. As an operations engineer, I want the first-environment run to be possible from a documented
    sequence, so that bootstrapping does not depend on who did it last time.
35. As an operations engineer, I want the deployment to be safe to run concurrently for different
    environments, so that dev and prod releases do not queue behind each other.
36. As a new joiner, I want access granted by group membership, so that I am productive on day one
    without a ticket per workspace.
37. As a leaver's manager, I want offboarding in Entra to end Fabric access, so that I do not need
    to know which workspaces exist.
38. As an auditor, I want to know who approved a prod deployment and what it contained, so that
    the change record is complete.
39. As an architect, I want the pipeline to refuse an item type it cannot deploy, so that a
    solution design that depends on an unsupported item fails early.
40. As an architect, I want the research constraints recorded next to the build, so that a future
    reader does not have to rediscover them.

## Implementation Decisions

**Modules and boundaries**

- One Terraform root for the Fabric control plane, with per-environment variable files and one
  state key per environment. Capacity (Azure-scope) is separable from Fabric-scope resources so
  that the differing provider and identity paths do not interleave.
- A deploy script that owns item deployment: it takes an environment, a content directory, a
  parameter file and a workspace selector, builds a credential from the pipeline's federated
  identity, and calls `fabric-cicd`. This is the single entry point for content — the pipeline
  does not reimplement any of it.
- A preflight check that validates the parameter file and the environment keys before anything
  touches the tenant, because unsubstituted values fail silently rather than loudly.
- A verification step that reads back one item definition, one role assignment and the capacity
  state after each deploy, because those are the three failures that actually occur.

**Contract: parameterisation**

- Environment values are substituted by `find_replace`, keyed by environment name. The
  environment key must match the pipeline stage's environment exactly; a mismatch is an error, not
  a silent no-op. No real IDs, connection strings or secrets are ever committed.

**Contract: identity**

- Two service principals, both federated through ADO service connections, neither holding a
  secret. `sp-fabric-deploy` is workspace Contributor only. `sp-fabric-admin` holds capacity
  Contributor, workspace Admin where it acts, and membership of the admin API security group, and
  is reachable only from an approved or scheduled stage.

**Contract: promotion**

- Merge to main deploys dev; test follows the same commit; prod requires approval on an ADO
  Environment. The artefact is the commit SHA. Only dev is bound to Git integration; test and prod
  accept changes solely from the pipeline.

**Contract: environment**

- Three environments, dev/test/prod, one workspace set each, all on one capacity today. The
  capacity is a variable, not a constant, so splitting it later is configuration.

**Constraints accepted from the research**

- Item types with no public create/update definition API cannot be deployed (SQL analytics
  endpoint, Dashboard, Scorecard, Datamart, MirroredWarehouse, ML model, ML experiment) and must
  be created by hand.
- `MirroredDatabase` and `Reflex` mark service-principal support as unsupported — not behind the
  deploy principal without a tenant test.
- Warehouse, SQL database and Lakehouse deploy as shells; schema and DDL are a separate step.
- Sensitivity labels are not deployed; they are applied in the workspace.
- No Azure Monitor metrics exist for the capacity, so alerting reads the Capacity Metrics app or
  Real-Time hub events.

## Testing Decisions

A good test here asserts **observable platform state**, not Terraform internals: after a run, does
the workspace exist with the intended capacity and role assignment, does the item's definition
match the repository, and is the capacity active? Tests that inspect HCL structure or mock the
Fabric API prove nothing about whether the deployment works.

- **Terraform:** `fmt -check` and `validate` in a credential-free build stage; `plan` against the
  environment before `apply` in the deploy stage, with the plan retained as an artefact.
- **Preflight:** the parameter file is checked for missing environment keys and unsubstituted
  placeholders, and fails the build rather than the deploy.
- **Post-deploy smoke assertions, per environment:** item definition round-trips to the committed
  value; the group's role assignment exists with the expected role; the capacity is `Active`; a
  known-good notebook is present.
- **Contract test for parameterisation:** a deliberately wrong environment key must fail. This is
  the single highest-value test in the system, because the failure it prevents is silent
  cross-environment data leakage.
- **Optional, for local iteration:** the community Fabric emulator can back a subset of these
  assertions without a tenant round trip. Treat it as a convenience seam, not a gate, until it has
  been proven against the real API for the item types in use.
- **No automated test for:** tenant settings, approval gates, licence behaviour or private
  networking. These are run-book checks with a human owner, recorded in the pack.

## Out of Scope

- Building or deploying anything from the research repository itself.
- Fabric's native deployment pipelines as a promotion mechanism — they never read the repository
  and cannot carry role assignments.
- Item types with no definition API, and any attempt to automate around their absence.
- Sensitivity-label deployment, OneLake security roles, SQL `GRANT` management.
- Provisioning the ADO organisation, agents, service connections or Entra groups from code.
- Capacity sizing decisions beyond expressing the SKU as a variable.
- Multi-tenant or cross-tenant deployment.

## Further Notes

**Seams — confirm before tickets.** Three seams are proposed, in preference order:

1. **Post-deploy assertions against the real tenant** (highest, fewest moving parts): every test
   reads platform state through the Fabric API after a deploy. Cost: needs a tenant and a
   credential; slow.
2. **The deploy script's CLI** (middle): its inputs and exit codes can be exercised without a
   tenant, with `fabric-cicd` stubbed, covering parameterisation and ordering.
3. **The parameter-file preflight** (lowest): pure function over a file, fastest, but proves only
   substitution.

Recommendation: 1 as the gate, 3 as the fast check, and skip 2 unless the deploy script grows
branches worth testing.

**Open risks carried from the pack.** Which network posture the tenant uses (run-book item 1) can
invalidate the agent placement; whether a service principal needs a Fabric licence is unverified;
whether an SP can hold capacity Contributor is unverified; a group containing only an SP satisfying
the admin API allow-lists is unverified.

**Revisit trigger.** If production is measurably throttled by non-production traffic twice, split
the capacity — the code is already shaped for it.

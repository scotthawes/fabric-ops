# 03 — Deployment and environments

**The decisions this supports:** [ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md),
[ADR 0004](../adr/0004-one-shared-capacity.md), [ADR 0005](../adr/0005-authoring-and-promotion.md).
**Evidence:** [deployment mechanism comparison](../research/deployment-mechanism-comparison.md).

## The shape

```
main (Azure Repos)
   │
   ├── merge ──► Build ────────────► validate, lint, plan
   │
   │             DeployDev ────────► terraform apply → fabric-cicd → dev workspaces
   │                │
   │             DeployTest ───────► same artefact, same steps → test workspaces
   │                │
   │             DeployProd ───────► manual approval → prod workspaces
   │
   └── dev workspace (Git integration, bound to a branch)
```

One capacity, three workspace sets, three stages. The artefact is the commit SHA; nothing is
rebuilt between stages, so what was approved in test is what lands in prod.

## Each stage, in order

1. **Terraform** — capacity (first run only, via `azurerm`), workspaces, role assignments, Git
   connection, terminal state. Containers before content, always: `fabric-cicd` assumes the
   workspace exists and fails obscurely if it does not.
2. **Item deployment** — `fabric-cicd` reads the definitions from `content/`, substitutes
   per-environment values from `parameter.yml`, and pushes every item. It is a full deploy,
   every run, with no commit diffing.
3. **Verification** — read back one item's definition and one role assignment, and assert the
   capacity is not paused. Three cheap calls that catch the three failures that actually
   happen: unapplied Terraform, overwritten content, dead capacity.

## Why not Fabric deployment pipelines

They never read the repository, and they do not copy role assignments. Either fact alone
disqualifies them as the promotion mechanism for a Git-first repo. They remain useful as a
*manual* tool for a one-off comparison between two workspaces — not as the path to production.

## Parameters and drift

- Per-environment values live in `parameter.yml` (`find_replace`, `$workspaces.*`), keyed by
  environment. Anything environment-specific — workspace IDs, lakehouse IDs, connection IDs —
  must be a parameter, because a hardcoded dev ID deployed to prod points prod at dev data.
- Because deployment is unconditional, a portal edit to a deployed item is **overwritten
  silently** rather than reported. Anything changed in `test` or `prod` is lost on the next run;
  say so to whoever has Contributor there.
- The `dev` workspace is the only one bound to Git. Its uncommitted changes are the authors'
  working state — deploying `dev` from the pipeline replaces them. Agree when that happens (on
  merge) and let authors know.

## The capacity is shared, so treat contention as normal

- A paused or throttled capacity is an expected failure, not an outage: the pipeline should fail
  with "capacity unavailable" rather than a wall of item-level 429s.
- Pausing is only safe when production may be down too (ADR 0004). Do not put pause/resume on a
  cron that ignores the environments living on that SKU.
- Long deployments consume capacity units themselves. On a small SKU, deploying three
  environments back to back is measurable load.

## What the pipeline cannot do

Connectivity is the part people assume is automated and is not — with one important exception now
established:

| Step | Verdict |
| --- | --- |
| Bind a semantic model to a gateway or cloud connection | **Automatable** — `bindConnection` with a `connectivityType`; caller must own the model |
| Create the gateway datasource | Partial — REST for on-premises gateways only, gateway-admin permission |
| Set and rotate datasource credentials | Manual |
| Add a principal to a gateway | PowerShell only (`Add-DataGatewayClusterUser`), accepts a service principal |
| Install, register and cluster a gateway | Manual — installer, recovery key |
| Approve a managed private endpoint | Manual — target owner's decision |
| Create the resource instance rule and workspace identity grant | Manual — ARM/PowerShell and Azure RBAC |
| Semantic-model RLS roles | Partial — XMLA read-write plus TMSL; a service principal can create roles but cannot be a role member |

Two consequences. A deployed model with no binding is healthy and fails at refresh, so binding is a
pipeline step to write rather than a relationship to tolerate. And the legacy Power BI API uses a
different token audience — so the pipeline needs a second credential path for the operations that
still live there.

Which route a given source needs — on-premises gateway, VNet gateway, managed private endpoint,
trusted workspace access, or a plain connection — is decided in
[`gateway-and-connectivity.md`](../research/gateway-and-connectivity.md). One consequence worth
knowing early: an on-premises gateway cannot register in a tenant with private link enabled, so
that combination is unavailable rather than merely awkward.

## Risks

- **Item-type coverage.** 23 item types survive all three gates — Git support, a public
  create/update definition API, and a `fabric-cicd` handler — and can be promised. Seven cannot
  be deployed by any route: **SQL analytics endpoint, Dashboard, Scorecard, Datamart,
  MirroredWarehouse, ML model, ML experiment**. Four more are API-only (Power BI Dataflow, Org
  app audience, Azure Databricks Storage, Mirrored catalog), so they can be created headlessly
  but never committed out of the Git-bound dev workspace. Full matrix:
  [item-type coverage](../research/item-type-deployment-coverage.md).
- **Two service-principal gaps.** `MirroredDatabase` and `Reflex` (Activator) are
  definition-deployable but mark service-principal support as unsupported. Do not put either
  behind the deploy principal without testing in the work tenant.
- **Shells, not schemas.** For Warehouse, SQL database and Lakehouse, `fabric-cicd` deploys the
  item shell only. Schema is a second stage in the same run — state-based for the warehouse,
  `dbt-fabricspark` for lakehouse tables ([ADR 0008](../adr/0008-schema-is-state-based.md)). A
  "deployed" warehouse can be empty and still look successful.
- **Provider support.** `microsoft/fabric` is outside Microsoft support. Keep the Terraform
  small enough that falling back to REST is an afternoon, not a project.
- **First-run ordering.** Capacity creation is subscription-scope Azure, the rest is Fabric-scope.
  Different provider, different identity path; do it once by hand or in its own pipeline rather
  than interleaving with content deployment.
- **Network path.** Unresolved, and it is the one open item that can change this design. If the
  tenant's inbound setting **Block Public Internet Access** is off, a public agent pool works
  and private links only serve private clients. If it is on, the agent must egress through the
  VNet holding the private endpoint, resolve the tenant FQDN privately, and still reach
  `login.microsoftonline.com` publicly for a token — and **workspace-level** private link
  additionally forbids deployment pipelines and semantic models, and requires Git features to
  be used from inside the approved VNet. Confirm before building; see
  [the network note](../research/network-private-endpoints-and-deployment-path.md).

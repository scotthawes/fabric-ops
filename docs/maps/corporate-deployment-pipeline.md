# The corporate deployment pipeline, mapped

**Dated 2026-11-27.** How a change travels from this repository to the corporate tenant, and where
each gate sits. Sources: [`corporate-pack/spec/0002-contract.md`](../reference/corporate-pack/spec/0002-contract.md),
[`spec/0001-decisions.md`](../reference/corporate-pack/spec/0001-decisions.md) and
[`spec/0004-assumptions.md`](../reference/corporate-pack/spec/0004-assumptions.md).

## 1. The one-way channel

```mermaid
flowchart LR
  subgraph ours["fabric-ops — this repository"]
    PACK["corporate-pack<br/>spec · .tmpl skeletons · runbook · agents"]
  end

  subgraph theirs["Corporate estate"]
    REPO["corporate work repo<br/>terraform · pipelines · config"]
    ADO["ADO pipeline<br/>cicd.yml"]
    ARM["Azure<br/>resource group · 2 capacities · state"]
    FAB["Fabric<br/>domains · workspaces · items"]
    ENTRA["Entra<br/>3 groups per workspace · service principals"]
  end

  PERSON(["a person"])

  PACK -->|"read-only; one-way"| REPO
  REPO -->|"triggers"| ADO
  ADO -->|"Terraform"| ARM
  ADO -->|"Fabric API · fabric-cicd"| FAB
  ADO -->|"Graph"| ENTRA
  ADO -.->|"no channel back"| PERSON
  PERSON -.->|"carries a report, not a log"| PACK
```

The corporate machine reads this repository and copies the pack; nothing is pushed back. That is why
the pack carries its own probes, baselines and troubleshooting index.

## 2. The stage graph

```mermaid
flowchart TB
  B["Build<br/>bundle · fmt · validate · parameter parity"]
  P["Probe<br/>AUTH · FABRIC · DOMAINS · GRAPH · PROVIDER · ADMIN"]
  OK{"required probes green?"}
  STOP["stop<br/>PROBE-* code"]
  PLAT["Platform<br/>capacity-nonprod ∥ capacity-prod<br/>domains only if createDomains"]
  N["Nonprod<br/>per domain: control → content"]
  PP["PlanProd<br/>one plan per domain<br/>no environment, no gate"]
  GATE{{"human approval<br/>fabric-prod"}}
  PR["Prod-[domain]<br/>assert_plan → apply saved plan → content → assign"]

  B --> P --> OK
  OK -->|"no"| STOP
  OK -->|"yes"| PLAT
  PLAT --> N
  N --> PP
  PP --> GATE
  GATE -->|"approved"| PR
  PR -->|"next domain"| GATE
```

The gate is the `environment:` line. An approval that times out marks the stage **skipped**, not
failed, so read the stage result, not the run colour.

## 3. Where the plans and states live

```mermaid
flowchart LR
  subgraph roots["Terraform roots"]
    PLATFORM["platform"]
    DOMAINS["domains<br/>(optional)"]
    WS["workspaces"]
    ASSIGN["domain-assignments<br/>(preview)"]
  end

  subgraph blobs["one container · one blob per key"]
    S1["platform/nonprod.tfstate"]
    S2["platform/prod.tfstate"]
    S3["domains.tfstate"]
    S4["workspaces/[domain]/nonprod.tfstate"]
    S5["workspaces/[domain]/prod.tfstate"]
    S6["assignments/[domain].tfstate"]
  end

  PLATFORM --> S1 & S2
  DOMAINS --> S3
  WS --> S4 & S5
  ASSIGN --> S6
  S1 -.->|"data fabric_capacity"| S4
  S2 -.->|"data fabric_capacity"| S5
```

A plan is made against one blob and applied to it. It is never promoted between environments or
domains — that is why `PlanProd` exists.

## 4. One production deploy, in order

```mermaid
sequenceDiagram
  participant P as PlanProd job
  participant S as Prod state blob
  participant H as Human approver
  participant J as Prod stage
  participant F as Fabric / Graph

  P->>S: plan against prod state
  P->>P: publish tfplan-domain (one artifact per domain)
  H->>J: approve on fabric-prod, after reading the plan
  J->>J: assert_plan — replacement, delete, counts
  J->>S: init with the same key
  J->>F: apply the saved plan
  J->>F: deploy items (same bundle as nonprod)
  J->>F: assign workspaces to the domain
  Note over J,F: no re-plan, no -refresh=false, no -target
```

## 5. What is automated, and what stays human

| Step | Who | Gate |
| --- | --- | --- |
| Copy the pack, fill placeholders | corporate engineer, one `scaffold.sh` | `check-pack.sh` clean |
| Probe the tenant, read-only | pipeline | `PROBE-*` green |
| Create capacities | pipeline | `fabric-platform` approval (optional) |
| Create domains | **human by default**; pipeline only assigns | `PROBE-ADMIN` decides whether the optional root may run |
| Create a repository per nonprod workspace | human | run-book 00 |
| Create workspace, groups, identity, grants | pipeline | `fabric-nonprod` |
| Plan production | pipeline | read-only |
| Approve production | **human** | `fabric-prod`, one per domain |
| Apply production | pipeline | `assert_plan` + the approval |
| Pause a capacity | human | never scheduled |
| Report a failure | **a person carries the archive** | `scripts/report.sh` |

The rule behind the table: **agents plan, humans approve, the pipeline applies.** No agent holds a
production credential, and no step depends on a question travelling back to this repository.

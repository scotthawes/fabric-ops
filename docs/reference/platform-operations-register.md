# Platform operations register: what we have counted, and what we have not

**Dated 2026-11-12.** "Platform operations" is broader than Fabric's REST API. This page is the
completeness check: every platform the design touches, whether its operations are censused, and what
we actually rely on from it.

## Counted

| Platform | Operations | Method |
| --- | --- | --- |
| **Fabric REST control plane** (`api.fabric.microsoft.com/v1`, `/v1/admin`) | **825** across 61 groups | Generated from `fabric-rest-api-specs` ([census](api-operations.md)) |
| **ARM `Microsoft.Fabric`** | **13** | Generated from `azure-rest-api-specs` ([detail](arm-fabric-operations.md)) |
| **Terraform providers** | **71 resources**, 136 data sources | Enumerated from provider docs ([inventory](terraform-resource-inventory.md)) |
| **`fab` CLI** | 9 groups + 20 `fs` subcommands | Enumerated from the repo ([detail](fab-cli-commands.md)) |

## Not counted, and cannot be the same way

| Platform | Why not | What we rely on from it |
| --- | --- | --- |
| **Power BI legacy REST** (`api.powerbi.com`) | No public OpenAPI spec exists, so there is nothing to generate from | Refresh, RLS roles, `setLabels`, `Rebind Report`, `TakeOver` — the five verdicts in the legacy note |
| **OneLake data plane** (`*.dfs.fabric.microsoft.com`) | It is ADLS Gen2-compatible; its "operations" are the blob/file verbs | Path reads and writes, including `fab fs` |
| **T-SQL** (`*.datawarehouse…:1433`) | Commands, not operations | Schema deployment (`sqlproj` + SqlPackage), ad-hoc SQL |
| **KQL** (`*.z<n>.kusto…`) | Management commands plus queries | Eventhouse queries, Activator triggers |
| **XMLA / TMSL** (`powerbi://…`) | Object model, not REST | Semantic-model RLS roles |
| **Purview** | Separate product with its own API surface | The Fabric source scan, for governance metadata |

## Not counted, and this is the real gap

Two adjacent platforms are **load-bearing for the design** and have never been censused, because
they are outside Fabric:

| Platform | What our design depends on | Raised by |
| --- | --- | --- |
| **Entra ID / Microsoft Graph** | Create and manage one security group per workspace; app registrations; service principals; federated identity credentials; group membership reads for the access report | [ADR 0002](../adr/0002-two-service-principals-federated.md), [ADR 0006](../adr/0006-access-through-entra-groups.md) |
| **Azure DevOps** | Service connections on workload identity federation; Environments and their approval checks; pipeline edit permissions | [ADR 0005](../adr/0005-authoring-and-promotion.md), [ADO note](../research/ado-pipeline-mechanics.md) |

A full Graph census would be thousands of operations and useless; what matters is the handful above,
and whether they can be automated with the same principals. The honest position: **we have described
those steps in prose and never verified their operation names**, which is exactly the class of error
that produced three wrong verdicts earlier in this audit.

## Within Fabric, what the census still cannot see

- **Undocumented operations.** `POST /v1/admin/items/bulkSetLabels` exists in the spec but 404s on
  Learn, so documentation and reality disagree.
- **Beta surfaces.** 48 operations take a `beta` query parameter; they are counted, but their
  behaviour is explicitly unstable.
- **Workload-development inbound APIs.** About 20 operations for building a Fabric *workload*; absent
  from the spec, and out of scope unless we ship a product into Fabric.
- **New groups.** `share` and `shareSubscription` appear in the spec and are absent from Learn —
  evidence that the spec runs ahead of the docs, not behind them.

## The answer

**Inside Fabric: no, the control plane is complete as of spec commit `3f8600f`.** Outside it: yes,
in two places that matter — Entra and Azure DevOps — plus one that would matter if we automated
refresh or RLS (Power BI legacy) and four data planes that are not operation-shaped at all.

The next useful census is not bigger; it is narrower: the ~10 Entra operations and ~6 ADO operations
this design actually calls.

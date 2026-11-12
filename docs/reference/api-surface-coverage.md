# API surface coverage: what we have collected, and what we have not

**Dated 2026-11-12.** Short answer: **no.** One surface is complete — the Fabric REST control plane
— and it is the one this design depends on. Several others are documented but uncensused, and one
has no public machine-readable spec at all.

## The surfaces

| Surface | What it is | Status here | How it would be enumerated |
| --- | --- | --- | --- |
| **Fabric REST control plane** | `api.fabric.microsoft.com/v1` plus `/v1/admin` — workspaces, items, definitions, Git, jobs, connections, tenant settings, admin reads | **Complete census: 825 operations**, 61 groups, spec commit `3f8600f` ([census](api-operations.md)) | `python3 refresh-api-operations.py` |
| **Terraform providers** | `microsoft/fabric` + `azurerm` | **Complete inventory: 71 resources, 136 data sources** ([inventory](terraform-resource-inventory.md)) | Provider docs at the pinned tag |
| **OneLake data plane** | `<workspace>.dfs.fabric.microsoft.com` — files, tables, shortcuts | Not censused. It is an ADLS Gen2-compatible surface, so "operations" are the ADLS verbs rather than a Fabric OpenAPI | OneLake access docs + DFS REST reference |
| **T-SQL** | `*.datawarehouse.fabric.microsoft.com:1433` — warehouse and SQL analytics endpoint | Not censused. Commands are T-SQL DDL/DML, not operations | SQL reference; TDS protocol |
| **KQL** | `*.z<n>.kusto.fabric.microsoft.com` — eventhouse, KQL databases | Not censused. Management commands plus query commands | Kusto management-commands reference |
| **XMLA / TMSL** | `powerbi://api.powerbi.com/v1.0/…` — semantic models | Not censused; used in one place (RLS roles) | TMSL and TOM reference |
| **ARM — `Microsoft.Fabric`** | Capacity create, suspend, resume, overage | **Partially covered**: the suspend/resume action and API version are in the capacity note, but there is no operation census | Azure REST reference for `Microsoft.Fabric/capacities` |
| **Legacy Power BI REST** | `api.powerbi.com` — refresh, RLS, labels, rebind, takeover, apps | Partially covered ([note](../research/powerbi-rest-api-for-fabric-items.md)); **no public OpenAPI repo found**, so there is no census to generate | Learn Power BI REST reference |
| **Fabric CLI (`fab`)** | `microsoft/fabric-cli` | Not enumerated. **11 documentation groups** — `acls`, `api`, `auth`, `config`, `desc`, `find`, `fs`, `jobs`, `labels`, `tables` — and `fab api` is a raw REST passthrough | The repo's `docs/commands/` tree |
| **Azure CLI `az fabric`** | Capacity create/suspend/resume as CLI verbs | Not enumerated; not installed here | `az fabric capacity --help` once the extension is installed |
| **PowerShell** | Gateway membership (`Add-DataGatewayClusterUser`), community `FabricTools` | Not enumerated | Module command listings |
| **MCP servers** | Three remote Fabric MCPs | Configured ([guide](../guides/fabric-mcp.md)) | Each server's tool list at connect time |
| **Events** | Real-Time hub `Capacity.Summary` / `Capacity.State`, `ItemJobEventLogs` | Partially covered in the monitoring note | Event schema documentation |
| **Workload development APIs** | Inbound APIs for building a Fabric *workload* | Not covered, and not relevant unless we ship a product into Fabric | Learn workload-development section |

## What that means in practice

- **For this project's decisions, the census is sufficient.** Everything the design does — create
  containers, assign roles, bind Git, deploy definitions, bind connections, run jobs, audit access —
  lives in the control plane, and that surface is enumerated.
- **The uncensused surfaces are data-plane or vendor-specific.** T-SQL, KQL and DFS do not have
  "operations" in the OpenAPI sense; counting them would produce a number that means something
  different.
- **Two gaps are worth closing if the work changes:** the ARM capacity provider (if we start doing
  suspend/resume or overage as code) and the legacy Power BI REST (if we automate refresh, RLS or
  labels). Both are narrow and named.
- **`fab` is mostly a wrapper.** Its `api` verb passes through to the same REST surface, and its
  distinctive commands are `fs` (OneLake files), `jobs`, `tables` and `labels`. Enumerating it would
  add convenience, not capability.

## The honest rule

A surface is "collected" here only when a script can regenerate its operation list. By that test this
pack has collected **two** surfaces — Fabric REST and Terraform — and has documented five more to the
depth the decisions needed.

Do not describe this repository as covering "all Fabric APIs". Say instead: the control plane is
censused, Terraform is inventoried, the data planes are mapped but not enumerated, and the legacy
Power BI API is researched only where it changes a verdict.

# GitHub ecosystem for Microsoft Fabric

**Checked 2026-11-11.** Every row was pulled from the GitHub API, not from memory: star count,
last push date and licence are as of that date. The full sweep — 311 repositories after
removing unrelated projects that merely share the word "fabric" — is in
[`repos.tsv`](repos.tsv). Reproduce or refresh it with [`refresh.sh`](refresh.sh).

Two things to keep in mind while reading:

- **Stars are a weak signal here**, and in this ecosystem they are actively gamed. See
  [the warning below](#stars-are-not-a-signal-worth-trusting).
- **Microsoft ships under several orgs** — `microsoft`, `MicrosoftLearning`, `Azure-Samples`,
  `AzureCosmosDB` — and a lot of first-party material lives in individuals' personal repos.
  "Official" below means "owned by a Microsoft org", nothing more.

## Stars are not a signal worth trusting

On 2026-11-11 the sweep surfaced four repositories created on the same day, 2026-11-06, from
four unrelated accounts, each with **exactly 149 stars and zero forks**, 200–700 KB in size:

| Repository | ★ | Forks | Created |
| --- | --- | --- | --- |
| `ArteVisualenVivo/fabric-pipeline-express-7` | 149 | 0 | 2026-11-06 |
| `muhammadusamakhan911-bit/fabric-mlv-agent-healthcare-starter` | 149 | 0 | 2026-11-06 |
| `balkewkidane/grizl-fabric-observability` | 149 | 0 | 2026-11-06 |
| `kaan123434/cart-abandonment-rti` | 149 | 0 | 2026-11-06 |

Their topic lists are near-identical keyword stuffing (`microsoft-fabric`, `onelake`, `dp-700`,
`activator`, …). They are excluded from the tables below. The practical rule: **a star count
above 100 with a single-digit fork count and a creation date inside the last few months is a
promotion artefact, not adoption** — Fabric is a young platform and genuine adoption shows up as
forks, issues and contributors. `microsoft/fabric-cicd` (347★, 187 forks) is what real traction
looks like.

---

## 1. Official — deployment and CI/CD

The set our design in [ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md)
actually depends on.

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/fabric-cicd`](https://github.com/microsoft/fabric-cicd) | 347 | 2026-11-11 | MIT | The Python deployer our item pipeline is built on. Reads definitions from a folder, pushes via REST, parameterises per environment. |
| [`microsoft/terraform-provider-fabric`](https://github.com/microsoft/terraform-provider-fabric) | 130 | 2026-11-11 | MPL-2.0 | The control-plane provider: workspaces, role assignments, domains, tenant settings. **Explicitly outside Microsoft support** — see ADR 0003. |
| [`microsoft/fabric-terraform-quickstart`](https://github.com/microsoft/fabric-terraform-quickstart) | 49 | 2026-11-11 | MIT | Worked examples for the provider, including the resource patterns worth copying. |
| [`microsoft/fabric-cli`](https://github.com/microsoft/fabric-cli) | 176 | 2026-11-04 | MIT | First-party CLI over the Fabric APIs. Useful for the ad-hoc and investigative half of admin work. |
| [`microsoft/fabric-launcher`](https://github.com/microsoft/fabric-launcher) | 10 | 2026-10-29 | MIT | Automates the initial deployment and configuration of a solution into a workspace — closer to a turnkey installer than a library. |
| [`microsoft/fabric-rest-api-specs`](https://github.com/microsoft/fabric-rest-api-specs) | 48 | 2026-11-10 | NOASSERTION | The OpenAPI source behind the REST reference. The place to look when a Learn page and the behaviour disagree. |
| [`microsoft/vscode-fabric`](https://github.com/microsoft/vscode-fabric) | 45 | 2026-11-05 | MIT | The VS Code extension — worth a look if authors want to stay out of the browser. |
| [`microsoft/data-factory-testing-framework`](https://github.com/microsoft/data-factory-testing-framework) | 136 | 2026-11-11 | MIT | Unit tests for Data Factory pipelines, covering Fabric and Azure Data Factory. Fills the gap `fabric-cicd` leaves: it has no dry run. |

## 2. Official — SDKs and extensibility

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/fabric-extensibility-toolkit`](https://github.com/microsoft/fabric-extensibility-toolkit) | 57 | 2026-09-14 | MIT | Scaffolding for building a Fabric *workload* — only relevant if you ship a product into Fabric, not if you use it. |
| [`microsoft/Microsoft-Fabric-workload-development-sample`](https://github.com/microsoft/Microsoft-Fabric-workload-development-sample) | 58 | 2026-08-06 | MIT | Reference implementation of a workload in .NET + TypeScript. |
| [`microsoft/fabric-user-data-functions-samples`](https://github.com/microsoft/fabric-user-data-functions-samples) | 29 | 2026-11-06 | MIT | User data functions, which is how custom Python gets called from Fabric items. |
| [`microsoft/fabric-apps-analytic-templates`](https://github.com/microsoft/fabric-apps-analytic-templates) | 29 | 2026-11-11 | MIT | Templates for building analytics apps on Fabric data. |
| [`microsoft/fabric-sdk-go`](https://github.com/microsoft/fabric-sdk-go) | 20 | 2026-11-11 | MIT | Go SDK. Only interesting if the work repo stops being Python/YAML. |
| [`microsoft/airflow-providers-microsoft-fabric`](https://github.com/microsoft/airflow-providers-microsoft-fabric) | 14 | 2026-09-26 | MIT | Current Airflow provider. Supersedes the archived `apache-airflow-microsoft-fabric-plugin` (25★, last push 2024). |
| [`microsoft/dbt-fabric`](https://github.com/microsoft/dbt-fabric) | 153 | 2026-10-26 | MIT | dbt adapter for the Fabric warehouse. |
| [`microsoft/dbt-fabricspark`](https://github.com/microsoft/dbt-fabricspark) | 72 | 2026-11-11 | MIT | dbt adapter for the lakehouse, backed by Spark. |

## 3. Official — samples, accelerators and workshops

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/fabric-toolbox`](https://github.com/microsoft/fabric-toolbox) | 947 | 2026-11-02 | MIT | The big first-party grab bag: tools, accelerators, scripts, samples. 560 MB — clone shallow or browse the web UI. |
| [`microsoft/fabric-samples`](https://github.com/microsoft/fabric-samples) | 644 | 2026-10-23 | MIT | Samples and data behind the Learn content, including the item-definition examples. |
| [`microsoft/fabric-jumpstart`](https://github.com/microsoft/fabric-jumpstart) | 60 | 2026-11-05 | MIT | Accelerators that install into a workspace in minutes — the fastest way to see a known-good layout. |
| [`microsoft/unified-data-foundation-with-fabric-solution-accelerator`](https://github.com/microsoft/unified-data-foundation-with-fabric-solution-accelerator) | 50 | 2026-10-23 | MIT | The reference medallion architecture with Databricks and Purview options. |
| [`microsoft/fabric-architecture-review`](https://github.com/microsoft/fabric-architecture-review) | 28 | 2026-11-11 | NOASSERTION | Metadata-only end-to-end tenant scan across governance, cost, capacity and performance. Directly relevant to [recommendation 04](../recommendations/04-users-and-governance.md). |
| [`microsoft/FabricCAT`](https://github.com/microsoft/FabricCAT) | 29 | 2026-09-03 | MIT | Customer Advisory Team content — opinionated, closer to field practice than the docs. |
| [`microsoft/FabricAccelerateFactory`](https://github.com/microsoft/FabricAccelerateFactory) | 13 | 2026-03-04 | MIT | Migration methodology plus automation. |
| [`microsoft/fabric-migration`](https://github.com/microsoft/fabric-migration) | 31 | 2024-04-09 | MIT | Scripts to move DW and Spark workloads; last push 2024, so read it as a starting point. |
| [`microsoft/FabricBQSync`](https://github.com/microsoft/FabricBQSync) | 26 | 2026-10-30 | MIT | BigQuery sync. |
| [`microsoft/fabric-event-streams`](https://github.com/microsoft/fabric-event-streams) | 6 | 2026-04-21 | MIT | Eventstream samples and templates. |
| [`microsoft/fabric-data-agent-workshop`](https://github.com/microsoft/fabric-data-agent-workshop) | 7 | 2026-08-28 | MIT | Workshop for Fabric data agents. |
| [`microsoft/frontier-fabric-governance-rvas`](https://github.com/microsoft/frontier-fabric-governance-rvas) | 2 | 2026-11-05 | MIT | Agentic governance blueprint — small, new, and pointed at exactly the problem in recommendation 04. |

## 4. Official — learning

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/Ontology-Playground`](https://github.com/microsoft/Ontology-Playground) | 3039 | 2026-10-31 | MIT | Fabric IQ ontology learning app. Popular because it is a demo, not because it is infrastructure. |
| [`microsoft/skills-for-fabric`](https://github.com/microsoft/skills-for-fabric) | 1339 | 2026-11-05 | MIT | Agent skills and MCP systems so CLI, VS Code and Claude can drive Fabric. The highest-starred genuinely-useful Fabric repo. |
| [`microsoft/iq-series`](https://github.com/microsoft/iq-series) | 409 | 2026-11-10 | MIT | Hands-on labs for the IQ family (Work, Foundry, Fabric). |
| [`MicrosoftLearning/mslearn-fabric`](https://github.com/MicrosoftLearning/mslearn-fabric) | 393 | 2026-11-05 | MIT | Source for the Learn modules, with labs you can run. |
| [`microsoft/fabricnotes`](https://github.com/microsoft/fabricnotes) | 118 | 2026-11-01 | CC-BY-4.0 | Hand-drawn explainers — the best ten-minute overview for a non-technical stakeholder. |
| [`microsoft/fabric-task-flows`](https://github.com/microsoft/fabric-task-flows) | 50 | 2026-05-22 | MIT | Natural-language to Fabric solution, agent-generated. Promo-shaped, but shows where the product is going. |
| [`microsoft/project-osmos`](https://github.com/microsoft/project-osmos) | 24 | 2026-10-28 | NOASSERTION | Copilot/Claude plugin wrapping the Osmos data-engineer agent. |

## 5. Official, but archived — reference only

Worth reading, not worth depending on. Check these before copying a pattern from a blog.

| Repository | ★ | Last push | Note |
| --- | --- | --- | --- |
| [`Azure-Samples/modern-data-warehouse-dataops`](https://github.com/Azure-Samples/modern-data-warehouse-dataops) | 710 | 2026-02-25 | **Archived.** The classic DataOps reference; its ideas survive, its code does not. |
| [`microsoft/Fabric-metadata-scanning`](https://github.com/microsoft/Fabric-metadata-scanning) | 33 | 2024-09-11 | **Archived.** Scanner API sample — still the clearest example of the admin-scan shape. |
| [`microsoft/fabric_data_agent_client`](https://github.com/microsoft/fabric_data_agent_client) | 36 | 2026-10-22 | **Archived.** Calling a data agent from outside Fabric. |
| [`microsoft/Fabric-Readiness`](https://github.com/microsoft/Fabric-Readiness) | 273 | 2024-03-22 | Not archived, but untouched for 19 months — pre-GA material. |

## 6. Community — CI/CD patterns

The most valuable community material, because Microsoft publishes a library (`fabric-cicd`) but
not the pipeline that surrounds it.

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`kevchant/AzureDevOps-fabric-cicd-sample`](https://github.com/kevchant/AzureDevOps-fabric-cicd-sample) | 8 | 2025-10-16 | MIT | The canonical ADO YAML walkthrough for `fabric-cicd`. Closest thing to our
[reference pipeline](../reference/ado-pipeline.yml). |
| [`kevchant/GitHub-fabric-cicd-sample`](https://github.com/kevchant/GitHub-fabric-cicd-sample) | 4 | 2025-07-10 | none | Same pattern with GitHub Actions. |
| [`kevchant/AzureDevOps-AutomateFabricDeploymentPipeline`](https://github.com/kevchant/AzureDevOps-AutomateFabricDeploymentPipeline) | 5 | 2024-06-11 | none | Automates Fabric's *native* deployment pipelines from YAML — relevant only if you go that route. |
| [`kevchant/GitHub-FUAM-Deploymenator`](https://github.com/kevchant/GitHub-FUAM-Deploymenator) | 9 | 2025-07-28 | MIT | Deploys FUAM, the community workspace-accelerator framework. |
| [`vinod-soni-microsoft/FABRIC-CICD-PROJECT`](https://github.com/vinod-soni-microsoft/FABRIC-CICD-PROJECT) | 2 | 2026-05-18 | none | Enterprise-shaped `fabric-cicd` + GitHub Actions example. |
| [`alisonpezzott/fabricopsflow`](https://github.com/alisonpezzott/fabricopsflow) | 19 | 2026-03-15 | MIT | End-to-end CI/CD framework spanning Azure DevOps, service principals and promotion. |
| [`chantifiedlens/deploy-microsoft-fabric-items`](https://github.com/chantifiedlens/deploy-microsoft-fabric-items) | 3 | 2026-01-10 | MIT | A reusable **GitHub Action** wrapping `fabric-cicd` with Az PowerShell auth. |
| [`michaeldeongreen/microsoft-fabric-sdlc-patterns`](https://github.com/michaeldeongreen/microsoft-fabric-sdlc-patterns) | 16 | 2026-11-03 | none | Branching strategies and Git-based SDLC patterns, written as a reference implementation. |
| [`kerski/fabric-dataops-patterns`](https://github.com/kerski/fabric-dataops-patterns) | 64 | 2026-05-24 | MIT | DataOps templates: the promotion and testing patterns around the deploy. |
| [`gronnerup/FabricOps`](https://github.com/gronnerup/FabricOps) | 19 | 2026-10-04 | MIT | IaC + CI/CD + delivery in one project. |
| [`FabricDevCamp/fabric-cicd-whitepaper`](https://github.com/FabricDevCamp/fabric-cicd-whitepaper) | 9 | 2026-06-17 | none | The community CI/CD whitepaper — the best single explanation of *why* the promotion model looks like this. |
| [`dereknguyenio/fabric-automation-bundles`](https://github.com/dereknguyenio/fabric-automation-bundles) | 3 | 2026-05-16 | MIT | Declarative project definitions for CI/CD. |
| [`imtkain/Fabric-Pathfinder`](https://github.com/imtkain/Fabric-Pathfinder) | 14 | 2026-01-26 | none | Maps artifacts across DEV/UAT/PROD via the Admin API — useful for building variable libraries. |
| [`EvaluationContext/fabric-cicd-example`](https://github.com/EvaluationContext/fabric-cicd-example) | 2 | 2026-11-07 | none | One workspace, five items, dev → test → prod. Small enough to read in full. |

## 7. Community — infrastructure as code

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`murggu/fabric-capacity-iac`](https://github.com/murggu/fabric-capacity-iac) | 11 | 2024-01-17 | none | IaC for the capacity resource itself. Dated, but the only example of the ARM/Bicep path. |
| [`carlosacchi/microsoft-fabric-with-terraform`](https://github.com/carlosacchi/microsoft-fabric-with-terraform) | 4 | 2025-08-06 | none | Terraform modules for workspaces with a medallion layout. |
| [`tysoncung/azure-fabric-data-platform`](https://github.com/tysoncung/azure-fabric-data-platform) | 4 | 2025-09-13 | none | Terraform for an enterprise platform with Fabric integrated. |
| [`FC2026-DeepDiveFabricCICD/fabric-terraform-demo`](https://github.com/FC2026-DeepDiveFabricCICD/fabric-terraform-demo) | 0 | 2026-03-01 | MIT | Conference demo wiring Terraform + ADO for Fabric. |
| [`ChristopherNagl/terraform-provider-microsoftfabric`](https://github.com/ChristopherNagl/terraform-provider-microsoftfabric) | 7 | 2024-11-06 | MPL-2.0 | A community provider that predates the official one. Superseded; useful only as history. |

## 8. Community — administration, governance and monitoring

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`dataplat/FabricTools`](https://github.com/dataplat/FabricTools) | 60 | 2026-11-10 | MIT | PowerShell module for Fabric administration. The active successor to `Jojobit/Fabtools` — check the rename before searching. |
| [`NatVanG/fab-inspector`](https://github.com/NatVanG/fab-inspector) | 95 | 2026-11-08 | MIT | Deterministic, rules-based testing for Fabric tenants. The closest thing to a test suite for an estate. |
| [`aboerger/Custom-Admin-Monitoring-Microsoft-Fabric`](https://github.com/aboerger/Custom-Admin-Monitoring-Microsoft-Fabric) | 12 | 2025-04-29 | MIT | Custom admin monitoring built on the scanner and admin APIs. |
| [`kilianbs/fabric-schedule-inventory`](https://github.com/kilianbs/fabric-schedule-inventory) | 6 | 2026-10-14 | MIT | Inventories every scheduled item and plots a typical-day Gantt. Answers "what runs at 02:00". |
| [`Cloud2BR-MSFTLearningHub/Fabric-EnterpriseFramework`](https://github.com/Cloud2BR-MSFTLearningHub/Fabric-EnterpriseFramework) | 6 | 2026-07-29 | MIT | Well-architected demos and guides for an enterprise data platform. |
| [`Insight-Services-APAC/Insight_Ingenious_For_Fabric`](https://github.com/Insight-Services-APAC/Insight_Ingenious_For_Fabric) | 11 | 2026-10-12 | MIT | Framework for accelerated development, testing and deployment. |
| [`FabricTools/fabric-icons`](https://github.com/FabricTools/fabric-icons) | 74 | 2026-11-09 | MIT | SVG icons from `@fabric-msft/svg-icons` — for diagrams that look right. |

## 9. Community — developer libraries

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/semantic-link-labs`](https://github.com/microsoft/semantic-link-labs) | 596 | 2026-11-10 | MIT | First-party but lab-grade: `sempy_labs`, the de facto standard for manipulating semantic models from notebooks. |
| [`TabularEditor/TabularEditor`](https://github.com/TabularEditor/TabularEditor) | 1130 | 2026-09-11 | MIT | Not Fabric-specific, but the tool most Fabric semantic-model work assumes. |
| [`data-goblin/power-bi-agentic-development`](https://github.com/data-goblin/power-bi-agentic-development) | 1089 | 2026-11-10 | GPL-3.0 | AI skills and agents for semantic-model development. |
| [`m-kovalsky/fabric_cat_tools`](https://github.com/m-kovalsky/fabric_cat_tools) | 120 | 2024-07-23 | MIT | **Archived.** The precursor to `semantic-link-labs`; cited everywhere, maintained nowhere. |
| [`alisonpezzott/pyfabricops`](https://github.com/alisonpezzott/pyfabricops) | 49 | 2026-10-27 | MIT | Thin Python wrapper over the Fabric/Power BI REST APIs. |
| [`mrjsj/msfabricutils`](https://github.com/mrjsj/msfabricutils) | 45 | 2026-05-20 | MIT | Spark-free utilities using Polars and delta-rs — interesting for lightweight jobs. |
| [`ladparth/fabricflow`](https://github.com/ladparth/fabricflow) | 26 | 2026-01-16 | MIT | Code-first Python SDK for pipelines and workspaces. |
| [`JonathanJihwanKim/pbip-documenter`](https://github.com/JonathanJihwanKim/pbip-documenter) | 64 | 2026-09-30 | MIT | Generates documentation from PBIP/TMDL models. |
| [`JamesDBartlett3/PowerBits`](https://github.com/JamesDBartlett3/PowerBits) | 62 | 2026-07-08 | OSL-3.0 | Grab bag of Power BI/Fabric tooling. |
| [`WeaveAnalytics/needlr`](https://github.com/WeaveAnalytics/needlr) | 8 | 2025-06-26 | MIT | Fabric SDK and utilities. |
| [`DanielAndreassen97/futils`](https://github.com/DanielAndreassen97/futils) | 5 | 2026-10-21 | MIT | Interactive CLI: run notebooks with parameters, refresh tables, move items. |

## 10. Community — local development and emulation

The most interesting category, because it changes what can be tested before deploy.

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`calvinchengx/fabric-emulator`](https://github.com/calvinchengx/fabric-emulator) | 26 | 2026-11-10 | Apache-2.0 | A local Fabric in one Go binary — control plane, OneLake, T-SQL and Spark. Ambitious and young; would remove the "no dry run" pain in ADR 0003 if it holds up. |
| [`djouallah/Fabric_Notebooks_Demo`](https://github.com/djouallah/Fabric_Notebooks_Demo) | 111 | 2026-09-01 | none | Practical notebook patterns, which is where most Fabric pyodide quirks get discovered. |
| [`mdrakiburrahman/spark-devcontainer`](https://github.com/mdrakiburrahman/spark-devcontainer) | 21 | 2026-03-19 | none | Devcontainer for Spark work aimed at Fabric compatibility. |
| [`mdrakiburrahman/spark-sandbox`](https://github.com/mdrakiburrahman/spark-sandbox) | 26 | 2026-06-21 | none | Spark patterns with a Fabric focus. |
| [`djouallah/onelake_studio`](https://github.com/djouallah/onelake_studio) | 11 | 2026-11-11 | MIT | VS Code extension to browse OneLake and semantic models, read-only. |
| [`sdebruyn/onelake-explorer-macos`](https://github.com/sdebruyn/onelake-explorer-macos) | 4 | 2026-10-10 | MIT | OneLake in Finder — useful because the first-party explorer is Windows-only. |
| [`data-goblin/nb-cli`](https://github.com/data-goblin/nb-cli) | 12 | 2026-10-15 | NOASSERTION | **Archived.** CLI for Fabric notebooks. |

## 11. Community — AI, MCP and agents

Fast-moving, mostly preview, and the area most likely to be obsolete in six months. Included
because the team is likely to be asked about it.

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`microsoft/fabric-rti-mcp`](https://github.com/microsoft/fabric-rti-mcp) | 133 | 2026-11-05 | MIT | First-party MCP server for Real-Time Intelligence. |
| [`santhoshravindran7/Fabric-Analytics-MCP`](https://github.com/santhoshravindran7/Fabric-Analytics-MCP) | 110 | 2025-12-23 | MIT | Community MCP over Fabric analytics data. |
| [`Augustab/microsoft_fabric_mcp`](https://github.com/Augustab/microsoft_fabric_mcp) | 25 | 2025-09-30 | MIT | MCP server wrapping the Fabric REST API. |
| [`sdebruyn/fabric-dw-mcp-cli`](https://github.com/sdebruyn/fabric-dw-mcp-cli) | 10 | 2026-11-01 | MIT | CLI + MCP for warehouses and SQL analytics endpoints. |
| [`PatrickGallucci/fabric-mcp-claude-extension`](https://github.com/PatrickGallucci/fabric-mcp-claude-extension) | 3 | 2026-02-27 | MIT | Claude Desktop extension wrapping Fabric MCP. |

## 12. Community — accelerators and learning

| Repository | ★ | Last push | Licence | What it is |
| --- | --- | --- | --- | --- |
| [`edkreuk/FMD_FRAMEWORK`](https://github.com/edkreuk/FMD_FRAMEWORK) | 166 | 2026-09-08 | MIT | Metadata-driven framework — the community's most-established accelerator pattern. |
| [`bennyaustin/fabric-accelerator`](https://github.com/bennyaustin/fabric-accelerator) | 156 | 2026-11-02 | GPL-2.0 | Reusable components plus an ELT orchestration framework. |
| [`bhakthan/awesome-microsoft-fabric`](https://github.com/bhakthan/awesome-microsoft-fabric) | 67 | 2026-10-07 | none | Curated link list. Good for discovery, not for authority. |
| [`lucid-bi/Fabric-Architecture-Diagrams`](https://github.com/lucid-bi/Fabric-Architecture-Diagrams) | 29 | 2025-03-21 | none | Architecture diagram samples. |
| [`marclelijveld/Fabric-Automation`](https://github.com/marclelijveld/Fabric-Automation) | 19 | 2026-09-06 | MIT | Solution templates for automation. |
| [`kengio/dp-700-study-guide`](https://github.com/kengio/dp-700-study-guide) | 11 | 2026-08-01 | MIT | Community study guide for DP-700. |
| [`marclelijveld/Fabric-Icons`](https://github.com/marclelijveld/Fabric-Icons) | 27 | 2023-10-13 | MIT | draw.io stencil set. Dated but still usable. |
| [`thedatashepherd/Presentations`](https://github.com/thedatashepherd/Presentations) | 5 | 2026-11-07 | none | Conference decks on Fabric and Power BI. |

---

## What to clone for this project

Mapped to the decisions we have already taken, so nobody clones 300 repositories to find seven:

| Need | Repository | Why |
| --- | --- | --- |
| Item deployment ([ADR 0003](../adr/0003-terraform-control-plane-fabric-cicd-items.md)) | `microsoft/fabric-cicd` | The library the work repo will call |
| The pipeline around it | `kevchant/AzureDevOps-fabric-cicd-sample` | The only worked ADO YAML example that matches our shape |
| Why the promotion model is what it is | `FabricDevCamp/fabric-cicd-whitepaper` | Explains the constraints the docs state but do not justify |
| Control plane | `microsoft/terraform-provider-fabric` + `microsoft/fabric-terraform-quickstart` | Provider plus worked patterns |
| Capacity as code ([ADR 0004](../adr/0004-one-shared-capacity.md)) | `murggu/fabric-capacity-iac` | The only worked capacity-IaC example; dated, so treat as a shape not a solution |
| Access auditing ([ADR 0006](../adr/0006-access-through-entra-groups.md)) | `NatVanG/fab-inspector`, `microsoft/fabric-architecture-review` | Rules-based tenant checks and metadata-only estate scan |
| What runs when | `kilianbs/fabric-schedule-inventory` | Answers the capacity-contention question in ADR 0004 |
| Untested deploys | `calvinchengx/fabric-emulator`, `microsoft/data-factory-testing-framework` | The two routes to testing without a tenant round trip |

## Vetting checklist for adding a repository

1. **Created date and fork count.** A busy recent repo with no forks is a promotion artefact.
2. **Last push.** Fabric moves monthly; anything untouched for a year describes a different product.
3. **Licence.** Several of the most-linked community repos have none, which means all rights reserved — read-only reference, not code to vendor.
4. **Archived flag.** Five repos above are archived; the ecosystem's most-cited patterns are often in them.
5. **Owner.** A `-msft` suffix in a username is not proof of employment; check the owning org,
   and prefer org-owned repos for anything the work repo depends on.

## What this sweep does not cover

- **Bicep.** No first-party Bicep module set for Fabric items appeared. If the work repo needs one, it does not exist to clone.
- **Private and internal repos.** Obviously invisible.
- **Quality.** Stars and recency are proxies. Nothing above has been read end to end by this project — where a row matters, read the code before depending on it.
- **Azure DevOps extensions** published on the marketplace, which are not GitHub repositories.

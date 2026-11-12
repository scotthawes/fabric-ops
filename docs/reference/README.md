# Reference artefacts — illustrative only

**Dated 2026-11-11.** Everything here is **illustrative reference material for the work repo to
adapt**. Nothing runs from this repo: no Terraform root, no pipeline, no credential — by decision
(`../adr/0001-research-artefact-not-deployment-tool.md`).

Read these as a sketch of decisions already taken, not a specification. Treat a file older than a
few months as a question. A `# VERIFY:` marker is a known gap where the real API shape was not
confirmed — check the doc it names before building on it. All IDs, group IDs, SKUs and connection
names are placeholders.

| File | What it demonstrates |
| --- | --- |
| `naming.md` | One naming pattern for workspaces, capacity, groups, state and pipelines, and why. |
| `repo-layout.md` | The work repo's top-level folders and what each owns. |
| `ado-pipeline.yml` | Build + Dev/Test/Prod stages, two federated connections, prod approval. |
| `terraform-capacity.tf` | The shared F SKU as an Azure resource (ADR 0004). |
| `terraform-fabric.tf` | Workspaces, group role assignment, dev Git binding (ADR 0003, 0005, 0006). |
| `content-layout.md` | Item definitions in source-control format, and how parameterisation reaches them. |
| `parameter.example.yml` | A `fabric-cicd` `parameter.yml` with `find_replace` across dev/test/prod. |
| `role-and-permission-matrix.md` | Workspace roles in the product's own words, and the six grant paths beneath them. |
| `terraform-resource-inventory.md` | What our design deploys (6 resources) versus the provider's full 71. |
| `api-operations.tsv` / `.md` | **Generated census**: 825 REST operations, one row each, with a refresh script. |
| `arm-fabric-operations.tsv` / `.md` | The 13 ARM operations for the capacity, including overage. |
| `fab-cli-commands.md` | The CLI surface, and why it adds convenience rather than capability. |
| `api-surface-coverage.md` | Which API surfaces are actually collected, and which are not. |
| `platform-operations-register.md` | Every platform the design touches, and what we rely on from it. |

Two of these are generated rather than written — `api-operations.tsv` and
`arm-fabric-operations.tsv`. Regenerate rather than edit; a hand-edited census drifts from the spec.

Decisions adapted: ADR 0002 (two federated principals), 0003 (Terraform control plane, fabric-cicd
items), 0004 (one capacity), 0005 (authoring and promotion), 0006 (access via groups). Mechanism
evidence: `../research/deployment-mechanism-comparison.md`.

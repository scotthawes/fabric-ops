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

Decisions adapted: ADR 0002 (two federated principals), 0003 (Terraform control plane, fabric-cicd
items), 0004 (one capacity), 0005 (authoring and promotion), 0006 (access via groups). Mechanism
evidence: `../research/deployment-mechanism-comparison.md`.

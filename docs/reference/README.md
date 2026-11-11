# Reference artefacts — illustrative only

**Dated 2026-11-11.** Everything in this folder is **illustrative reference material for the
work repo to adapt**. Nothing here runs from this repo: there is no Terraform root, no pipeline
and no credential, by decision (`../adr/0001-research-artefact-not-deployment-tool.md`).

Read these as a sketch of decisions already taken, not as a specification. Every file carries
the date it was written; treat one older than a few months as a question. Any point marked
`# VERIFY:` is a known gap where the real API shape was not confirmed — check the named doc
before building on it. All identifiers, group IDs, SKUs and connection names are placeholders.

| File | What it demonstrates |
| --- | --- |
| `naming.md` | One naming pattern for workspaces, capacity, groups, state and pipelines, and why. |
| `repo-layout.md` | The work repo's top-level folders and what each owns. |
| `ado-pipeline.yml` | Build + Dev/Test/Prod stages, two federated service connections, prod approval. |
| `terraform-capacity.tf` | The shared F SKU as an Azure resource (ADR 0004). |
| `terraform-fabric.tf` | Workspaces, group role assignment and the dev Git binding (ADR 0003, 0005, 0006). |
| `content-layout.md` | Item definitions in source-control format, and how parameterisation reaches them. |
| `parameter.example.yml` | A `fabric-cicd` `parameter.yml` with `find_replace` across dev/test/prod. |

Decisions these adapt: `../adr/0002` (two federated principals), `../adr/0003` (Terraform
control plane, fabric-cicd items), `../adr/0004` (one capacity), `../adr/0005` (authoring and
promotion), `../adr/0006` (access through groups). Evidence for the mechanism split:
`../research/deployment-mechanism-comparison.md`.

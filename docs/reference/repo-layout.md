# Work repo layout (illustrative)

**Dated 2026-11-11.** The shape below is what the work repo should start from. It is a sketch,
not a manifest — the work repo owns the real files.

```
work-repo/
├── terraform/
│   ├── main.tf              # providers, azurerm + microsoft/fabric, backend
│   ├── capacity.tf          # shared F SKU, resource group, tags   (see terraform-capacity.tf)
│   ├── fabric.tf            # workspaces, role assignments, Git binding (see terraform-fabric.tf)
│   ├── variables.tf
│   ├── env/
│   │   ├── dev.tfvars       # capacity_id, group IDs, locations — non-secret values only
│   │   ├── test.tfvars
│   │   └── prod.tfvars
│   └── README.md            # how to plan locally, and what state holds what
├── content/                 # Fabric item definitions, source-control format (see content-layout.md)
│   └── fabric-sales-forecast/
│       ├── Sales Forecast Ingest.Notebook/
│       └── Sales Forecast Model.SemanticModel/
├── config/
│   ├── parameter.yml        # fabric-cicd find_replace, dev/test/prod keys inside
│   ├── dev.yaml             # per-env non-secrets: workspace name, capacity name, ADO env name
│   ├── test.yaml
│   └── prod.yaml
├── pipelines/
│   ├── cicd.yml             # the content + control-plane pipeline (see ado-pipeline.yml)
│   └── admin.yml            # sp-fabric-admin only: roles, tenant settings, scheduled jobs
└── scripts/
    ├── deploy_items.py      # wraps fabric-cicd: FabricWorkspace(...) + publish for one env
    └── preflight.py         # checks the workspace exists before items land; fails fast
```

Why each top-level folder exists:

- **`terraform/`** — the control plane: things with a lifecycle and an ID that must not be
  recreated by a content deploy (workspaces, role assignments, the Git connection, the capacity
  as an Azure resource). One root with a workspace per environment is the starting choice
  because the three environments differ only in a handful of variables; the alternative, one
  root per environment, buys harder isolation and three states to remember. If a second root is
  ever added, split by *lifetime*, not by environment — see ADR 0003 on keeping Terraform small
  enough that the REST fallback stays cheap.
- **`content/`** — the items, in Fabric's source-control format. One folder per workspace
  **without** the environment token, because the same definitions deploy to all three
  environments and `parameter.yml` supplies the differences. This is also the folder the dev
  workspace's Git integration commits into (ADR 0005), so it is the repo's hot path for authors.
- **`config/`** — everything that differs between environments, kept out of YAML and HCL so a
  diff between environments is a diff of values, not of logic. It holds no secrets: connection
  IDs, group IDs and workspace IDs are references, and the credential itself lives in the
  service connection.
- **`pipelines/`** — Azure DevOps YAML, one file per authority level. `cicd.yml` runs on merge to
  `main` and deploys content; `admin.yml` is a separate, gated pipeline because it holds the
  admin principal (ADR 0002). Two files also mean two approval records.
- **`scripts/`** — the only place with logic that is not declarative: the fabric-cicd call, and
  the preflight that turns "workspace missing" from a confusing API error into a one-line
  failure. Keep them thin; anything with branching belongs in Terraform or in the pipeline.

Ordering that the layout cannot express: Terraform must apply before items land (`preflight.py`),
and `content/` is committed by humans in the dev workspace while being *read* by the pipeline.
Both are dependencies on sequence, not on folders — worth stating in the work repo's README.

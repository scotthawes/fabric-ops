# Work repo layout (illustrative)

**Dated 2026-11-11.** The shape the work repo should start from — a sketch, not a manifest.

```
work-repo/
├── terraform/               # control plane: containers, IDs, role assignments
│   ├── main.tf              # providers (azurerm + microsoft/fabric) and backend
│   ├── capacity.tf          # shared F SKU, resource group, tags (see terraform-capacity.tf)
│   ├── fabric.tf            # workspaces, role assignments, Git binding (see terraform-fabric.tf)
│   └── env/{dev,test,prod}.tfvars      # non-secret values: group object IDs, region, SKU
├── content/                 # item definitions in source-control format (see content-layout.md)
│   └── fabric-sales-forecast/
│       ├── Sales Forecast Ingest.Notebook/
│       └── Sales Forecast Model.SemanticModel/
├── config/
│   ├── parameter.yml        # fabric-cicd find_replace, dev/test/prod keys inside
│   └── {dev,test,prod}.yaml # per-env non-secrets: workspace name, capacity name, ADO env name
├── pipelines/
│   ├── cicd.yml             # content + control plane (see ado-pipeline.yml)
│   └── admin.yml            # sp-fabric-admin only: roles, tenant settings, scheduled jobs
└── scripts/
    ├── deploy_items.py      # wraps fabric-cicd: FabricWorkspace(...) + publish, one env per run
    └── preflight.py         # fails fast if the workspace is missing before items land
```

Why each top-level folder exists:

- **`terraform/`** — things with a lifecycle and an ID that a content deploy must not recreate:
  workspaces, role assignments, the Git connection, the capacity as an Azure resource. One root
  with a state key and a tfvars file per environment (`terraform workspace` is the alternative,
  and the overloaded word is why the pipeline names state keys instead). If a second root appears,
  split by *lifetime*, not by environment, and keep it small so ADR 0003's "fall back to REST by
  hand" stays cheap.
- **`content/`** — the items, one folder per workspace **without** the environment token, because
  the same definitions deploy to all three and `parameter.yml` supplies the differences. Also where
  the dev workspace's Git integration commits (ADR 0005), so it is the authors' hot path.
- **`config/`** — what differs between environments, out of YAML and HCL, so an environment diff is
  a diff of values, not of logic. No secrets: these are references.
- **`pipelines/`** — one file per authority level. `cicd.yml` runs on merge to `main`; `admin.yml`
  holds the admin principal, so it is separate and gated (ADR 0002). Two files, two approval records.
- **`scripts/`** — the only imperative code: the fabric-cicd call, and a preflight that turns
  "workspace missing" into a one-line failure.

Two ordering facts the folders cannot express: Terraform applies before items land, and `content/`
is written by humans in dev but read by the pipeline.

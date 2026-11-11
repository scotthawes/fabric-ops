# Content layout (illustrative)

**Dated 2026-11-11.** `content/` holds Fabric item definitions in the source-control format — the
one layout Git integration, the item-definition APIs and `fabric-cicd` all read. It is written by
humans (committed out of the dev workspace) and read by the pipeline.

```
content/
└── fabric-sales-forecast/                  # workspace folder, no environment token
    ├── Sales Forecast Ingest.Notebook/
    │   ├── .platform
    │   └── notebook-content.py
    └── Sales Forecast Model.SemanticModel/
        ├── .platform
        ├── definition.pbism
        └── definition/
            ├── model.tmdl
            ├── relationships.tmdl
            └── tables/
                └── Sales.tmdl
```

The folder name is `<item display name>.<ItemType>`: the type suffix is how `fabric-cicd` and Git
integration know what to create. One workspace folder serves all three environments, because the
definitions are identical and the differences are values.

## `.platform`

Every item definition carries a `.platform` part. It is the item's identity card: what type it
is, what it is called, and the schema the rest of the folder follows. It carries **logical**
IDs, not workspace or environment IDs — which is why it survives promotion.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": { "type": "Notebook", "displayName": "Sales Forecast Ingest" },
  "config": { "version": "2.0", "logicalId": "00000000-0000-0000-0000-000000000000" }
}
```

```yaml
# VERIFY: the .platform schema version, the metadata/config key names and whether logicalId is
# required for a non-Git-synced item. Check the Fabric "item definition overview" Learn page
# (docs/research/deployment-mechanism-comparison.md cites it) against a real exported item.
```

## How a definition becomes per-environment values

A definition exported from the portal contains the IDs it was authored against: the dev
workspace's GUID, the dev lakehouse's GUID, sometimes a connection ID. Those are the only things
that must change per environment, and they change by text substitution, not by branching the
folder.

`config/parameter.yml` lists each dev value as `find_value` and gives a `replace_value` per
environment. `fabric-cicd` applies the substitutions in memory at deploy time, then posts the
resulting definition to the target workspace. Nothing in `content/` is rewritten.

| Definition holds | `parameter.yml` replaces it with | Reaches |
| --- | --- | --- |
| dev workspace GUID | `$workspaces.<name>.id`, or a literal per-env GUID | the target workspace's ID |
| dev lakehouse GUID | `$items.Lakehouse.<name>.id`, or a literal per-env GUID | the target lakehouse |
| (nothing else, if the definition is clean) | — | — |

Rules that keep this workable:

- **Only IDs vary.** If a definition needs a per-environment *expression* (a different schema
  name, a different connection), that is a design smell — fix the item, don't grow the parameter
  file.
- **Environment keys must match** the environment name passed to `FabricWorkspace(environment=…)`,
  or the substitution silently does nothing and the item deploys with dev's IDs.
  `# VERIFY:` the exact matching rule in the `fabric-cicd` parameterisation docs.
- **A missing `find_value` is silent.** A GUID that only appears in a report's binding, not in
  the notebook, still needs an entry — check the deployed item in the target workspace, not the
  deploy log, the first time.
- **`test` and `prod` are never authored.** Their items arrive only through this substitution.

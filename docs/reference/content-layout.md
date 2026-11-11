# Content layout (illustrative)

**Dated 2026-11-11.** `content/` holds item definitions in the source-control format — the one
layout Git integration, the item-definition APIs and `fabric-cicd` all read. Humans write it by
committing out of the dev workspace; the pipeline only reads it.

```
content/
└── fabric-sales-forecast/                   # workspace folder, no environment token
    ├── Sales Forecast Ingest.Notebook/
    │   ├── .platform
    │   └── notebook-content.py
    └── Sales Forecast Model.SemanticModel/
        ├── .platform
        └── definition/{model.tmdl, relationships.tmdl, tables/Sales.tmdl}
```

The folder is `<display name>.<ItemType>` — the type suffix is how `fabric-cicd` knows what to
create. One workspace folder serves all three environments; only values differ.

## `.platform`

Every item definition carries a `.platform` part — its identity card. It states the item type,
display name and schema the folder follows, and holds **logical** IDs rather than workspace or
environment IDs, which is why it survives promotion.

```json
{ "$schema": "…/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": { "type": "Notebook", "displayName": "Sales Forecast Ingest" },
  "config": { "version": "2.0", "logicalId": "00000000-0000-0000-0000-000000000000" } }
```

`# VERIFY:` the real `$schema` URL and version, the `metadata`/`config` key names, and whether
`logicalId` is required for a non-Git-synced item. Check the Fabric "item definition overview"
Learn page (cited in `docs/research/deployment-mechanism-comparison.md`) against a real export.

## Per-environment values

A definition exported from the portal contains the IDs it was authored against: the dev workspace
GUID, the dev lakehouse GUID, sometimes a connection ID. Those change per environment by text
substitution, not by branching the folder. `config/parameter.yml` lists each dev value as
`find_value` with a `replace_value` per environment; `fabric-cicd` substitutes in memory at deploy
time, so `content/` is never rewritten.

| Definition holds | `parameter.yml` supplies | Reaches |
| --- | --- | --- |
| dev workspace GUID | `$workspaces.<name>.id`, or a literal per env | the target workspace's ID |
| dev lakehouse GUID | `$items.Lakehouse.<name>.id`, or a literal per env | the target lakehouse |

- **Only IDs vary.** A per-environment expression or a different connection is a smell in the item.
- **Environment keys must match** the name given to `FabricWorkspace(environment=…)`, or the
  substitution does nothing and the item deploys pointing at dev. `# VERIFY:` the matching rule in
  the fabric-cicd parameterisation docs.
- **A missing `find_value` is silent.** A GUID used only in a report binding still needs an entry;
  check the deployed item, not the deploy log.
- **`test` and `prod` are never authored.** Their items arrive only through this substitution.

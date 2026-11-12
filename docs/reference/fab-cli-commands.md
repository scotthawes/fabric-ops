# `fab` CLI: the command surface

**Dated 2026-11-12**, from `microsoft/fabric-cli` `docs/commands/`. This is a *convenience* surface
over APIs already censused — worth knowing, not worth depending on for capability.

## Shape

Nine groups, one standalone command, and a filesystem verb with twenty subcommands:

| Group | Covers | What it wraps |
| --- | --- | --- |
| `acls` | Access control lists for workspaces, items and OneLake | OneLake security APIs |
| `api` | **Raw REST passthrough** to Fabric APIs | Everything the census has |
| `auth` | Authentication methods for the CLI itself | — |
| `config` | CLI settings | — |
| `desc` | Describes other CLI commands and elements | — |
| `jobs` | Start, run, monitor and schedule item jobs | Jobs API |
| `labels` | Sensitivity labels on workspaces, items and data | Labels APIs |
| `tables` | Load, optimise and manage lakehouse tables | OneLake / Delta |
| `find` | Search the OneLake catalogue across workspaces | Catalogue APIs |
| `fs` | A filesystem metaphor over OneLake | OneLake DFS |

`fs` is the interesting one, because it is the only part with real ergonomics: `assign`, `bulk_export`,
`cd`, `cp`, `deploy`, `exists`, `export`, `get`, `import`, `ln`, `ls`, `mkdir`, `mv`, `open`, `pwd`,
`rm`, `set`, `start`, `stop`, `unassign`.

## Why it does not change the audit

- **`fab api` is a passthrough.** Anything the census enumerates is reachable through it and nothing
  more is. A command census of the CLI is a census of convenience, not capability.
- **`fs` is the exception worth remembering** — copying to and from OneLake by path is genuinely
  easier than the DFS API, and it appears nowhere else in our surface list.
- **`deploy` inside `fs`** is worth checking before relying on `fabric-cicd` alone; it may be a second
  route to the same operation.

## What this does not establish

- The exact subcommands of the eight non-`fs` groups: their docs are single index pages describing the
  group, so the surface is not enumerable file-by-file the way `fs` is.
- Whether `fs deploy` duplicates `fabric-cicd` or does something narrower.
- Whether the CLI supports service-principal auth for unattended use — `auth` documents "multiple
  authentication methods", but the specific set was not read here.

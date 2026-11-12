# API operations: the census

**Generated 2026-11-12** from `microsoft/fabric-rest-api-specs` at commit `3f8600f`
(2026-11-10). **825 operations across 61 groups**, in [`api-operations.tsv`](api-operations.tsv).

This exists because the [automation coverage matrix](../guides/automation-coverage.md) classifies
*action families* — about 45 of them — and a family is not a census. This is the census: every
operation the spec declares, one row each.

## What the columns mean

| Column | Meaning |
| --- | --- |
| `group` | The spec directory, which is per **item type** (`lakehouse`, `warehouse`, `eventstream`…) plus two cross-cutting groups, `platform` (published on Learn as **Core**) and `admin` |
| `method`, `path` | As declared, without the `beta` query parameter |
| `operationId` | The generated name, useful when searching the Learn reference |
| `beta` | `yes` where the operation declares a `beta` query parameter |
| `kind` | Mechanical classification: `definition` (path mentions definitions), `job` (jobs/instances), `admin`, `write`, `read` |
| `summary` | The spec's own one-liner |

Mechanical `kind` counts: **357 write**, **256 read**, **112 definition**, **60 admin**, **40 job**.
54 operations carry a `beta` parameter.

## What this census cannot tell you

- **Whether a service principal may call it.** The spec does not carry that reliably; the identity
  tables live in the Learn pages, and 58 operations are documented as SP-unsupported.
- **Whether the operation is usable.** A definition operation for an item type with no public
  create/update support exists in the spec and still cannot be used.
- **What it means.** `POST …/items` appears in many groups with different semantics.

That is why the census and the coverage matrix are separate artefacts: one is exhaustive and dumb, the
other is curated and opinionated. Use this one to find an operation; use the matrix to decide whether
to build on it.

## Reproducing it

```bash
python3 refresh-api-operations.py
```

It clones the specs repository at `main`, walks `*/swagger.json`, and rewrites the TSV. Pin the commit
in a note when you cite counts — the repository moves, and a count without a commit is a rumour.

## Counting disagreements worth knowing about

`fabric-api-inventory.md` reports **835**; this file has **825**. Both are right about different
things: 835 counts operation entries including the duplicated `sqlEndpoint` partial and the admin/Core
pairs that share a `METHOD path`, while this file de-duplicates on `group + method + path`. Neither
number should be quoted without saying which method produced it.

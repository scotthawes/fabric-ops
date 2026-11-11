# AGENTS.md

Conventions for working in this repo. Read `README.md` first, then `GLOSSARY.md`.

## No code in this repo

- This repo is a research artefact (`docs/adr/0001-research-artefact-not-deployment-tool.md`).
  Do not add a package manifest, Terraform root, CI pipeline or deploy script. Reference
  artefacts belong inside a research note, labelled illustrative and dated.
- Read `docs/adr/` before questioning a decision; one that looks odd is usually recorded there.
- Never add credentials, service connections or tenant-specific identifiers.

## Research notes

- One question per file in `docs/research/`, named `<topic>-<question>.md`
  (for example `deployment-what-can-git-integration-sync.md`).
- Start from `docs/research/TEMPLATE.md`.
- **Cite primary sources.** Microsoft Learn pages and the official `microsoft/*` GitHub
  repos. Do not cite blogs, Stack Overflow or other AI output as authority; if a secondary
  source is the only evidence for something, say so in the note.
- Record the date you checked a source. Fabric changes monthly and previews graduate.
- State plainly what the note does *not* establish. A confident wrong answer about tenant
  settings costs more than a gap.

## Glossary

- `GLOSSARY.md` holds project vocabulary, not a Fabric tutorial. One entry per term, two
  sentences maximum, and the term the product actually uses.
- When a term turns out to be overloaded (for example "workspace" for both the Fabric
  workspace and a local checkout), disambiguate it in the glossary rather than inventing
  synonyms.

## ADRs

- Write one when a decision is expensive to reverse, or when a future reader would
  otherwise ask "why on earth". Skip it for naming and formatting.
- Number sequentially, `NNNN-title-with-dashes.md`, starting from the template in
  `docs/adr/README.md`.

## Secrets

- Never commit credentials. Fabric automation needs either an interactive `az login`
  context, a service principal secret, or a federated credential; all three belong in
  `.env` (git-ignored) or the CI secret store.
- Tenant IDs, capacity IDs and workspace IDs are not secrets, but keep them out of commits
  where a placeholder will do.

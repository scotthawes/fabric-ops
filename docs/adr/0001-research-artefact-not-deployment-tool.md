# 0001 — This repo is a research artefact, not a deployment tool

- **Status:** accepted
- **Date:** 2026-11-11
- **Deciders:** Scott

## Context

The Fabric estate to be managed lives in a **work tenant**, which is not reachable from the
machine this repo was created on (`az` there is signed into a personal tenant). Delivery
happens in a separate **work repo**: a human carries the work across and runs it through an
Azure DevOps pipeline using a service connection. The only Fabric instance available for
experimentation is a trial capacity, which is not the production target.

Three alternatives were considered:

1. Build the deployment tool here and copy it into the work repo later. Rejected: it would
   need a second home for credentials, the copy would drift from its origin, and nothing here
   could ever be run to prove it worked.
2. Keep a thin CLI here pointed at the trial capacity. Rejected: the trial capacity is not
   the production tenant, so familiarity with it would produce confident wrong answers about
   the work tenant's tenant settings and permissions.
3. Keep only research and decisions here. Chosen.

## Decision

This repository holds research notes, glossary and ADRs. It contains no credentials, no
infrastructure-as-code root, no pipeline definition and no deployable code. Reference
artefacts (a pipeline stage sketch, a Terraform resource outline, a folder layout) may appear
inside a research note, labelled illustrative and dated; the work repo owns the real ones.

## Consequences

- The pack is safe to hand over and cheap to share: no secrets, no tenant IDs baked into
  configuration.
- Every Fabric claim must stand on a citation rather than on "we tried it", because nothing
  can be tried from here. That raises the bar on `docs/research/` and is the main cost.
- Snippets will rot as the work repo evolves. Each carries the date it was written; treat
  anything older than a few months as a question, not an answer.
- Verification of tenant-specific behaviour (which tenant settings are actually on, whether a
  service principal is permitted) is a human step in the work tenant, and must be written as
  a checklist rather than assumed.

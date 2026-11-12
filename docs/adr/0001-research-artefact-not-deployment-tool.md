# 0001 — This repo is a research artefact, not a deployment tool

- **Status:** accepted
- **Date:** 2026-11-11
- **Amended:** 2026-11-12 — research-only is permanent and not contingent on tenant access
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

## Amendment 2026-11-12 — research-only is the charter, not a circumstance

The Context above gives a contingent reason for this decision: the work tenant was not reachable
from the machine the pack was written on, so building here was impossible as well as inadvisable.
That reading leaves the decision looking like a holding pattern — do research until a tenant
arrives, then build.

**This project is research, permanently.** The decision does not depend on what becomes reachable.
The contingency is struck; the scope is not.

- **Tenant access, if it is ever granted, is an observation instrument.** Reading tenant settings,
  enumerating capacities and inventories, and answering the tracked `needs-info` questions are in
  scope. Creating a capacity, deploying an item, configuring a deployment pipeline or connecting a
  workspace to Git are not — not as a smoke test, not "just the smallest possible one".
- **No work repo follows from this pack.** If somebody builds a Fabric platform, that is a separate
  project with its own charter, its own repository and its own decisions. This pack is an input to
  it. It is not phase 0 of it, and nothing here is owed a build.
- **Consequently, some questions stay permanently open.** Anything whose answer requires performing
  a deployment — whether a service principal needs a Fabric licence, whether the container-then-
  content ordering holds in a real run — is now a recorded gap rather than a pending step. Say
  "not established", not "to be confirmed at first deploy".
- **The run-books are observation instruments, not procedures.** `runbook/01` reads a tenant; it
  does not provision one. `runbook/02` describes how the described platform behaves in steady state;
  it is not an operating commitment this repo makes. `specs/0001` and `0002` remain synthesis, as
  `AGENTS.md` already insists.

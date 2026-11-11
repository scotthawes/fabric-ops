# Architecture decision records

One file per decision that is expensive to reverse. Numbered `NNNN-title-with-dashes.md`,
never renumbered, never deleted — a superseded ADR stays and gains a pointer to its
successor.

## Template

```markdown
# NNNN — <Decision in the imperative>

- **Status:** proposed | accepted | superseded by NNNN
- **Date:** YYYY-MM-DD
- **Deciders:** <who>

## Context

What Forces are in play? Facts, constraints, and the research notes that establish them.

## Decision

What we are doing, in one paragraph, stated as a decision rather than a discussion.

## Consequences

What becomes easy, what becomes hard, and what we are now committed to maintaining.
```

## Index

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-research-artefact-not-deployment-tool.md) | This repo is a research artefact, not a deployment tool | accepted |
| [0002](0002-two-service-principals-federated.md) | Two service principals, federated, split by job | accepted |
| [0003](0003-terraform-control-plane-fabric-cicd-items.md) | Terraform for the control plane, fabric-cicd for items | accepted |
| [0004](0004-one-shared-capacity.md) | One Fabric capacity shared by dev, test and prod | accepted |
| [0005](0005-authoring-and-promotion.md) | Authoring in a bound dev workspace, promotion by pinned commit | accepted |
| [0006](0006-access-through-entra-groups.md) | Access through one Entra security group per workspace | accepted |

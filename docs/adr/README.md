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

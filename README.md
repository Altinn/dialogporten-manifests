# Dialogporten Flux manifests

This repository contains the Flux app configuration and syncroot wiring for Dialogporten on DIS.

## Layout
- `flux/dialogporten`: application manifests (base + environment overlays)
- `flux/syncroot`: Flux `GitRepository` + `Kustomization` wiring per environment

## Environments
The overlays under `flux/dialogporten/overlays/<env>` are referenced from the syncroot kustomizations.
Current environments: `at23`, `tt02`, `yt01`, `prod`.

## Summary
See `docs/summary.md` for a short overview.

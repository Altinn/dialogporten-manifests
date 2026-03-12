# AGENTS.md

## Purpose
This repository stores Dialogporten Flux manifests and wiring after the `main` restructure.

## Current structure (authoritative)
- `manifests/`: app, job, and common bases plus per-environment overlays in `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical reusable app base manifests consumed by each environment overlay.
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays (patch-only).
- `flux/syncroot/`: bootstrap wiring that selects `flux-system/<env>`.
- `.github/workflows/publish-flux-artifacts.yml`: publishes OCI artifacts for syncroot and app manifests.

## Registry model
- Runtime app images: GHCR tags set in `manifests/environments/<env>/kustomization.yaml`.
- Flux manifests artifacts: ACR (`altinncr.azurecr.io`), published as:
  - `dialogporten/dialogporten-sync:main` (app manifests)
  - `dialogporten/syncroot:main` (syncroot)
- Flux app `Kustomization` objects apply environment wrappers directly and do not use `postBuild.substituteFrom`.

## Change hygiene (required)
When changing structure, environments, Flux source wiring, workflow publish logic, or registry/source strategy, update all relevant guidance in the same PR:
- `README.md`
- `docs/summary.md`
- `AGENTS.md`
- `.codex/skills/dialogporten-manifests-maintenance/SKILL.md`
- `.github/workflows/publish-flux-artifacts.yml` (if env list/path/source assumptions change)

## Environment additions/removals
If environment set changes, update all of:
- `flux/syncroot/<env>/kustomization.yaml`
- validation loops in `.github/workflows/publish-flux-artifacts.yml`
- `README.md`, `docs/summary.md`, and this file

## Validation baseline
Run before commit when relevant:
- `kustomize build manifests/environments/at23`
- `kustomize build manifests/environments/tt02`
- `kustomize build manifests/environments/yt01`
- `kustomize build manifests/environments/prod`

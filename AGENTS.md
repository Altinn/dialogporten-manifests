# AGENTS.md

## Purpose
This repository stores Dialogporten Flux manifests and wiring after the `main` restructure.

## Current structure (authoritative)
- `manifests/`: app, job, and common bases plus per-environment overlays in `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical reusable app base manifests consumed by each environment overlay.
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays (patch-only).
- `environments/<env>/`: wrapper kustomizations consumed by Flux app kustomizations.
- `flux-system/<env>/`: environment-scoped `OCIRepository` + app `Kustomization` objects.
- `flux/syncroot/`: bootstrap wiring that selects `flux-system/<env>`.
- `.github/workflows/publish-flux-artifacts.yml`: publishes OCI artifacts for syncroot and app manifests.

## Registry model
- Runtime app images: GHCR tags set in `manifests/environments/<env>/kustomization.yaml`.
- Flux manifests artifacts: ACR (`altinncr.azurecr.io`), published as:
  - `dialogporten/dialogporten-sync:main` (app manifests)
  - `dialogporten/syncroot:main` (syncroot)

## Change hygiene (required)
When changing structure, environments, Flux source wiring, workflow publish logic, or registry/source strategy, update all relevant guidance in the same PR:
- `README.md`
- `docs/summary.md`
- `AGENTS.md`
- `.codex/skills/dialogporten-manifests-maintenance/SKILL.md`
- `.github/workflows/publish-flux-artifacts.yml` (if env list/path/source assumptions change)

## Environment additions/removals
If environment set changes, update all of:
- `environments/<env>/kustomization.yaml`
- `flux-system/<env>/` files
- `flux/syncroot/<env>/kustomization.yaml`
- validation loops in `.github/workflows/publish-flux-artifacts.yml`
- `README.md`, `docs/summary.md`, and this file

## Validation baseline
Run before commit when relevant:
- `kustomize build environments/at23`
- `kustomize build environments/tt02`
- `kustomize build environments/yt01`
- `kustomize build environments/prod`
- `kustomize build flux/syncroot/at23`
- `kustomize build flux/syncroot/tt02`
- `kustomize build flux/syncroot/yt01`
- `kustomize build flux/syncroot/prod`
- `kustomize build flux-system/at23`
- `kustomize build flux-system/tt02`
- `kustomize build flux-system/yt01`
- `kustomize build flux-system/prod`

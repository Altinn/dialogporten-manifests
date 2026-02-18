---
name: dialogporten-manifests-maintenance
description: Use when changing Dialogporten manifests structure, Flux wiring, environment set, or publish workflow. Ensures workflow/docs/agent guidance stay in sync after updates.
---

# Dialogporten Manifests Maintenance

## Use this skill when
- Changing folder structure under `manifests/`, `environments/`, `flux-system/`, or `flux/syncroot/`.
- Changing registry/source strategy for manifests or syncroot artifacts.
- Adding/removing environments.
- Updating `.github/workflows/publish-flux-artifacts.yml` behavior.

## Required update set
For relevant changes, update these files in the same PR:
- `README.md`
- `docs/summary.md`
- `AGENTS.md`
- `.github/workflows/publish-flux-artifacts.yml`
- `skills/dialogporten-manifests-maintenance/SKILL.md`

## Registry/source invariants
- Runtime app images are GHCR-hosted and pinned via `manifests/environments/<env>/kustomization.yaml`.
- Flux manifests/sync artifacts are OCI artifacts in ACR:
  - `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync:main`
  - `oci://altinncr.azurecr.io/dialogporten/syncroot:main`

## Environment checklist
If environment set changes, update:
- `environments/<env>/kustomization.yaml`
- `flux-system/<env>/`
- `flux/syncroot/<env>/kustomization.yaml`
- validation loops in `.github/workflows/publish-flux-artifacts.yml`
- environment lists in docs/guidance files

## Validation
Run:
- `kustomize build flux/syncroot/at23`
- `kustomize build flux/syncroot/tt02`
- `kustomize build flux/syncroot/yt01`
- `kustomize build flux/syncroot/prod`
- `kustomize build flux-system/at23`
- `kustomize build flux-system/tt02`
- `kustomize build flux-system/yt01`
- `kustomize build flux-system/prod`

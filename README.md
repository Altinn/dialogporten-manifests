# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/base`: single common app base; each app overlay (`manifests/apps/<app>/`) patches names, image, ingress path, and any app-specific env/HPA tweaks.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `environments/<env>/`: thin wrapper kustomization that points Flux to the corresponding `manifests/environments/<env>` (keeps the old `clusters/<env>` path shape, now renamed).
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` definitions that point Flux at `./environments/<env>` (which in turn includes `manifests/environments/<env>`) inside the OCI artifact.
- `flux/syncroot/`: bootstrap wiring (namespace, `OCIRepository`, and a Kustomization that targets the chosen `flux-system/<env>` path).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`): syncroot from `flux/syncroot` and app manifests from the repository root.
2. `flux-system/<env>/ocirepository.yaml` points to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls that OCI artifact, and `dialogporten-apps-<env>` applies `environments/<env>` (which loads `manifests/environments/<env>`) with substitutions from `dialogporten-flux-substitutions`.

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.
Local maintenance skill: `skills/dialogporten-manifests-maintenance/SKILL.md`.

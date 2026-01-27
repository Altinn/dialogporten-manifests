# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `environments/<env>/`: thin wrapper kustomization that points Flux to the corresponding `manifests/environments/<env>` (keeps the old `clusters/<env>` path shape, now renamed).
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` definitions that point Flux at `./environments/<env>` (which in turn includes `manifests/environments/<env>`) inside the OCI artifact.
- `flux/syncroot/`: bootstrap wiring (namespace, GitRepository pointing to this repo, and a Kustomization that targets the chosen `flux-system/<env>` path).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. Package the repo (or at least `manifests/`) into an OCI artifact, e.g. `ghcr.io/altinn/dialogporten-manifests:${ENV}-${SHORT_SHA}`.
2. Update `flux-system/<env>/ocirepository.yaml` `spec.ref.tag` to the new tag (CI can do this).
3. Flux pulls the OCI artifact via `OCIRepository`, and `dialogporten-apps-<env>` applies `environments/<env>` (which loads `manifests/environments/<env>`) with secret/config substitutions.

See `docs/summary.md` for more detail.

# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) with per-environment patches under `.../environments/<env>/`.
- `clusters/<env>/`: kustomization that stitches together the env-specific overlays and image tags for one environment.
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` definitions that point Flux at the OCI artifact for that environment.
- `flux/syncroot/`: bootstrap wiring (namespace, GitRepository pointing to this repo, and a Kustomization that targets the chosen `flux-system/<env>` path).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. Package the repo (or at least `clusters/<env>` + `manifests/`) into an OCI artifact, e.g. `ghcr.io/altinn/dialogporten-manifests:${ENV}-${SHORT_SHA}`.
2. Update `flux-system/<env>/ocirepository.yaml` `spec.ref.tag` to the new tag (CI can do this).
3. Flux pulls the OCI artifact via `OCIRepository`, and `dialogporten-apps-<env>` applies `clusters/<env>` with secret/config substitutions.

See `docs/summary.md` for more detail.

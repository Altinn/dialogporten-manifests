# Dialogporten Flux manifests summary

This repo now separates workload definitions, environment overlays, and Flux wiring to support OCI-delivered manifests.

## Structure
- `manifests/`: Bases for apps, jobs, and common config. Environment patches live under each workload in `environments/<env>/`.
- `clusters/<env>/`: Kustomization that composes the env overlays and image tags; this is what gets packaged to OCI.
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` per environment, pointing at `./clusters/<env>` inside the OCI artifact.
- `flux/syncroot/`: Bootstrap namespace + GitRepository (this repo) + Kustomization that selects the right `flux-system/<env>` path.

## Flow
1. CI builds an OCI artifact per environment (e.g. `ghcr.io/altinn/dialogporten-manifests:${ENV}-${SHORT_SHA}`) that includes `clusters/` + `manifests/`.
2. CI updates `flux-system/<env>/ocirepository.yaml` `spec.ref.tag` to the new tag.
3. Flux pulls the OCI artifact and `dialogporten-apps-<env>` applies the manifests with substitutions from `dialogporten-flux-substitutions`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

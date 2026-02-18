# Dialogporten Flux manifests summary

This repo now separates workload definitions, environment overlays, and Flux wiring to support OCI-delivered manifests.

## Structure
- `manifests/`: Bases for apps, jobs, and common config. Per-environment overlays now live under `manifests/environments/<env>/` (apps + jobs grouped by env).
- `manifests/environments/<env>/`: Env entrypoint that pulls all overlays and sets image tags.
- `manifests/apps/base`: Single common app base; app overlays under `manifests/apps/<app>/` patch names, images, ingress, env, and HPA differences.
- `environments/<env>/`: Thin wrapper kustomization that simply references `manifests/environments/<env>`; Flux paths can target this.
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` per environment, pointing at `./environments/<env>` inside the OCI artifact.
- `flux/syncroot/`: Bootstrap namespace + `OCIRepository` + Kustomization that selects the right `flux-system/<env>` path.

## Flow
1. CI builds an OCI artifact per environment (e.g. `ghcr.io/altinn/dialogporten-manifests:${ENV}-${SHORT_SHA}`) that includes `manifests/`.
2. CI updates `flux-system/<env>/ocirepository.yaml` `spec.ref.tag` to the new tag.
3. Flux pulls the OCI artifact and `dialogporten-apps-<env>` applies `environments/<env>` (which loads `manifests/environments/<env>`) with substitutions from `dialogporten-flux-substitutions`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

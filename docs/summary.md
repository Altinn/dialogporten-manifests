# Dialogporten Flux manifests summary

This repo now separates workload definitions, environment overlays, and Flux wiring to support OCI-delivered manifests.

## Structure
- `manifests/`: Bases for apps, jobs, and common config. Per-environment overlays now live under `manifests/environments/<env>/` (apps + jobs grouped by env).
- `manifests/environments/<env>/`: Env entrypoint that pulls all overlays and sets image tags.
- `manifests/apps/<app>/base/`: Canonical per-app base manifests used by environment overlays.
- `manifests/environments/<env>/apps/<app>/`: Per-env app overlays that patch app bases.
- `environments/<env>/`: Thin wrapper kustomization that simply references `manifests/environments/<env>`; Flux paths can target this.
- `flux-system/<env>/`: Flux `OCIRepository` + `Kustomization` per environment, pointing at `./environments/<env>` inside the OCI artifact.
- `flux/syncroot/`: Bootstrap namespace + `OCIRepository` + Kustomization that selects the right `flux-system/<env>` path.

## Flow
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`) on every commit to `main`.
2. `flux-system/<env>/ocirepository.yaml` points to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls the OCI artifact and `dialogporten-apps-<env>` applies `environments/<env>` (which loads `manifests/environments/<env>`) directly (no `postBuild` substitutions).
4. Application container images remain on GHCR and are pinned in `manifests/environments/<env>/kustomization.yaml`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

Change-maintenance rules are defined in `AGENTS.md` and `.codex/skills/dialogporten-manifests-maintenance/SKILL.md`.

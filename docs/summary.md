# Dialogporten Flux manifests summary

This repo now separates workload definitions, environment overlays, and Flux wiring to support OCI-delivered manifests.

## Structure
- `manifests/`: Bases for apps, jobs, and common config. Per-environment overlays now live under `manifests/environments/<env>/` (apps + jobs grouped by env).
- `manifests/environments/<env>/`: Env entrypoint that pulls all overlays and sets image tags.
- `manifests/apps/<app>/base/`: Canonical per-app base manifests used by environment overlays.
- `manifests/environments/<env>/apps/<app>/`: Per-env app overlays that patch app bases.
- `flux/syncroot/`: Bootstrap namespace + `OCIRepository` + Kustomization that selects the right `./environments/<env>` path within the manifests artifact.

## Flow
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`) on every commit to `main`.
2. `flux/syncroot/` defines an `OCIRepository` pointing to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls the OCI artifact and the environment-specific `Kustomization` in `flux/syncroot/<env>` targets the `./environments/<env>` path within the artifact.
4. Application container images remain on GHCR and are pinned in `manifests/environments/<env>/kustomization.yaml`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## Workflow failure alerts

- `workflow-update-all-image-tags.yml` updates tags from `repository_dispatch` and explicitly dispatches `publish-flux-artifacts.yml` after pushing a change. Its failure notification depends on the entire update job, including input validation and the publish dispatch.
- `publish-flux-artifacts.yml` runs on pushes to `main` and manual dispatch. Its failure notification waits for both `publish-syncroot` and `publish-app-manifests`, reports both results, and sends one alert if either job fails.
- Both use `workflow-send-ci-cd-status-slack-message.yml`, following Dialogporten's CI/CD Slack convention. The reusable workflow needs `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS` available to this repository; see [Failure notifications](../README.md#failure-notifications) for setup.
- Alerts contain operation context and a link to the failing run. They run without checkout or tool installation, JSON-encode dynamic text, and fail visibly on Slack delivery errors. Successful, skipped, and cancelled runs remain silent.

Change-maintenance rules are defined in `AGENTS.md` and `.codex/skills/dialogporten-manifests-maintenance/SKILL.md`.

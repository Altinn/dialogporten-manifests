---
name: dialogporten-manifests-maintenance
description: Maintain this repository's Dialogporten Flux manifests, environment overlays, and image-update and artifact-publishing workflows.
---

# Dialogporten manifests maintenance

Read `AGENTS.md`, `README.md`, and `docs/summary.md` for the repository layout and required change hygiene.

## Manifest and publishing invariants

- Keep reusable app manifests in `manifests/apps/<app>/base/`; environment app overlays are patch-only. Environment entrypoints in `manifests/environments/<env>/kustomization.yaml` set GHCR runtime image tags.
- Flux manifests artifacts use ACR (`altinncr.azurecr.io`). App Flux Kustomizations select the environment wrapper directly without `postBuild.substituteFrom`.
- Every `flux/syncroot/<env>/kustomization.yaml` must patch `spec.path` to `./environments/<env>`; the base otherwise selects `at23`.
- Preserve the explicit publish workflow dispatch after image-tag changes: pushes made with `GITHUB_TOKEN` do not trigger the publish workflow's push event.

## Failure alerts

- Keep a failure notification dependent on the full image-update job, including validation, push, and publish dispatch.
- Keep a single publishing failure notification dependent on both artifact jobs and include both results.
- Use `workflow-send-ci-cd-status-slack-message.yml`, gated by `failure() && !cancelled()`, with `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS` supplied by callers. Successful, skipped, and cancelled runs stay silent.
- Preserve JSON encoding and plain-text Slack blocks for dynamic event data so rejected inputs cannot break the notification payload. Keep `errors: true` so Slack delivery failures are visible.
- The notifier runs without checkout or tool installation, allowing failures in those operations to be reported.

## Validation and guidance

Run `actionlint` for workflow changes and the relevant Kustomize builds listed in `AGENTS.md` for manifest changes. When environments change, validate every syncroot overlay selects its own environment and update the workflow validation loops.

Update `README.md`, `docs/summary.md`, `AGENTS.md`, and this skill together when changing structure, environments, source strategy, or publishing logic.

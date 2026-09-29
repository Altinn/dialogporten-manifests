# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. CI publishes OCI artifacts with environment tags; Flux selects the matching environment overlay from each artifact.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical per-app base manifests (`web-api-eu`, `web-api-so`, `graphql`, `service`), aligned with job base layout (`manifests/jobs/<job>/base/`).
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays that only patch app bases.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `flux/syncroot/`: bootstrap wiring (`OCIRepository` and a Kustomization that targets `./environments/<env>` inside the app artifact).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)

1. Every push to `main` builds the app artifact from `manifests/` and tags it as `dialogporten/dialogporten-sync:<env>` for all four environments: `at23`, `tt02`, `yt01`, and `prod`.
2. After the app tags are published, CI builds the syncroot from `flux/syncroot` and publishes the same four tags under `dialogporten/syncroot:<env>`. Each artifact is built once; its environment tags point to the same digest. Manual publishing from `main` follows the same flow.
3. The core bootstrap consumes `dialogporten/syncroot:<env>` at `./<env>`. That overlay selects `dialogporten/dialogporten-sync:<env>` and applies `./environments/<env>` inside the app artifact.

Publishing refreshes all environment tags on every run. Each environment keeps the runtime image versions declared in its own overlay. The former app artifact tag `:main` is no longer updated; application tags are published first so the syncroot can safely switch consumers to environment tags.

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`.

## Failure notifications

`Update all image tags` and `Publish Flux artifacts` send one Slack alert per failed workflow run through `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`. Alerts include the repository, workflow, job results, a link to the run, and the requested environment/image tag or published ref/commit. Image-update alerts also cover input validation, checkout, tool installation, push, and publish-dispatch failures. Publishing alerts cover either artifact job, including validation failures. Successful, skipped, and cancelled runs do not send alerts.

Make these GitHub Actions secrets available to this repository, using the same names as Dialogporten's CI/CD notifications:

- `SLACK_BOT_TOKEN`: Slack bot token with permission to post to the CI/CD status channel.
- `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`: ID of that channel; the bot must have access to it.

Slack delivery errors fail the notification job so an undelivered alert is visible in Actions.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.

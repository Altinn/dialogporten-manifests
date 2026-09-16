# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical per-app base manifests (`web-api-eu`, `web-api-so`, `graphql`, `service`), aligned with job base layout (`manifests/jobs/<job>/base/`).
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays that only patch app bases.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `flux/syncroot/`: bootstrap wiring (namespace, `OCIRepository`, and a Kustomization that targets the chosen `flux-system/<env>` path).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## Node sizing by environment

[`manifests/common/large-node-pool`](manifests/common/large-node-pool/kustomization.yaml)
is a Kustomize component used by at23, tt02, and prod. It adds
`dis.altinn.cloud/node-class=large` as both a node selector and a `NoSchedule`
toleration to **only `reindex-dialogsearch-job`**. Jobs created manually from
that CronJob inherit the settings. Regular apps and other jobs use the general pool.

The `core` repository owns the generic `largepool` and its matching label/taint.
Every large pool uses `Standard_D8ads_v6`, autoscaling from **0 to 10 nodes**.
Reindex requests 4 CPUs; a D4 node has less than 4 CPUs available for Pods after
AKS reservations. Normal production app containers request 2 CPUs, so the core
production general pool uses D4 nodes.

| Manifest environment | Dialogporten ACA reference | Core general pool | Core large pool |
| --- | --- | --- | --- |
| at23 | test: Consumption | D4 | D8, 0–10 nodes |
| tt02 | staging: Consumption | D2 | D8, 0–10 nodes |
| prod | Consumption + D8, 3–10 nodes | D4 | D8, 0–10 nodes |
| yt01 | Consumption + D8, 3–10 nodes | Target cluster not defined in core | Scheduling component not enabled |

The ACA reference is `.azure/infrastructure/` and `.azure/applications/` in the
Dialogporten application repo. Only `web-api-eu`, `web-api-so`, and `graphql`
select ACA's dedicated D8 profile in prod and yt01; the service and jobs use
Consumption. AKS placement follows current Pod requests, with larger nodes
reserved for the reindex job and a zero-node minimum to avoid idle job capacity.

Provision the core pools **before** publishing these manifests. When reindex
starts, the autoscaler can create a large node; allow for provisioning time in
the job deadline. Verify required platform DaemonSets tolerate the taint and
confirm the pool scales down after the job completes. Keep the generic label and
taint consistent across repositories. Enable the component for yt01 once its
target core cluster and large pool are configured.

## OCI flow (high level)
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`): syncroot from `flux/syncroot` and app manifests from `manifests/`.
2. `flux/syncroot/` defines an `OCIRepository` pointing to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls that OCI artifact, and the environment-specific `Kustomization` in `flux/syncroot/<env>` targets the `./environments/<env>` path within the artifact.

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`.

## Failure notifications

`Update all image tags` and `Publish Flux artifacts` send one Slack alert per failed workflow run through `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`. Alerts include the repository, workflow, job results, a link to the run, and the requested environment/image tag or published ref/commit. Image-update alerts also cover input validation, checkout, tool installation, push, and publish-dispatch failures. Publishing alerts cover either artifact job, including validation failures. Successful, skipped, and cancelled runs do not send alerts.

Make these GitHub Actions secrets available to this repository, using the same names as Dialogporten's CI/CD notifications:

- `SLACK_BOT_TOKEN`: Slack bot token with permission to post to the CI/CD status channel.
- `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`: ID of that channel; the bot must have access to it.

Slack delivery errors fail the notification job so an undelivered alert is visible in Actions.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.

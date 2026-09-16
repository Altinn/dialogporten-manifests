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

## Node pools and scheduling

The at23, tt02, and prod entrypoints include the shared
`manifests/common/large-node-pool` component. It selects
`dis.altinn.cloud/node-class=large` and tolerates its `NoSchedule` taint only on
the `reindex-dialogsearch-job` Pod template. Jobs created from that CronJob use
the same settings. Regular Deployments and other CronJobs use the general pool.

Core provisions generic D8 `largepool` nodes with a 0–10 autoscaling range in
all three environments. The general pools are D4 in at23/prod and D2 in tt02.
This accommodates reindex's 4-CPU request and lets the large pools return to zero
between runs. The ACA reference uses Consumption for test/staging and adds a
D8 profile with 3–10 nodes in prod/yt01; the AKS minimum is deliberately zero.

Provision the pools before publishing the scheduling component. Yt01's core
cluster is not defined in the linked core checkout, so its scheduling is left
unchanged until that target is configured. See
[Node sizing by environment](../README.md#node-sizing-by-environment) for details.

## Workflow failure alerts

- `workflow-update-all-image-tags.yml` updates tags from `repository_dispatch` and explicitly dispatches `publish-flux-artifacts.yml` after pushing a change. Its failure notification depends on the entire update job, including input validation and the publish dispatch.
- `publish-flux-artifacts.yml` runs on pushes to `main` and manual dispatch. Its failure notification waits for both `publish-syncroot` and `publish-app-manifests`, reports both results, and sends one alert if either job fails.
- Both use `workflow-send-ci-cd-status-slack-message.yml`, following Dialogporten's CI/CD Slack convention. The reusable workflow needs `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS` available to this repository; see [Failure notifications](../README.md#failure-notifications) for setup.
- Alerts contain operation context and a link to the failing run. They run without checkout or tool installation, JSON-encode dynamic text, and fail visibly on Slack delivery errors. Successful, skipped, and cancelled runs remain silent.

Change-maintenance rules are defined in `AGENTS.md`.

## Scaling model
Apps autoscale with KEDA (`ScaledObject`, `keda.sh/v1alpha1`) rather than a plain
`HorizontalPodAutoscaler`. This mirrors the Container Apps `scale` rules in the
`dialogporten` repo (`.azure/applications/<app>/main.bicep`), which are KEDA rules
underneath, so both platforms stay on the same numbers during the migration.

| App | CPU trigger | Memory trigger | max replicas |
| --- | --- | --- | --- |
| `web-api-eu` | 50% | 70% | 20 |
| `web-api-so` | 70% | 70% | 10 |
| `graphql` | 70% | 70% | 10 |
| `service` | 70% | 70% | 10 |

`minReplicaCount` is 1 in every environment except `prod`, which patches it to 2
via `scaledobject-min.yaml`.

Container `resources` live in the app base at 1 CPU / 2Gi (requests == limits, as
Container Apps does); `yt01` and `prod` override to 2 CPU / 4Gi. The requests are
required, not cosmetic: KEDA's cpu/memory triggers read utilisation as a share of
the request, and report `<unknown>` without one.

Notes:
- KEDA (AKS managed add-on) must be present in the target cluster; the `ScaledObject`
  CRD is a hard dependency of these manifests.
- KEDA's admission webhook rejects a `ScaledObject` whose target Deployment is still
  owned by another HPA, so any pre-existing `HorizontalPodAutoscaler` must be deleted
  before these manifests reconcile.
- Use trigger-level `metricType: Utilization`. The `metadata.type` form used by the
  bicep templates was removed in KEDA 2.18.

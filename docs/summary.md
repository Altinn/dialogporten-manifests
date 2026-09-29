# Dialogporten Flux manifests summary

This repo now separates workload definitions, environment overlays, and Flux wiring to support OCI-delivered manifests.

## Structure
- `manifests/`: Bases for apps, jobs, and common config. Per-environment overlays now live under `manifests/environments/<env>/` (apps + jobs grouped by env).
- `manifests/environments/<env>/`: Env entrypoint that pulls all overlays and sets image tags.
- `manifests/apps/<app>/base/`: Canonical per-app base manifests used by environment overlays.
- `manifests/environments/<env>/apps/<app>/`: Per-env app overlays that patch app bases.
- `flux/syncroot/`: Bootstrap `OCIRepository` + Kustomization that selects the right `./environments/<env>` path within the manifests artifact.

## Flow

1. Every commit to `main` publishes the complete app bundle to `dialogporten/dialogporten-sync` in ACR (`altinncr.azurecr.io`) with all environment tags: `at23`, `tt02`, `yt01`, and `prod`.
2. Once every app tag is available, CI publishes the complete `flux/syncroot` bundle to `dialogporten/syncroot` with the same tags. Each bundle is built once, then tagged for every directory under `manifests/environments/`.
3. Core selects syncroot tag `<env>` and path `./<env>`. Its `OCIRepository` selects app tag `<env>`, and its application Kustomization selects `./environments/<env>` inside the app bundle. CI checks both the tag and path.
4. Application container images remain on GHCR and are pinned in `manifests/environments/<env>/kustomization.yaml`. Refreshing all OCI tags does not change those per-environment image choices.

The former app tag `:main` is no longer refreshed. Publishing app tags before syncroot tags lets existing consumers switch without referencing unpublished tags. A failure while tagging can leave some tags advanced; the workflow reports failure and can be rerun.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## Workflow failure alerts

- `workflow-update-all-image-tags.yml` updates tags from `repository_dispatch` and explicitly dispatches `publish-flux-artifacts.yml` after pushing a change. Its failure notification depends on the entire update job, including input validation and the publish dispatch.
- `publish-flux-artifacts.yml` runs on pushes to `main` and manual dispatch. It publishes app tags before syncroot tags. Its failure notification waits for both `publish-syncroot` and `publish-app-manifests`, reports both results, and sends one alert if either job fails.
- Both use `workflow-send-ci-cd-status-slack-message.yml`, following Dialogporten's CI/CD Slack convention. The reusable workflow needs `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS` available to this repository; see [Failure notifications](../README.md#failure-notifications) for setup.
- Alerts contain operation context and a link to the failing run. They run without checkout or tool installation, JSON-encode dynamic text, and fail visibly on Slack delivery errors. Successful, skipped, and cancelled runs remain silent.

Change-maintenance rules are defined in `AGENTS.md`.

## Routing
Public traffic reaches Dialogporten through the edge proxy for `platform.<env>.altinn.cloud`,
which owns the `/dialogporten` mount point: it strips the prefix and forwards to
`dialogporten.<env>.dis-core.altinn.cloud`. Dialogporten is not published through APIM on
dis-core. On its own host, Traefik routes the apps' native paths without rewrites, like every
other product on dis-core; the apps never strip `/dialogporten` themselves.

| Path | App |
| --- | --- |
| `/api/v{n}/enduser`, any API version | `web-api-eu` |
| `/graphql` (including `/graphql/stream`) | `graphql` |
| `/` (everything else) | `web-api-so` |

`service` serves nothing but health checks, so it has no route.

Linkerd reserves only the kubelet's probe paths (`/health/startup`, `/health/liveness`,
`/health/readiness`) for the node network (`manifests/common/base/linkerd-policies.yaml`).
Everything else, including `/health` and `/health/deep`, is open to the same callers as the
API, so availability checks from outside (for example through the dis edge) can read
`web-api-so`'s health via the `/` route. The split keeps node traffic off the API; it does not
keep other callers off the probe paths, because Linkerd matches paths case-sensitively and
ASP.NET routing does not (`/Health/liveness` arrives via `/`).

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

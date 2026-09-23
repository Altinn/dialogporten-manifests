# AGENTS.md

## Purpose
This repository stores Dialogporten Flux manifests and wiring after the `main` restructure.

## Current structure (authoritative)
- `manifests/`: app, job, and common bases plus per-environment overlays in `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical reusable app base manifests consumed by each environment overlay.
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays (patch-only).
- `flux/syncroot/`: bootstrap wiring that selects `flux-system/<env>`.
- `.github/workflows/publish-flux-artifacts.yml`: publishes OCI artifacts for syncroot and app manifests.
- `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`: reusable failure alerts for image-tag updates and artifact publishing.

## Registry model
- Runtime app images: GHCR tags set in `manifests/environments/<env>/kustomization.yaml`.
- Flux manifests artifacts: ACR (`altinncr.azurecr.io`), published as:
  - `dialogporten/dialogporten-sync:main` (app manifests)
  - `dialogporten/syncroot:main` (syncroot)
- Flux app `Kustomization` objects apply environment wrappers directly and do not use `postBuild.substituteFrom`.

## Workflow failure notifications

- Image-tag update alerts must cover the entire `update-tags` job, including validation, push, and publish dispatch.
- Artifact publishing alerts must depend on both `publish-syncroot` and `publish-app-manifests` and report both results in one message.
- Keep notifications gated by `failure() && !cancelled()` so successful, skipped, and cancelled runs stay silent.
- Reuse `workflow-send-ci-cd-status-slack-message.yml` with `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`. Keep dynamic payload values JSON-encoded and Slack delivery errors visible as job failures.

## Change hygiene (required)
When changing structure, environments, Flux source wiring, workflow publish logic, or registry/source strategy, update all relevant guidance in the same PR:
- `README.md`
- `docs/summary.md`
- `AGENTS.md`
- `.github/workflows/publish-flux-artifacts.yml` (if env list/path/source assumptions change)

## Environment additions/removals
If environment set changes, update all of:
- `flux/syncroot/<env>/kustomization.yaml` — must patch `spec.path` to `./environments/<env>`.
  The base pins `spec.path` to `at23`, so an overlay that omits the patch silently
  deploys at23's manifests. CI enforces this in both `pull-request.yml` and the
  `publish-syncroot` job of `publish-flux-artifacts.yml`.
- validation loops in `.github/workflows/publish-flux-artifacts.yml`
- `README.md`, `docs/summary.md`, and this file

## Scaling model
- Apps autoscale via KEDA `ScaledObject` (`keda.sh/v1alpha1`) in each app base, not a
  plain `HorizontalPodAutoscaler`. Values mirror the Container Apps `scale` rules in
  the `dialogporten` repo (`.azure/applications/<app>/main.bicep`) — keep the two in
  sync until the bicep path is retired. See `docs/summary.md` for the table.
- Per-env changes are patch-only: `scaledobject-min.yaml` for `minReplicaCount`,
  `deployment-resources.yaml` for CPU/memory.
- Do not drop container `resources.requests`. KEDA's cpu/memory triggers are a share
  of the request; without it the autoscaler reports `<unknown>` and never scales.
- The `ScaledObject` CRD is a hard dependency — a cluster without the KEDA add-on will
  fail to reconcile these manifests.

## Routing model
- The edge proxy strips the public `/dialogporten` mount point; the HTTPRoutes on
  `dialogporten.<env>.dis-core.altinn.cloud` match the apps' native paths without rewrites.
  See `docs/summary.md` for the path table.
- Match with `PathPrefix`. The exception is `web-api-eu`, whose anchored `RegularExpression`
  catches every API version. Traefik evaluates regex with Go's unanchored `MatchString`, so
  keep the `^...$` anchors: a bare `enduser` pattern also matches the service-owner
  `endusercontext` endpoints. Traefik ranks regex routes by pattern length rather than
  specificity, so check precedence when adding a route that overlaps it.
- Keep the prefix out of the apps (no `UsePathBase`): the edge owns `/dialogporten`, and the
  Linkerd routes in `manifests/common/base/linkerd-policies.yaml` match native paths.
- Only the probe paths (`/health/startup`, `/health/liveness`, `/health/readiness`) are
  reserved for the kubelet, as `Exact` matches; `/health` and `/health/deep` are open to the
  same callers as the API, including external availability checks through Traefik. Keep probe
  matches exact and longer than any overlapping match: before Linkerd edge-26.9.1 the proxy
  ranks path matches by length alone. A new probe path must be added to the
  `dialogporten-health` route in `manifests/common/base/linkerd-policies.yaml`, or the kubelet
  gets 403 on it and that probe fails. Linkerd matches paths case-sensitively and ASP.NET does
  not, so `/Health/liveness` still arrives via `/`: the split is not access control.

## Validation baseline
Run before commit when relevant:
- `actionlint` for workflow changes
- `kustomize build manifests/environments/at23`
- `kustomize build manifests/environments/tt02`
- `kustomize build manifests/environments/yt01`
- `kustomize build manifests/environments/prod`

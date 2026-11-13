# AGENTS.md

## Purpose
This repository stores Dialogporten Flux manifests and wiring after the `main` restructure.

## Current structure (authoritative)
- `manifests/`: app, job, and common bases plus per-environment overlays in `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical reusable app base manifests consumed by each environment overlay.
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays (patch-only).
- `manifests/environments/<env>/migration/`: the database migration `Job` for the env, applied by its own Flux Kustomization. See [Migration ordering](#migration-ordering).
- `flux/syncroot/`: bootstrap wiring that selects `flux-system/<env>`, with two Flux Kustomizations: `dialogporten-migration` and `dialogporten-apps`. The `at23` overlay also has the `Receiver` for on-demand reconcile, makes `dialogporten-apps` wait for its rollout, and sends rollout results to `Altinn/dialogporten`. See [Rollout health checks](#rollout-health-checks) and [Flux results](#flux-results).
- `flux/edge-syncroot/`: edge proxy routes (`Backend`, `BackendTLSPolicy`, `HTTPRoute`) per environment. The base uses `*.placeholder.invalid` hostnames and every `<env>` overlay must patch all of them; the `publish-edge-syncroot` job fails if any placeholder survives. `tt02` and `prod` include `components/platform-apim`, which routes through the old APIM via the platform-owned `platform/platform-upstream` `Backend`; reference it, do not redefine it. The cross-namespace `backendRef` needs a `ReferenceGrant` in the `platform` namespace.
- `.github/workflows/publish-flux-artifacts.yml`: publishes OCI artifacts for syncroot and app manifests.
- `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`: reusable failure alerts for image-tag updates and artifact publishing.

## Registry model
- Runtime app images: GHCR tags set in `manifests/environments/<env>/kustomization.yaml`. Exception: the feature-metrics collector image is pinned in `manifests/common/base/feature-metrics-collector.yaml`; do not move it to `images:`, which CI overwrites with the app tag.
- Migration bundle: GHCR tag set in `manifests/environments/<env>/migration/kustomization.yaml`. `workflow-update-all-image-tags.yml` must update that file together with the env `kustomization.yaml`.
- Flux manifests artifacts: ACR (`altinncr.azurecr.io`), published as:
  - `dialogporten/dialogporten-sync:main` (app manifests)
  - `dialogporten/syncroot:<env>` (syncroot; envs listed in the `publish-syncroot` matrix). See [Syncroot publishing](#syncroot-publishing).
  - `dialogporten/edge-syncroot:<env>` (edge-syncroot; envs listed in the `publish-edge-syncroot` matrix)
- Flux app `Kustomization` objects apply environment wrappers directly and do not use `postBuild.substituteFrom`.

## Syncroot publishing

- `publish-syncroot` pushes only when `flux/syncroot` differs from the published `dialogporten/syncroot:<env>` artifact, checked with `flux diff artifact`. Every new artifact makes the platform's syncroot Kustomization reconcile and wait for `dialogporten-apps`, and that wait times out during slow rollouts. See `docs/summary.md#syncroot-publishing`.
- Keep comparison errors counting as a difference, so a missing tag, for example for a new environment, still publishes.

## Workflow failure notifications

- Image-tag update alerts must cover the entire `update-tags` job, including validation, push, and publish dispatch.
- Artifact publishing alerts must depend on `publish-syncroot`, `publish-edge-syncroot`, and `publish-app-manifests` and report all results in one message.
- Keep notifications gated by `failure() && !cancelled()` so successful, skipped, and cancelled runs stay silent.
- Reuse `workflow-send-ci-cd-status-slack-message.yml` with `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`. Keep dynamic payload values JSON-encoded and Slack delivery errors visible as job failures.

## On-demand reconcile

- `publish-flux-artifacts.yml` asks the cluster to fetch a new app artifact right after publishing, through the `Receiver` in `flux/syncroot/at23/dialogporten-receiver.yaml`. See `docs/summary.md` for the flow.
- Keep the `Trigger Flux reconcile` step after the step that pushes and tags the app artifact, and keep `continue-on-error: true`. Polling is the fallback; a failed trigger must not fail publishing or raise a Slack alert.
- The step runs only for the environment passed as the `environment` dispatch input, and only for environments in its `if:` list. `workflow-update-all-image-tags.yml` must keep passing `-f environment=...`.
- Put a `Receiver` only in the overlay of an environment whose cluster runs Flux 2.9 or later, not in `flux/syncroot/base/`. An older cluster rejects the `generic-oidc` type, and the syncroot then fails to apply.
- The `Receiver` audience must be the webhook endpoint of its environment, `https://ops.<env>.dis.altinn.cloud/flux-webhook`. The step sends the request to that URL, and the action uses it as the token audience.
- To enable another environment, add a `Receiver` to `flux/syncroot/<env>/` and add the environment to the `if:` list of the step.
- The `Receiver` lists only the `OCIRepository`. Do not add the `Kustomization`: it reconciles when the source revision changes, and triggering it directly can run it before the new artifact is fetched.
- The `Receiver` validations pin this repository by numeric id and the `main` ref. Do not relax them to names or to the organization alone: GitHub issues OIDC tokens to every repository.

## Rollout health checks

- The `at23` syncroot overlay gives `dialogporten-apps` `healthChecks` on its `Deployment`s and `timeout: 15m`, so Flux sends the `Health check passed` event that RFC 0019 uses. Keep it out of `flux/syncroot/base/` until the pilot extends to other environments.
- When a `Deployment` is added to, renamed in or removed from `manifests/environments/at23`, update `healthChecks`. An unlisted `Deployment` is not checked, and a listed one that no longer exists fails every reconcile after the full timeout.
- Do not replace `healthChecks` with `wait: true`. Flux would then also wait for every custom resource with a `Ready` condition, such as an `ExternalSecret` or `ScaledObject`, and report a failed rollout when one of them stays not ready. See `docs/summary.md#rollout-health-in-at23`.
- Keep the timeout above the slowest expected rollout: the startup probes allow 5 minutes per pod.

## Flux results

- `flux/syncroot/at23/dialogporten-flux-results.yaml` sends at23 rollout results to `Altinn/dialogporten`: a `githubdispatch` `Provider` and two `Alert`s, one for `dialogporten-apps` and one for errors of the `dialogporten-manifests` `OCIRepository`. See `docs/summary.md#flux-results-in-at23`.
- Keep each `Alert`'s `eventMetadata` and event source in step with the `subscriptions` of `ci-cd-flux-reconciliation-result.yml` in `Altinn/dialogporten`, which rejects any other product, environment, cluster, repository or resource.
- Name event sources exactly. Do not add an error `Alert` for `dialogporten-apps`: `eventSeverity: info` already includes errors.
- Do not define the Secret `flux-dispatch-github-token`. The platform creates it in `product-dialogporten` and renews its token.

## Release mapping
- `.github/actions/resolve-release` maps the `originRevision` of a Flux event (`main/<commit>`) to the Dialogporten release by reading `images[].newTag` from `manifests/environments/<env>/kustomization.yaml` at that commit. `Altinn/dialogporten` pins it in the workflow that receives Flux results. See `docs/summary.md#release-of-a-flux-revision`.
- Map only image tags that name the Dialogporten commit (`<version>-<short commit>`). Do not resolve a `<version>` tag through the `v<version>` Git tag until release tags are immutable: a moved tag would give a result the wrong commit.
- If the overlay path, the Dialogporten image names, the tag format or the app artifact's `--revision` change, update the action and the cases in `test-resolve-release.yml` in the same PR.

## Migration ordering

- `dialogporten-migration` applies only the migration `Job` from `./environments/<env>/migration`, with `wait: true` and `force: true`. `dialogporten-apps` has `dependsOn: dialogporten-migration`, so new app images roll out only after the migration of the same artifact revision has completed. See `docs/summary.md` for the flow.
- Keep the migration `Job` out of `./environments/<env>`; in that path it would roll out alongside the apps instead of before them.
- Do not add `ttlSecondsAfterFinished` to the migration `Job`. Flux recreates a deleted `Job` on its next reconcile, so the migration would run again after every TTL expiry.
- Keep the `web-api-migration-job` `ApplicationIdentity` in `./environments/<env>` (`manifests/jobs/web-api-migration-job/identity/`). Moving an object between the two Flux Kustomizations can prune it: the syncroot and app artifacts reach the cluster independently, and the old owner deletes objects missing from its new build.
- The `Job` needs `dialogporten-secrets` and the `web-api-migration-job` ServiceAccount, which `dialogporten-apps` creates. On a new cluster, patch `dependsOn` out of `dialogporten-apps` in the env's syncroot overlay for the first rollout, then remove the patch.

## Search reindex

- `reindex-search-job` is a template for runs started by hand (`docs/summary.md#search-reindex-in-at23`). Keep it suspended in every environment, and keep its placeholder schedule: unsuspending it would start a reindex on that schedule.
- Keep the `docs/summary.md` command in sync with the CronJob: if the container, its env var names or its arguments change, update the command too.

## Change hygiene (required)
When changing structure, environments, Flux source wiring, workflow publish logic, or registry/source strategy, update all relevant guidance in the same PR:
- `README.md`
- `docs/summary.md`
- `AGENTS.md`
- `.github/workflows/publish-flux-artifacts.yml` (if env list/path/source assumptions change)

## Environment additions/removals
If environment set changes, update all of:
- `flux/syncroot/<env>/kustomization.yaml`: must patch `spec.path` of `dialogporten-apps` to
  `./environments/<env>` and of `dialogporten-migration` to `./environments/<env>/migration`.
  The base pins both paths to `at23`, so an overlay that omits a patch silently
  deploys at23's manifests. CI enforces this in both `pull-request.yml` and the
  `publish-syncroot` job of `publish-flux-artifacts.yml`.
- `manifests/environments/<env>/migration/` (`kustomization.yaml` with the migration-bundle tag, and `env.yaml`)
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
- The edge proxy owns the public `/dialogporten` mount point. It forwards web API paths with
  the prefix (`/dialogporten/api/...`), and the web APIs remove it with
  `UsePathBase("/dialogporten")`, which leaves unprefixed paths unchanged. GraphQL has no
  path base, so the edge strips the prefix from `/dialogporten/graphql`. The HTTPRoutes on
  `dialogporten.<env>.dis-core.altinn.cloud` match the paths as received, without rewrites.
  See `docs/summary.md` for the path table.
- Match with `PathPrefix`. The exception is `web-api-eu`, whose anchored `RegularExpression`
  catches every API version, with or without the `/dialogporten` prefix. Keep the optional
  prefix group: `web-api-so` serves the end-user endpoints too, so a prefixed end-user path
  that misses the regex is answered by `web-api-so` without errors and only shows up as
  missing `web-api-eu` traffic. Traefik evaluates regex with Go's unanchored `MatchString`, so
  keep the `^...$` anchors: a bare `enduser` pattern also matches the service-owner
  `endusercontext` endpoints. Traefik ranks regex routes by pattern length rather than
  specificity, so check precedence when adding a route that overlaps it.
- The Linkerd catch-all route in `manifests/common/base/linkerd-policies.yaml` admits
  prefixed and unprefixed paths alike; the kubelet probes hit the native `/health/...` paths
  on the pod directly.
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
- `kustomize build manifests/environments/<env>/migration` for each of the env names above

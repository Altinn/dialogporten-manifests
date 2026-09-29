# AGENTS.md

## Purpose
This repository stores Dialogporten Flux manifests and wiring after the `main` restructure.

## Current structure (authoritative)
- `manifests/`: app, job, and common bases plus per-environment overlays in `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical reusable app base manifests consumed by each environment overlay.
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays (patch-only).
- `manifests/environments/<env>/migration/`: the database migration `Job` for the env, applied by its own Flux Kustomization. See [Migration ordering](#migration-ordering).
- `flux/syncroot/`: bootstrap wiring that selects `flux-system/<env>`, with two Flux Kustomizations: `dialogporten-migration` and `dialogporten-apps`. The `at23` overlay also has the `Receiver` for on-demand reconcile.
- `flux/edge-syncroot/`: edge proxy routes (`Backend`, `BackendTLSPolicy`, `HTTPRoute`) per environment. The base uses `*.placeholder.invalid` hostnames and every `<env>` overlay must patch all of them; the `publish-edge-syncroot` job fails if any placeholder survives. `tt02` and `prod` include `components/platform-apim`, which routes through the old APIM via the platform-owned `platform/platform-upstream` `Backend`; reference it, do not redefine it. The cross-namespace `backendRef` needs a `ReferenceGrant` in the `platform` namespace.
- `.github/workflows/publish-flux-artifacts.yml`: publishes OCI artifacts for syncroot and app manifests.
- `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`: reusable failure alerts for image-tag updates and artifact publishing.

## Registry model
- Runtime app images: GHCR tags set in `manifests/environments/<env>/kustomization.yaml`. Exception: the feature-metrics collector image is pinned in `manifests/common/base/feature-metrics-collector.yaml`; do not move it to `images:`, which CI overwrites with the app tag.
- Migration bundle: GHCR tag set in `manifests/environments/<env>/migration/kustomization.yaml`. `workflow-update-all-image-tags.yml` must update that file together with the env `kustomization.yaml`.
- Flux manifests artifacts: ACR (`altinncr.azurecr.io`), published as:
  - `dialogporten/dialogporten-sync:main` (app manifests)
  - `dialogporten/syncroot:main` (syncroot)
  - `dialogporten/edge-syncroot:<env>` (edge-syncroot; envs listed in the `publish-edge-syncroot` matrix)
- Flux app `Kustomization` objects apply environment wrappers directly and do not use `postBuild.substituteFrom`.

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

## Database role provisioning job
- `manifests/jobs/db-provisioner-job/base/` holds the suspended `db-provisioner-job`
  `CronJob`, the `db-provisioner` `ApplicationIdentity`, its `Role`/`RoleBinding`, and the
  `db-provisioner-runtime` ConfigMap. Run it on demand with
  `kubectl create job --from=cronjob/db-provisioner-job db-provisioner-<date> -n product-dialogporten`.
- Do not create a `ServiceAccount` for it. The dis-identity-operator creates one with the
  same name as the `ApplicationIdentity` (Altinn/altinn-platform RFC 0004).
- Do not add a secret to this job. It authenticates with its workload identity, which is
  why the pod template carries `azure.workload.identity/use: "true"`.
- Workload lists are environment data: keep them in the overlay's `db-provisioner-runtime`
  patch (`PGHOST`, `PROVISION_WORKLOADS`), never in the base. Identity ids stay out of the
  repo: the job reads them from the `ApplicationIdentity` status.
- Adding an environment means adding the overlay, listing it in that env's
  `jobs/kustomization.yaml`, and adding `ghcr.io/altinn/dialogporten-db-provisioner` to
  that env's `images:` block.
- Before the first run, follow [README prerequisites](README.md#first-run-prerequisites)
  and the linked provisioner bootstrap runbook. Register the AKS identity as an Entra
  administrator, create the workload identities, and apply migrations first.
- pgAudit is mandatory in the target database. Preserve existing preload libraries
  when adding `pgaudit`; restart manually during an agreed maintenance window if the
  setting changes, then install and verify the extension in `dialogporten`. Production
  setup and any restart are manual operations, never part of manifest reconciliation.
- Pin only a verified, published provisioner image containing the required code.
  The initial `at23` tag `1.121.1-1de2b7c` must be replaced by the exact tag from a
  successful publish containing Dialogporten PR #4407 before first execution.
  Do not invent a replacement when publication is pending or inaccessible; report
  the blocker and keep the CronJob suspended. Kustomize does not check image availability.

## Validation baseline
Run before commit when relevant:
- `actionlint` for workflow changes
- `kustomize build manifests/environments/at23`
- `kustomize build manifests/environments/tt02`
- `kustomize build manifests/environments/yt01`
- `kustomize build manifests/environments/prod`
- `kustomize build manifests/environments/<env>/migration` for each of the env names above

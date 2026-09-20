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

## Database role provisioning

`manifests/jobs/db-provisioner-job/base/` defines a suspended `CronJob`
(`db-provisioner-job`) that registers a PostgreSQL login role per AKS workload identity
and grants it a least-privilege profile role. It is run on demand, like
`web-api-migration-job`:

```
kubectl create job --from=cronjob/db-provisioner-job db-provisioner-<date> -n product-dialogporten
```

Complete the [first run prerequisites](../README.md#first-run-prerequisites) before
using this command. The [provisioner bootstrap runbook](https://github.com/Altinn/dialogporten/blob/3a15eb561e313e557cb63144c4e134f6d89d4129/.azure/modules/postgreSql/provisioner/README.md#bootstrap-and-rollout)
describes the corresponding database setup.

The run is additive and idempotent: missing roles and grants are created, existing ones
are left as they are, so re-running after adding a workload is safe.

The base ships the `ApplicationIdentity` `db-provisioner`, a `Role`/`RoleBinding` letting
it read `applicationidentities`, the `db-provisioner-runtime` ConfigMap with placeholder
values, and the `CronJob` itself. Environment overlays patch the ConfigMap:

| Key | Meaning |
| --- | --- |
| `PGHOST` | PostgreSQL server for that environment |
| `PROVISION_WORKLOADS` | JSON array of `{ applicationIdentity, profile }` entries |

Each entry names an `ApplicationIdentity` in the same namespace; the job resolves its
managed identity name and object id from the resource status at runtime, so identity ids
are never checked in.

Notes:
- The pod carries `azure.workload.identity/use: "true"` and mounts no secret — it
  authenticates as its own identity.
- That identity (`product-dialogporten-db-provisioner`) must be a Microsoft Entra
  administrator on the PostgreSQL server. The registration lives in the `dialogporten`
  repo's infrastructure deployment, not here, and is a prerequisite for the job.
- The image `ghcr.io/altinn/dialogporten-db-provisioner` is published by the
  `dialogporten` repo and pinned in `manifests/environments/<env>/kustomization.yaml`
  like the other images. Before the first run, replace the initial `at23` pin
  `1.121.1-1de2b7c` with the exact tag from a successful provisioner image publish
  containing Dialogporten PR #4407. Verify that image can be pulled; Kustomize
  validation cannot establish this.
- pgAudit is mandatory: allowlist `PGAUDIT`, add `pgaudit` to the existing
  `shared_preload_libraries` without dropping other libraries, manually restart
  during an agreed maintenance window if the setting changes, and install the
  extension in **dialogporten**. Verify the active preload value and installed
  extension before provisioning. Production setup and any restart are manual;
  the job only checks these prerequisites and fails if they are missing.
- Keep the CronJob suspended. Create an on-demand Job only after the image,
  administrator registration, workload identities, migrations, and pgAudit are
  ready; verify a fresh-session login and auditing before switching workloads
  to Entra token authentication.
- Wired for `at23` only so far.

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

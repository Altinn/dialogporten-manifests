# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical per-app base manifests (`web-api-eu`, `web-api-so`, `graphql`, `service`), aligned with job base layout (`manifests/jobs/<job>/base/`).
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays that only patch app bases.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `manifests/environments/<env>/migration/`: the database migration `Job` for that env and the migration-bundle image tag. It is applied on its own, before the apps; see [Database migrations](docs/summary.md#database-migrations).
- `flux/syncroot/`: bootstrap wiring (namespace, `OCIRepository`, and two Kustomizations: `dialogporten-migration` targets `./environments/<env>/migration`, and `dialogporten-apps` targets `./environments/<env>` after it). The `at23` overlay also has the `Receiver` for on-demand reconcile.
- `flux/edge-syncroot/`: edge proxy routing for the public `/dialogporten` mount point (Envoy Gateway `Backend`, `BackendTLSPolicy`, and `HTTPRoute`). The base uses placeholder hostnames; each `<env>` overlay sets the public hostname and the `dialogporten.<env>.dis-core.*` backend hostname. `tt02` and `prod` still route through the old APIM via the `components/platform-apim` component, which points the `HTTPRoute` at the platform-owned `platform/platform-upstream` `Backend` instead of `dp-dis-upstream`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`): syncroot from `flux/syncroot`, edge-syncroot from `flux/edge-syncroot` (`dialogporten/edge-syncroot:<env>`), and app manifests from `manifests/`.
2. `flux/syncroot/` defines an `OCIRepository` pointing to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls that OCI artifact. The environment-specific Kustomizations in `flux/syncroot/<env>` run the migration `Job` from `./environments/<env>/migration` to completion, then apply the `./environments/<env>` path within the artifact.
4. After an image-tag update, CI asks the environment's cluster to pull the new artifact right away instead of at the next 10-minute poll. See [On-demand reconcile](docs/summary.md#on-demand-reconcile).

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`. Two images are the exception: the migration bundle is pinned in `manifests/environments/<env>/migration/kustomization.yaml`, and the feature-metrics collector in `manifests/common/base/feature-metrics-collector.yaml`.

## Database role provisioning

`manifests/jobs/db-provisioner-job/` registers a PostgreSQL login role for each AKS
workload identity and grants it a least-privilege profile role. It follows the same
pattern as `web-api-migration-job`: a suspended `CronJob` that is run on demand by
creating a `Job` from its template.

```
kubectl create job --from=cronjob/db-provisioner-job db-provisioner-<date> -n product-dialogporten
```

The run is additive and idempotent — it creates roles and grants that are missing and
leaves everything else alone, so it is safe to re-run after adding a workload.

Which workloads are provisioned is environment data, held in the
`db-provisioner-runtime` ConfigMap:

- `PGHOST`: the PostgreSQL server for that environment.
- `PROVISION_WORKLOADS`: a JSON array of `{ "applicationIdentity": ..., "profile": ... }`
  entries. The job looks each `ApplicationIdentity` up in the cluster and reads its
  managed identity name and object id from the resource status, so no identity ids are
  stored in this repo. The job's `Role`/`RoleBinding` grant exactly that read access.

The job authenticates with its own workload identity and mounts no secret. Its identity
(`product-dialogporten-db-provisioner`) must be registered as a Microsoft Entra
administrator on the PostgreSQL server before the job can run; that registration is part
of the infrastructure deployment in the `dialogporten` repo.

Currently wired for `at23` only.

## Failure notifications

`Update all image tags` and `Publish Flux artifacts` send one Slack alert per failed workflow run through `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`. Alerts include the repository, workflow, job results, a link to the run, and the requested environment/image tag or published ref/commit. Image-update alerts also cover input validation, checkout, tool installation, push, and publish-dispatch failures. Publishing alerts cover any artifact job, including validation failures. Successful, skipped, and cancelled runs do not send alerts.

Make these GitHub Actions secrets available to this repository, using the same names as Dialogporten's CI/CD notifications:

- `SLACK_BOT_TOKEN`: Slack bot token with permission to post to the CI/CD status channel.
- `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`: ID of that channel; the bot must have access to it.

Slack delivery errors fail the notification job so an undelivered alert is visible in Actions.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.

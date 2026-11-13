# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical per-app base manifests (`web-api-eu`, `web-api-so`, `graphql`, `service`), aligned with job base layout (`manifests/jobs/<job>/base/`).
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays that only patch app bases.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `manifests/environments/<env>/migration/`: the database migration `Job` for that env and the migration-bundle image tag. It is applied on its own, before the apps; see [Database migrations](docs/summary.md#database-migrations).
- `flux/syncroot/`: bootstrap wiring (namespace, `OCIRepository`, and two Kustomizations: `dialogporten-migration` targets `./environments/<env>/migration`, and `dialogporten-apps` targets `./environments/<env>` after it). The `at23` overlay also has the `Receiver` for on-demand reconcile, and makes `dialogporten-apps` wait for its rollout.
- `flux/edge-syncroot/`: edge proxy routing for the public `/dialogporten` mount point (Envoy Gateway `Backend`, `BackendTLSPolicy`, and `HTTPRoute`). The base uses placeholder hostnames; each `<env>` overlay sets the public hostname and the `dialogporten.<env>.dis-core.*` backend hostname. `tt02` and `prod` still route through the old APIM via the `components/platform-apim` component, which points the `HTTPRoute` at the platform-owned `platform/platform-upstream` `Backend` instead of `dp-dis-upstream`.

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`): syncroot from `flux/syncroot` (only when it changes; see [Syncroot publishing](docs/summary.md#syncroot-publishing)), edge-syncroot from `flux/edge-syncroot` (`dialogporten/edge-syncroot:<env>`), and app manifests from `manifests/`.
2. `flux/syncroot/` defines an `OCIRepository` pointing to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls that OCI artifact. The environment-specific Kustomizations in `flux/syncroot/<env>` run the migration `Job` from `./environments/<env>/migration` to completion, then apply the `./environments/<env>` path within the artifact.
4. After an image-tag update, CI asks the environment's cluster to pull the new artifact right away instead of at the next 10-minute poll. See [On-demand reconcile](docs/summary.md#on-demand-reconcile).
5. Flux sends the at23 rollout result to `Altinn/dialogporten`, which maps it to the Dialogporten release with `.github/actions/resolve-release`. See [Release of a Flux revision](docs/summary.md#release-of-a-flux-revision).

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`. Two images are the exception: the migration bundle is pinned in `manifests/environments/<env>/migration/kustomization.yaml`, and the feature-metrics collector in `manifests/common/base/feature-metrics-collector.yaml`.

## Database role provisioning

`manifests/jobs/db-provisioner-job/` registers a PostgreSQL login role for each AKS
workload identity and grants it a least-privilege profile role. Like
`reindex-search-job`, it is a suspended `CronJob` that only serves as a template: a run
is a `Job` created from it by hand, after completing the prerequisites below.

The run is additive and idempotent: it creates roles and grants that are missing and
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
of the infrastructure deployment in the `dialogporten` repo. Configure it through
`additionalEntraAdministrators` using the operator-created identity's principal ID and
managed identity name. Enabling the ACA provisioner does not register this AKS identity.

Currently wired for `at23` only.

### First run prerequisites

Follow the [provisioner bootstrap runbook](https://github.com/Altinn/dialogporten/blob/main/.azure/modules/postgreSql/provisioner/README.md#bootstrap-and-rollout)
in the `dialogporten` repo before creating a Job.

1. Make sure the pinned image exists. The `dialogporten` repo publishes
   `ghcr.io/altinn/dialogporten-db-provisioner` with the app images from
   [PR #4407](https://github.com/Altinn/dialogporten/pull/4407) on, and
   `workflow-update-all-image-tags.yml` sets its `newTag` in
   `manifests/environments/at23/kustomization.yaml` together with theirs. Tags
   published before that PR was merged have no provisioner image. The cluster pulls
   GHCR images without credentials, so the package must also be public. A successful
   Kustomize build does not verify image availability.
2. Complete the Entra administrator registration above, create the workload
   `ApplicationIdentity` resources, and apply the database migrations. Provisioning
   needs both the resolved identities and the application tables to exist.
3. Prepare pgAudit in the target database. Allow `PGAUDIT` in `azure.extensions`,
   add `pgaudit` to the current `shared_preload_libraries` value while preserving
   all other libraries, and manually restart the server during an agreed maintenance
   window if that value changes. Check the active value after restarting. Connect
   as an administrator to **dialogporten**, run `CREATE EXTENSION IF NOT EXISTS pgaudit;`,
   and verify it is installed there. Use the linked runbook for the infrastructure
   parameters and verification query. Production database setup and any restart
   must be performed manually.

The provisioning job does not install pgAudit or restart PostgreSQL. Its preflight
fails before changing roles or privileges if pgAudit is not ready. Keep the CronJob
suspended and leave workloads in their current authentication mode until provisioning
and a fresh-session login/audit check have succeeded.

Once these prerequisites are complete, create the Job manually:

```sh
kubectl --context dis-core-at23-aks -n product-dialogporten create job \
  --from=cronjob/db-provisioner-job "db-provisioner-$(date -u +%Y%m%d%H%M)"
```

## Failure notifications

`Update all image tags` and `Publish Flux artifacts` send one Slack alert per failed workflow run through `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`. Alerts include the repository, workflow, job results, a link to the run, and the requested environment/image tag or published ref/commit. Image-update alerts also cover input validation, checkout, tool installation, push, and publish-dispatch failures. Publishing alerts cover any artifact job, including validation failures. Successful, skipped, and cancelled runs do not send alerts.

Make these GitHub Actions secrets available to this repository, using the same names as Dialogporten's CI/CD notifications:

- `SLACK_BOT_TOKEN`: Slack bot token with permission to post to the CI/CD status channel.
- `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`: ID of that channel; the bot must have access to it.

Slack delivery errors fail the notification job so an undelivered alert is visible in Actions.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.

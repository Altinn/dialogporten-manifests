# Dialogporten Flux manifests

This repository contains the Flux wiring and workload manifests for Dialogporten on DIS. Workloads are now packaged per environment as OCI artifacts and pulled by Flux.

## Layout
- `manifests/`: shared bases (`apps/`, `jobs/`, `common/`) plus per-environment overlays collected under `manifests/environments/<env>/`.
- `manifests/apps/<app>/base/`: canonical per-app base manifests (`web-api-eu`, `web-api-so`, `graphql`, `service`), aligned with job base layout (`manifests/jobs/<job>/base/`).
- `manifests/environments/<env>/apps/<app>/`: per-env app overlays that only patch app bases.
- `manifests/environments/<env>/kustomization.yaml`: concise env entrypoint that pulls all app/job overlays for that env and sets image tags.
- `flux/syncroot/`: bootstrap wiring (namespace, `OCIRepository`, and a Kustomization that targets the chosen `flux-system/<env>` path).

Current environments: `at23`, `tt02`, `yt01`, `prod`.

## OCI flow (high level)
1. CI publishes Flux OCI artifacts to ACR (`altinncr.azurecr.io`): syncroot from `flux/syncroot` and app manifests from `manifests/`.
2. `flux/syncroot/` defines an `OCIRepository` pointing to `oci://altinncr.azurecr.io/dialogporten/dialogporten-sync` with `tag: main`.
3. Flux pulls that OCI artifact, and the environment-specific `Kustomization` in `flux/syncroot/<env>` targets the `./environments/<env>` path within the artifact.

Application runtime images remain GHCR-hosted and are pinned by tags in `manifests/environments/<env>/kustomization.yaml`.

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

`Update all image tags` and `Publish Flux artifacts` send one Slack alert per failed workflow run through `.github/workflows/workflow-send-ci-cd-status-slack-message.yml`. Alerts include the repository, workflow, job results, a link to the run, and the requested environment/image tag or published ref/commit. Image-update alerts also cover input validation, checkout, tool installation, push, and publish-dispatch failures. Publishing alerts cover either artifact job, including validation failures. Successful, skipped, and cancelled runs do not send alerts.

Make these GitHub Actions secrets available to this repository, using the same names as Dialogporten's CI/CD notifications:

- `SLACK_BOT_TOKEN`: Slack bot token with permission to post to the CI/CD status channel.
- `SLACK_CHANNEL_ID_FOR_CI_CD_STATUS`: ID of that channel; the bot must have access to it.

Slack delivery errors fail the notification job so an undelivered alert is visible in Actions.

See `docs/summary.md` for more detail.
Agent/maintenance rules live in `AGENTS.md`.

#!/usr/bin/env bash
# Writes the Dialogporten release that a Flux revision deploys to an environment to
# $GITHUB_OUTPUT. When the mapping is missing or ambiguous it leaves app_version and
# app_commit empty, with a warning, and still succeeds.
set -euo pipefail

# Messages name only checked values: the revision comes from the event.
unavailable() {
  echo "::warning::No release metadata: $1"
  exit 0
}

# publish-flux-artifacts.yml publishes the app artifact from main with --revision=main/<commit>.
[[ "${ORIGIN_REVISION}" =~ ^main/([0-9a-f]{40})$ ]] || unavailable "originRevision is not main/<commit>"
manifests_commit=${BASH_REMATCH[1]}
[[ "${ENVIRONMENT}" =~ ^[a-z0-9]+$ ]] || unavailable "invalid environment"
echo "manifests_commit=${manifests_commit}" >> "${GITHUB_OUTPUT}"

# The overlay at that commit holds the image tags. A commit cannot change, so the
# mapping never depends on a mutable tag.
manifests=$(mktemp -d)
git -C "${manifests}" init -q
git -C "${manifests}" fetch -q --depth=1 https://github.com/Altinn/dialogporten-manifests.git "${manifests_commit}" ||
  unavailable "manifests commit ${manifests_commit} not found"
overlay=$(git -C "${manifests}" show "FETCH_HEAD:manifests/environments/${ENVIRONMENT}/kustomization.yaml") ||
  unavailable "no ${ENVIRONMENT} overlay at ${manifests_commit}"
tags=$(yq '.images[] | select(.name | test("^ghcr[.]io/altinn/dialogporten-")) | .newTag' <<< "${overlay}" | sort -u) ||
  unavailable "cannot read the image tags"
[ "$(grep -c . <<< "${tags}")" -eq 1 ] || unavailable "the overlay has no single Dialogporten image tag"
tag=${tags}

# Map only tags that name the commit: at23 deploys every commit on main as
# <version>-<short commit>. The other environments deploy <version>, which only names a
# release tag, and a tag can be moved. They stay unmapped until release tags are
# immutable (Altinn/altinn-platform#4387).
[[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-([0-9a-f]{7,40})$ ]] || unavailable "the image tag does not name a commit"
short_commit=${BASH_REMATCH[1]}

# Look the commit up only on main, which the Flux dispatch token cannot push to. A ref
# lookup through the API would also match a branch or tag named like the commit.
app=$(mktemp -d)
git -C "${app}" init -q
git -C "${app}" fetch -q --filter=tree:0 --no-tags https://github.com/Altinn/dialogporten.git \
  "+refs/heads/main:refs/remotes/origin/main" || unavailable "cannot fetch Dialogporten main"
app_commit=$(git -C "${app}" rev-list origin/main | grep "^${short_commit}" || true)
[ "$(grep -c . <<< "${app_commit}")" -eq 1 ] || unavailable "no single commit on main for ${tag}"

echo "Release ${tag}, commit ${app_commit}"
echo "app_version=${tag}" >> "${GITHUB_OUTPUT}"
echo "app_commit=${app_commit}" >> "${GITHUB_OUTPUT}"

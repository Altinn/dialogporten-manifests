#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/publish-flux-artifacts-manual.sh [options]

Manually publishes Flux OCI artifacts to ACR, aligned with CI defaults.

Options:
  --app-only         Push only dialogporten/dialogporten-sync
  --syncroot-only    Push only dialogporten/syncroot
  --skip-validate    Skip local structure + kustomize validation
  --acr-login        Run az acr login before pushing
  --registry <host>  OCI registry host (default: altinncr.azurecr.io)
  --tag <tag>        OCI tag (default: main)
  --provider <name>  Flux provider (default: azure)
  --source <url>     Override OCI source annotation (default: git remote.origin.url)
  --revision <rev>   Override OCI revision annotation (default: <branch>@sha1:<commit>)
  --dry-run          Print commands without executing
  -h, --help         Show this help text

Environment overrides:
  APP_REPO           (default: dialogporten/dialogporten-sync)
  SYNCROOT_REPO      (default: dialogporten/syncroot)
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' not found in PATH." >&2
    exit 1
  fi
}

build_kustomize() {
  local path="$1"
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$path" >/dev/null
    return
  fi
  if command -v kubectl >/dev/null 2>&1; then
    kubectl kustomize "$path" >/dev/null
    return
  fi
  echo "Error: Neither 'kustomize' nor 'kubectl' found in PATH." >&2
  exit 1
}

validate_layout() {
  local env app

  for env in at23 tt02 yt01 prod; do
    if [[ ! -f "./flux/syncroot/${env}/kustomization.yaml" ]]; then
      echo "Error: Missing ./flux/syncroot/${env}/kustomization.yaml" >&2
      exit 1
    fi
    if [[ ! -f "./environments/${env}/kustomization.yaml" ]]; then
      echo "Error: Missing ./environments/${env}/kustomization.yaml" >&2
      exit 1
    fi
    if [[ ! -f "./manifests/environments/${env}/kustomization.yaml" ]]; then
      echo "Error: Missing ./manifests/environments/${env}/kustomization.yaml" >&2
      exit 1
    fi
    if [[ ! -f "./flux-system/${env}/kustomization.yaml" ]]; then
      echo "Error: Missing ./flux-system/${env}/kustomization.yaml" >&2
      exit 1
    fi
  done

  for app in web-api-eu web-api-so graphql service; do
    if [[ ! -f "./manifests/apps/${app}/base/kustomization.yaml" ]]; then
      echo "Error: Missing ./manifests/apps/${app}/base/kustomization.yaml" >&2
      exit 1
    fi
  done

  if [[ -d "./manifests/apps/components" || -d "./manifests/apps/base" ]]; then
    echo "Error: Legacy app manifest paths detected (manifests/apps/components or manifests/apps/base)." >&2
    exit 1
  fi

  if grep -R --include='kustomization.yaml' -n 'patchesStrategicMerge' ./manifests/environments >/dev/null; then
    echo "Error: Found deprecated patchesStrategicMerge usage." >&2
    exit 1
  fi

  for env in at23 tt02 yt01 prod; do
    build_kustomize "./environments/${env}"
    build_kustomize "./flux/syncroot/${env}"
    build_kustomize "./flux-system/${env}"
  done
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PUSH_APP=true
PUSH_SYNCROOT=true
SKIP_VALIDATE=false
ACR_LOGIN=false
DRY_RUN=false

REGISTRY="altinncr.azurecr.io"
TAG="main"
PROVIDER="azure"
APP_REPO="${APP_REPO:-dialogporten/dialogporten-sync}"
SYNCROOT_REPO="${SYNCROOT_REPO:-dialogporten/syncroot}"
SOURCE=""
REVISION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-only)
      PUSH_APP=true
      PUSH_SYNCROOT=false
      ;;
    --syncroot-only)
      PUSH_APP=false
      PUSH_SYNCROOT=true
      ;;
    --skip-validate)
      SKIP_VALIDATE=true
      ;;
    --acr-login)
      ACR_LOGIN=true
      ;;
    --registry)
      shift
      REGISTRY="${1:-}"
      ;;
    --tag)
      shift
      TAG="${1:-}"
      ;;
    --provider)
      shift
      PROVIDER="${1:-}"
      ;;
    --source)
      shift
      SOURCE="${1:-}"
      ;;
    --revision)
      shift
      REVISION="${1:-}"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

require_cmd flux
require_cmd git

if [[ -z "${SOURCE}" ]]; then
  SOURCE="$(git config --get remote.origin.url || true)"
fi
if [[ -z "${SOURCE}" ]]; then
  echo "Error: Could not determine git remote.origin.url; pass --source explicitly." >&2
  exit 1
fi

if [[ -z "${REVISION}" ]]; then
  REVISION="$(git rev-parse --abbrev-ref HEAD)@sha1:$(git rev-parse HEAD)"
fi

if [[ "${ACR_LOGIN}" == "true" ]]; then
  require_cmd az
  ACR_NAME="${REGISTRY%%.*}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY RUN: az acr login --name ${ACR_NAME}"
  else
    az acr login --name "${ACR_NAME}"
  fi
fi

if [[ "${SKIP_VALIDATE}" == "false" ]]; then
  echo "Running validation checks..."
  validate_layout
fi

push_artifact() {
  local repository="$1"
  local path="$2"
  local target="oci://${REGISTRY}/${repository}:${TAG}"
  local cmd=(
    flux push artifact "${target}"
    --path="${path}"
    --source="${SOURCE}"
    --revision="${REVISION}"
    --provider="${PROVIDER}"
  )

  echo "Publishing ${target} from ${path}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf 'DRY RUN:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
  else
    "${cmd[@]}"
  fi
}

if [[ "${PUSH_APP}" == "false" && "${PUSH_SYNCROOT}" == "false" ]]; then
  echo "Error: Nothing to push. Use default mode, --app-only, or --syncroot-only." >&2
  exit 1
fi

if [[ "${PUSH_APP}" == "true" ]]; then
  push_artifact "${APP_REPO}" "."
fi

if [[ "${PUSH_SYNCROOT}" == "true" ]]; then
  push_artifact "${SYNCROOT_REPO}" "./flux/syncroot"
fi

echo "Done."

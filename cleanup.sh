#!/usr/bin/env bash
set -euo pipefail

OWNER=${OWNER:-enix223}
OWNER_TYPE=${OWNER_TYPE:-users} # users or orgs
PACKAGE=${PACKAGE:-alibaba-cloud-csi-driver}
TAG=${TAG:-}

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is not installed." >&2
  exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "GitHub auth is not configured. Run: gh auth login" >&2
  exit 1
fi

# Tag resolution order: first arg, then TAG env, then interactive prompt.
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  TAG="$1"
fi

if [ -z "$TAG" ]; then
  if [ -t 0 ]; then
    read -r -p "Enter GHCR tag to delete: " TAG
  else
    echo "TAG is required in non-interactive mode. Use TAG=<tag> bash cleanup.sh or bash cleanup.sh <tag>." >&2
    exit 1
  fi
fi

if [ -z "$TAG" ]; then
  echo "TAG cannot be empty." >&2
  exit 1
fi

base_path="/${OWNER_TYPE}/${OWNER}/packages/container/${PACKAGE}/versions"

set +e
list_output="$(gh api -H "Accept: application/vnd.github+json" "${base_path}?per_page=100" 2>&1)"
list_status=$?
set -e

if [ "$list_status" -ne 0 ]; then
  if echo "$list_output" | grep -q 'read:packages'; then
    echo "Token is missing read:packages scope." >&2
    echo "Create a classic PAT with read:packages and delete:packages, then run:" >&2
    echo "  export GH_TOKEN=YOUR_PAT" >&2
    exit 1
  fi
  echo "Failed to list package versions:" >&2
  echo "$list_output" >&2
  exit 1
fi

version_id="$(printf '%s' "$list_output" | jq -r --arg tag "$TAG" '.[] | select(.metadata.container.tags[]? == $tag) | .id' | head -n1 | tr -d '\r')"

if [ -z "${version_id}" ]; then
  echo "Tag not found: ${TAG}"
  exit 0
fi

if ! [[ "${version_id}" =~ ^[0-9]+$ ]]; then
  echo "Resolved version id is invalid: ${version_id}" >&2
  echo "Check token scopes (read:packages, delete:packages) and OWNER_TYPE (${OWNER_TYPE})." >&2
  exit 1
fi

gh api -X DELETE -H "Accept: application/vnd.github+json" "${base_path}/${version_id}"
echo "Deleted tag ${TAG} (version id ${version_id})"

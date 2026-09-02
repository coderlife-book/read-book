#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${1:?usage: check-release-policy.sh <base-sha> [head-sha]}"
HEAD_SHA="${2:-HEAD}"

write_output() {
  local value="$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "release_required=$value" >> "$GITHUB_OUTPUT"
  else
    echo "release_required=$value"
  fi
}

is_maintenance_path() {
  case "$1" in
    .github/*|Tests/*|AGENTS.md|README.md|docs/*|.gitignore|Scripts/check-release-policy.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

extract_version() {
  local ref="$1"
  git show "$ref:Scripts/build-app.sh" \
    | sed -n 's/.*READBOOK_VERSION:-\([^}]*\).*/\1/p' \
    | head -n 1
}

extract_build() {
  local ref="$1"
  git show "$ref:Scripts/build-app.sh" \
    | sed -n 's/.*READBOOK_BUILD:-\([^}]*\).*/\1/p' \
    | head -n 1
}

version_greater_than() {
  local candidate="$1"
  local baseline="$2"
  local candidate_major candidate_minor candidate_patch
  local baseline_major baseline_minor baseline_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
  IFS=. read -r baseline_major baseline_minor baseline_patch <<< "$baseline"

  for part in \
    "$candidate_major" "$candidate_minor" "$candidate_patch" \
    "$baseline_major" "$baseline_minor" "$baseline_patch"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
  done

  if (( candidate_major != baseline_major )); then
    (( candidate_major > baseline_major ))
  elif (( candidate_minor != baseline_minor )); then
    (( candidate_minor > baseline_minor ))
  else
    (( candidate_patch > baseline_patch ))
  fi
}

release_required=false
while IFS= read -r file; do
  if ! is_maintenance_path "$file"; then
    release_required=true
    break
  fi
done < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA")

write_output "$release_required"

if [[ "$release_required" != "true" ]]; then
  echo "Maintenance-only change detected; version bump is not required."
  exit 0
fi

base_version="$(extract_version "$BASE_SHA")"
head_version="$(extract_version "$HEAD_SHA")"
base_build="$(extract_build "$BASE_SHA")"
head_build="$(extract_build "$HEAD_SHA")"

if [[ -z "$base_version" || -z "$head_version" ]]; then
  echo "APP_VERSION must be readable from Scripts/build-app.sh on both base and head." >&2
  exit 1
fi
if [[ -z "$base_build" || -z "$head_build" ]]; then
  echo "APP_BUILD must be readable from Scripts/build-app.sh on both base and head." >&2
  exit 1
fi

if ! version_greater_than "$head_version" "$base_version"; then
  echo "APP_VERSION must increase for user-facing changes: $base_version -> $head_version" >&2
  exit 1
fi

if [[ ! "$base_build" =~ ^[0-9]+$ || ! "$head_build" =~ ^[0-9]+$ || "$head_build" -le "$base_build" ]]; then
  echo "APP_BUILD must increase for user-facing changes: $base_build -> $head_build" >&2
  exit 1
fi

echo "Release version policy passed: v$base_version build $base_build -> v$head_version build $head_build"

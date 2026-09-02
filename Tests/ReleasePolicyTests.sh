#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$ROOT/Scripts/check-release-policy.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle\nactual: $haystack"
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir/Scripts" "$dir/Sources/ReadBook" "$dir/Tests"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Release Policy Test"
  git -C "$dir" config user.email "release-policy@example.invalid"
  cat > "$dir/Scripts/build-app.sh" <<'SCRIPT'
APP_VERSION="${READBOOK_VERSION:-0.2.0}"
APP_BUILD="${READBOOK_BUILD:-12}"
SCRIPT
  echo 'initial' > "$dir/Sources/ReadBook/App.swift"
  git -C "$dir" add .
  git -C "$dir" commit -qm initial
}

run_policy() {
  local dir="$1"
  local base="$2"
  local head="$3"
  local output_file="$dir/github-output"
  : > "$output_file"
  (
    cd "$dir"
    GITHUB_OUTPUT="$output_file" bash "$POLICY" "$base" "$head"
  )
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Maintenance-only changes must not require a release.
repo="$TMP/maintenance"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
echo '# test only' > "$repo/Tests/OnlyTest.swift"
git -C "$repo" add . && git -C "$repo" commit -qm maintenance
head="$(git -C "$repo" rev-parse HEAD)"
run_policy "$repo" "$base" "$head"
grep -qx 'release_required=false' "$repo/github-output" || fail "maintenance-only change should not require release"

# Product changes without a version bump must fail.
repo="$TMP/no-version-bump"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
echo '// changed' >> "$repo/Sources/ReadBook/App.swift"
git -C "$repo" add . && git -C "$repo" commit -qm product
head="$(git -C "$repo" rev-parse HEAD)"
set +e
output="$(run_policy "$repo" "$base" "$head" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "product change without version bump should fail"
assert_contains "$output" "APP_VERSION must increase"

# Unknown non-maintenance paths default to release-impacting, so new resource roots cannot bypass the guard.
repo="$TMP/unknown-product-path"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$repo/Resources"
echo 'resource' > "$repo/Resources/AppResource.txt"
git -C "$repo" add . && git -C "$repo" commit -qm resource
head="$(git -C "$repo" rev-parse HEAD)"
set +e
output="$(run_policy "$repo" "$base" "$head" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "unknown non-maintenance path should require a release"
assert_contains "$output" "APP_VERSION must increase"

# Version bump without build bump must fail.
repo="$TMP/no-build-bump"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
echo '// changed' >> "$repo/Sources/ReadBook/App.swift"
sed -i.bak 's/0.2.0/0.2.1/' "$repo/Scripts/build-app.sh"
rm -f "$repo/Scripts/build-app.sh.bak"
git -C "$repo" add . && git -C "$repo" commit -qm version-only
head="$(git -C "$repo" rev-parse HEAD)"
set +e
output="$(run_policy "$repo" "$base" "$head" 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]] || fail "product change without build bump should fail"
assert_contains "$output" "APP_BUILD must increase"

# Product changes with both version and build bumps must pass and mark release required.
repo="$TMP/valid-release"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
echo '// changed' >> "$repo/Sources/ReadBook/App.swift"
sed -i.bak 's/0.2.0/0.2.1/; s/:-12/:-13/' "$repo/Scripts/build-app.sh"
rm -f "$repo/Scripts/build-app.sh.bak"
git -C "$repo" add . && git -C "$repo" commit -qm release
head="$(git -C "$repo" rev-parse HEAD)"
run_policy "$repo" "$base" "$head"
grep -qx 'release_required=true' "$repo/github-output" || fail "valid product change should require release"

bash "$ROOT/Tests/CIWorkflowCachePolicyTests.sh"

echo "Release policy tests passed."

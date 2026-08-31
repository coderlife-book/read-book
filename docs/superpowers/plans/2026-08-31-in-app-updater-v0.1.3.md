# ReadBook In-App Updater v0.1.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native GitHub-Releases updater so v0.1.3+ can check, download, validate, replace, and relaunch ReadBook without manual browser downloads.

**Architecture:** Keep update state independent from reading/window state. `GitHubReleaseClient` retrieves metadata, `AppVersion` compares versions, `UpdateController` orchestrates user-facing state, and `UpdateInstaller` validates/extracts/replaces only after progress is flushed. GitHub release assets provide the ZIP and SHA-256 sidecar; no private updater key or new backend is required for this personal-use release.

**Tech Stack:** Swift 6, Foundation URLSession, CryptoKit, AppKit, Process, XCTest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-31-in-app-updater-design.md`

## Global Constraints

- macOS 26+.
- GitHub repo is fixed to `coderlife-book/read-book`.
- Only HTTPS GitHub API/download URLs are accepted.
- Asset names are exactly `ReadBook-macOS.zip` and `ReadBook-macOS.zip.sha256`.
- Bundle identifier must remain `com.coderlife.readbook`.
- No silent installation, sudo, privilege escalation, quarantine removal, or Gatekeeper disabling.
- Existing app/library data must not be modified by update download/install logic.

---

### Task 1: Version and release metadata

**Files:**
- Create `Sources/ReadBookCore/Update/AppVersion.swift`
- Create `Sources/ReadBookCore/Update/GitHubRelease.swift`
- Create `Tests/ReadBookCoreTests/UpdateMetadataTests.swift`

**Interfaces:** `AppVersion.init?(_:)`, `Comparable`; `GitHubRelease.latestVersion`; `archiveAsset`; `checksumAsset`.

- [ ] Write RED tests for `0.1.10 > 0.1.9`, leading `v`, malformed versions, GitHub JSON decoding, and exact asset selection.
- [ ] Run `swift test --filter UpdateMetadataTests` and confirm failure.
- [ ] Implement numeric dot-component comparison and Codable release/asset DTOs.
- [ ] Run focused tests to GREEN and commit `feat: add update release metadata`.

### Task 2: Release client and checksum validation

**Files:**
- Create `Sources/ReadBook/Update/GitHubReleaseClient.swift`
- Create `Sources/ReadBook/Update/UpdateChecksum.swift`
- Create `Tests/ReadBookAppTests/UpdateClientTests.swift`

**Interfaces:** `func latestRelease() async throws -> GitHubRelease`; `UpdateChecksum.sha256(of:)`; `matches(file:expected:)`.

- [ ] Add RED tests using injected URLSession protocol/stub data and a temporary file with known SHA-256.
- [ ] Implement a request to `https://api.github.com/repos/coderlife-book/read-book/releases/latest` with `Accept: application/vnd.github+json` and a ReadBook User-Agent.
- [ ] Reject non-HTTPS or non-GitHub asset URLs before download.
- [ ] Implement CryptoKit streaming/file SHA-256 and normalized 64-hex checksum parsing.
- [ ] GREEN + commit `feat: add GitHub update client`.

### Task 3: Candidate extraction and installer helper

**Files:**
- Create `Sources/ReadBook/Update/UpdateInstaller.swift`
- Create `Tests/ReadBookAppTests/UpdateInstallerTests.swift`

**Interfaces:** `validateCandidate(appURL:expectedVersion:) throws`; `prepareReplacement(candidateAppURL:currentAppURL:currentPID:) throws -> URL`; `launchReplacementHelper(...) throws`.

- [ ] RED tests for wrong bundle id, wrong version, missing executable, non-writable destination, and helper script containing wait/backup/rollback/relaunch steps.
- [ ] Extract ZIP via `/usr/bin/ditto -x -k` into a unique temporary directory.
- [ ] Validate plist bundle id/version and run `/usr/bin/codesign --verify --deep --strict` against candidate.
- [ ] Generate helper script that waits for current PID, moves current app to `.ReadBook.backup`, copies candidate with `ditto`, rolls back on failure, removes backup on success, and `/usr/bin/open`s the replacement.
- [ ] GREEN + commit `feat: add atomic app replacement`.

### Task 4: UpdateController and UI integration

**Files:**
- Create `Sources/ReadBook/Update/UpdateController.swift`
- Modify `Sources/ReadBook/App/AppRuntime.swift` (or create it if stealth plan has not yet reached that task)
- Modify `Sources/ReadBook/App/ReadBookApp.swift`
- Modify `Sources/ReadBook/Settings/SettingsView.swift`
- Modify `Sources/ReadBook/App/AppDelegate.swift`
- Create `Tests/ReadBookAppTests/UpdateControllerTests.swift`

**Interfaces:** observable `UpdateState` = idle/checking/upToDate/available/downloading/ready/error; `check(manual:)`; `downloadAndInstall()`.

- [ ] RED tests: background current-version check stays quiet; manual current-version check reports up-to-date; newer release becomes available; failed download leaves running app untouched; install calls flush before launching helper.
- [ ] Implement controller with injected client/installer/current-version/flush/terminate closures.
- [ ] Start one delayed automatic check after launch when enabled; never poll.
- [ ] Add `检查更新…` to MenuBarExtra and Settings plus an update sheet/alert with release notes and `稍后` / `下载并安装`.
- [ ] GREEN + commit `feat: add in-app update UI`.

### Task 5: Immutable version-derived releases

**Files:**
- Modify `Scripts/build-app.sh`
- Modify `.github/workflows/bootstrap-readbook.yml`
- Create `Tests` only through CI shell verification.

- [ ] Bump `CFBundleShortVersionString` to `0.1.3` and `CFBundleVersion` to `4`.
- [ ] On PR: test/build/package/codesign and create a downloadable preview artifact; do not publish a GitHub Release.
- [ ] On main: derive `VERSION` from packaged Info.plist, create ZIP + `shasum -a 256` sidecar, verify checksum, and create `v$VERSION` only if absent. If already present, skip publication rather than clobbering assets.
- [ ] Release notes describe stealth mode, pure-reading chrome, branding, and in-app updater.
- [ ] Verify full CI, preview artifact, strict codesign, and release assets; commit `build: publish immutable self-updating releases`.

### Task 6: End-to-end release gate

- [ ] Run full `swift test`, `swift build`, `Scripts/build-app.sh` in macOS CI.
- [ ] Verify no failing tests and strict bundle signature success.
- [ ] Verify preview ZIP/checksum can be downloaded from PR artifact.
- [ ] Merge only after stealth-reader acceptance code paths and updater tests are green.
- [ ] Main CI publishes v0.1.3; verify release contains ZIP + checksum and direct download is usable.

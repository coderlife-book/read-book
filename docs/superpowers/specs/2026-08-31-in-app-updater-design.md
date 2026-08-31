# ReadBook In-App Updater Design

Date: 2026-08-31
Status: Approved by delegated user decision
Target release: v0.1.3

## Purpose

ReadBook should stop requiring a manual browser download for every release after v0.1.3. The updater must fit the current distribution model: GitHub Releases, an ad-hoc signed app bundle, no Apple Developer ID/notarization, and no separate backend.

## Architecture

Use a small native updater instead of Sparkle for this release. Sparkle would be the preferred public-distribution path once Developer ID/notarization and a protected signing-key workflow exist; adding that key-management dependency now would block the user's primary goal.

The client queries the public GitHub Releases API for `coderlife-book/read-book/releases/latest`, compares semantic versions against `CFBundleShortVersionString`, finds `ReadBook-macOS.zip`, and validates the downloaded archive against a SHA-256 digest published by the release workflow. It then extracts into a temporary directory, validates the candidate bundle identifier/version and strict `codesign`, and launches a tiny replacement helper that waits for ReadBook to exit, atomically replaces the app, reopens it, and rolls back on copy failure.

## Product behavior

- Automatically check once shortly after launch when enabled; default enabled.
- Menu bar and Settings expose `检查更新…`.
- If already current, manual check reports that clearly; background check stays quiet.
- If an update exists, show version + release notes with `稍后` and `下载并安装`.
- Download is explicit; no silent install in v0.1.3.
- Show download/install errors without changing the current app.
- Before install, flush reading progress.
- After validation, quit ReadBook and let the helper replace/relaunch it.
- v0.1.2 cannot self-update; v0.1.3 is the one final manual download. v0.1.3+ can self-update.

## Release contract

Each GitHub Release contains:

- `ReadBook-macOS.zip`
- `ReadBook-macOS.zip.sha256`

The checksum file contains one lowercase 64-character SHA-256 followed by the archive filename. The client accepts only HTTPS GitHub URLs returned by the GitHub Releases API and requires checksum equality before extraction.

The release workflow derives the tag from the app version instead of hardcoding v0.1.2. A main build publishes a version only when that release tag does not already exist; later pushes at the same version do not mutate the released binary. A version bump creates the next release.

## Safety and failure handling

- Never replace the running app before archive, checksum, bundle identifier, version, and strict code-signature validation pass.
- Require `CFBundleIdentifier == com.coderlife.readbook`.
- Require candidate version to equal the GitHub release version and be newer than the running version.
- Keep a sibling backup during replacement and restore it if copy fails.
- Require the destination parent directory to be writable. If not writable, keep the downloaded candidate and tell the user to install manually rather than attempting privilege escalation.
- No `sudo`, authorization dialogs, global Gatekeeper disabling, or automatic quarantine removal.
- GitHub HTTPS + SHA-256 protects transport/corruption under the current personal-use threat model; it is not a replacement for Developer ID/notarization or a separate publisher signature.

## Components

- `AppVersion`: semantic version parsing/comparison.
- `GitHubReleaseClient`: release metadata retrieval and asset selection.
- `UpdateController`: observable update state, automatic/manual checks, download/validation/install orchestration.
- `UpdateInstaller`: extraction, bundle validation, helper-script creation and replacement.
- Release workflow: archive + checksum + immutable versioned release.

## Testing

Unit tests cover semantic version ordering, GitHub release JSON parsing/asset selection, checksum validation, candidate bundle validation failures, and update-state decisions. CI builds the app, verifies strict ad-hoc signing, creates the release ZIP/checksum, and verifies the checksum before publication.

Manual acceptance on macOS 26 covers: manual current-version check, simulated/new-version update prompt, download failure recovery, writable install path update/relaunch, and preservation of the library/reading position after update.

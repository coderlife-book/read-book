# ReadBook v0.1.3 macOS Acceptance Checklist

Target: macOS 26+, Apple Silicon.

## Pure reading

- [ ] Move the pointer into the body text: toolbar/footer stay hidden.
- [ ] Scroll with mouse wheel and trackpad: toolbar/footer stay hidden.
- [ ] Enter the top 20 pt edge and dwell ~250 ms: top controls appear with an opaque-enough theme scrim and no text overlap.
- [ ] Enter the bottom 16 pt edge and dwell ~250 ms: chapter/progress appear with their own scrim.
- [ ] Return to the body: chrome fades away after ~200 ms.

## Dragging and appearances

- [ ] Drag title text/empty toolbar area: borderless window moves reliably.
- [ ] Toolbar buttons still click rather than drag.
- [ ] Card keeps background/shadow.
- [ ] Frameless removes shadow and defaults to 18% background.
- [ ] Transparent has no window background or shadow.

## Boss Mode

- [ ] Enable Floating Reading: only text remains when chrome is not requested.
- [ ] Floating Reading defaults to pointer pass-through; clicks/scroll target the app behind ReadBook.
- [ ] Hold Option while the pointer is in the stored reader frame: ReadBook becomes interactive and full controls appear.
- [ ] Release Option: after ~300 ms it returns to floating/pass-through unless Lock Interactive is enabled.
- [ ] Enable Concealed: leave the reader frame for ~300 ms and the whole reader hides.
- [ ] Re-enter the previous frame: an automatically hidden reader returns.
- [ ] Press `⌃⌥R`: reader hides immediately.
- [ ] Move pointer through the old frame after shortcut hide: reader stays hidden.
- [ ] Press `⌃⌥R` again: reader returns.
- [ ] Disconnect a display that held the reader and show it again: frame is clamped to an available display.

## Branding

- [ ] Finder shows the custom ReadBook icon.
- [ ] Dock shows the custom ReadBook icon in normal app-presence mode.
- [ ] Menu bar uses the monochrome ReadBook mark and adapts to light/dark menu bar appearance.

## Updates

- [ ] Menu bar `检查更新…` opens a visible update prompt.
- [ ] Settings shows current version and `检查更新…`.
- [ ] On v0.1.3 with latest release v0.1.3, manual check reports current/latest; automatic check stays quiet.
- [ ] A newer test release produces an update prompt with release notes.
- [ ] Archive SHA-256 mismatch refuses installation and leaves the current app untouched.
- [ ] Valid candidate requires bundle id `com.coderlife.readbook`, matching newer version, executable, and strict codesign verification.
- [ ] On a writable install directory, installation flushes reading progress, replaces the app, and relaunches.
- [ ] Library, current book, and reading offset survive the update.
- [ ] On a non-writable install directory, updater reports an error and does not request sudo or modify the existing app.

## Packaging / CI

- [ ] `swift test` all green.
- [ ] `swift build` green.
- [ ] `Scripts/build-app.sh` green.
- [ ] `codesign --verify --deep --strict` green.
- [ ] `.icns` and menu template are packaged.
- [ ] PR workflow publishes ZIP + `.sha256` preview artifact.
- [ ] Main workflow publishes immutable `v0.1.3` ZIP + `.sha256` release assets.

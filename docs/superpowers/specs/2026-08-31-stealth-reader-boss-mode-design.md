# ReadBook Stealth Reader / Boss Mode Design

Date: 2026-08-31
Status: Proposed for implementation after user review
Target: macOS 26+

## 1. Purpose

ReadBook is intended to work as a low-presence personal novel reader while the user is working. The current V1 reader still behaves too much like a normal application window: hovering the reader exposes controls over the text, borderless dragging is unreliable, and there is no fast hide/show workflow for discreet reading.

This design adds a dedicated stealth-reading window subsystem while preserving the existing TXT library, reading modes, canonical UTF-16 reading position, pagination, and virtualized continuous rendering.

The core product principle is:

> The reading surface stays visually quiet by default. Merely moving the pointer into the text or scrolling must never summon interface chrome.

## 2. Scope

### Included

- Fix hover controls overlapping reading text.
- Replace generic window hover with explicit top/bottom control hot zones.
- Make the borderless reader reliably draggable from the title/control region.
- Add a unified reader window state machine instead of accumulating independent booleans.
- Add Boss Mode with two profiles: Floating Reading and Concealed.
- Add global show/hide shortcut.
- Restore an automatically hidden window when the pointer re-enters its previous frame.
- Prevent auto-restore after an explicit shortcut hide until explicitly shown again.
- Add frameless and fully transparent reading appearances.
- Add pointer pass-through with temporary Option-key interaction.
- Add a menu-bar "lock interactive" override.
- Add application branding: a custom ReadBook app icon/logo and a small curated open-source SVG icon set where non-SF-Symbol artwork is useful.

### Excluded

- Screen-capture hiding or anti-screenshot behavior.
- Process-name masquerading.
- Fake IDE/editor content.
- Automatic foreground-app detection.
- Cloud synchronization.
- Changes to TXT import/storage semantics.
- Replacing the existing paginated or virtualized-continuous text engines.
- User-configurable global hotkeys in this release; V1.3 ships one fixed default hotkey.

## 3. Architecture

Use one `ReaderWindowStateController` as the authority for window interaction state. Appearance is modeled separately from behavioral state.

This avoids a state explosion such as `isHovering`, `isTransparent`, `isHidden`, `isBossMode`, `isInteractive`, and `isMouseInside` independently mutating the same `NSWindow`.

### 3.1 Behavioral state

```swift
enum ReaderWindowState {
    case normal
    case floatingText
    case interactiveStealth
    case hidden(HideReason)
}

enum HideReason {
    case automaticPointerExit
    case explicitShortcut
    case explicitMenuAction
}
```

`explicitShortcut` and `explicitMenuAction` are lock-hidden reasons: entering the old window frame must not auto-show the reader.

### 3.2 Appearance

```swift
enum ReaderWindowAppearance {
    case card
    case frameless
    case transparent
}
```

Behavior and appearance are orthogonal. Valid examples:

- `normal + card`: normal widget-style reader.
- `normal + frameless`: normal borderless low-chrome reader.
- `floatingText + transparent`: text floating over the desktop/editor.
- `interactiveStealth + transparent`: transparent reader temporarily receiving input.
- `hidden`: no visible reader regardless of configured appearance.

### 3.3 Boss Mode profile

```swift
enum BossModeProfile {
    case floatingReading
    case concealed
}
```

Boss Mode itself is enabled/disabled separately from the selected profile.

## 4. State transitions

### 4.1 Normal operation

Boss Mode off:

- Reader remains `normal`.
- Pointer entering text does not alter controls.
- Top/bottom hot zones may reveal controls.

### 4.2 Floating Reading profile

Boss Mode on + Floating Reading:

- Default state becomes `floatingText`.
- Background, shadow, toolbar, chapter footer, and other chrome are hidden.
- Text remains visible.
- Pointer is pass-through by default.
- Holding Option while inside the stored reader frame transitions to `interactiveStealth`.
- Releasing Option returns to `floatingText` after 300 ms.
- Pointer exiting does not hide the text in this profile.

### 4.3 Concealed profile

Boss Mode on + Concealed:

- Reader may be `floatingText` or `interactiveStealth` while in use.
- Pointer leaving the reader frame starts a 300 ms hide timer.
- Re-entering before the timer expires cancels the hide.
- Timer expiry transitions to `hidden(.automaticPointerExit)`.
- While hidden for automatic pointer exit, global mouse tracking detects re-entry into the last reader frame and restores the previous stealth state.

### 4.4 Emergency global shortcut

V1.3 fixed shortcut: `Control + Option + R` (`⌃⌥R`).

- Shortcut works even when ReadBook is not frontmost.
- From any visible state: immediately hide as `hidden(.explicitShortcut)`.
- No 300 ms delay and no concealment animation.
- Pointer movement into the old frame does not restore an explicitly hidden window.
- Pressing the shortcut again restores the last visible state.
- Menu-bar "Show Reader" also clears lock-hidden state and restores the reader.
- Shortcut customization is explicitly deferred to a later release.

## 5. Pointer pass-through and temporary interaction

Transparent/Floating Reading is primarily a visual overlay, not a normal foreground window.

Default behavior:

- `window.ignoresMouseEvents = true` in `floatingText`.
- Mouse clicks and scrolling continue to operate the IDE/browser behind ReadBook.

Temporary interaction:

- Global/local modifier monitoring watches Option.
- When Option is held and the pointer is inside the stored reader frame, enter `interactiveStealth` and set `ignoresMouseEvents = false`.
- The reader can then scroll, paginate, open controls, and drag.
- Releasing Option waits 300 ms before returning to pointer pass-through, preventing flicker while the user moves between reader controls.

Persistent override:

- Menu bar exposes `Lock as Interactive`.
- When enabled, Boss Mode does not return to pass-through until unlocked.
- This lock is session-only and resets to off at the next app launch.

## 6. Pure reading hover behavior

The current rule "pointer is inside reader => show toolbar/footer" is removed.

### 6.1 Text area

Pointer movement, wheel scrolling, trackpad scrolling, page navigation, text selection, and ordinary hover in the reading body do **not** reveal toolbar or footer.

### 6.2 Top control hot zone

- Top hot zone height: 20 pt.
- Pointer must remain in the zone for 250 ms before revealing the toolbar.
- Toolbar appears over a theme-matched scrim with enough opacity to fully separate controls from body text.
- The scrim prevents title/buttons from visually stacking on body text.
- Toolbar non-button area is the primary window drag surface.

### 6.3 Bottom status hot zone

- Bottom hot zone height: 16 pt.
- Pointer must remain in the zone for 250 ms before revealing chapter title and reading progress.
- Footer receives its own theme-matched scrim.
- Footer text never renders directly over body text without background separation.

### 6.4 Auto-dismiss

- Leaving a control hot zone and returning to the body starts a 200 ms fade-out timer.
- Entering a popover/menu originating from the control region keeps that region visible while the control is active.
- Scrolling must never reset or trigger the reveal timer.

### 6.5 Option interaction

Holding Option in a stealth profile reveals the full control layer immediately because this is an explicit interaction intent.

## 7. Window dragging

`isMovableByWindowBackground` is not sufficient for a borderless reader containing `NSTextView`/SwiftUI controls because child views consume mouse input.

The toolbar/title drag region will bridge to AppKit and call `NSWindow.performDrag(with:)` from an explicit mouse-down event.

Rules:

- Dragging the title text or empty toolbar space moves the reader.
- Buttons keep normal click behavior and must not start dragging.
- In frameless/transparent modes, Option interaction exposes the same drag surface.
- Window frame persistence continues using the existing autosave/registry mechanism.

## 8. Appearance modes

### 8.1 Card

- Existing rounded reading card.
- Theme background visible at 100% opacity.
- Window shadow visible.
- Suitable for normal reading.

### 8.2 Frameless

- No obvious outer card/chrome.
- No titlebar.
- Window shadow disabled.
- Default theme-surface background opacity: 18%.
- Background opacity is user-adjustable from 0% to 60% in Settings.
- Reader remains fully legible over ordinary desktop backgrounds.

### 8.3 Transparent

- Main background alpha = 0%.
- Window shadow disabled.
- Only text remains when controls are not explicitly revealed.
- Toolbar/footer scrims are permitted while controls are explicitly active so the controls stay readable.
- Pointer pass-through defaults on in Floating Reading.

Text opacity remains independent from background opacity. V1.3 does not expose arbitrary text-opacity control; readable text is more important than another visual setting.

## 9. Preferences and menu-bar controls

Extend `ReaderPreferences` with durable product preferences, while transient state remains in the window controller.

Persistent settings:

- Boss Mode enabled.
- Boss Mode profile: Floating Reading / Concealed.
- Appearance: Card / Frameless / Transparent.
- Frameless background opacity, default 18%, range 0%...60%.
- Global shortcut is not persisted/configurable in V1.3; it is fixed to `⌃⌥R`.

Transient settings/state:

- Lock Interactive, default off and not persisted across launches.
- Current `ReaderWindowState`.
- Last visible stealth state.
- Current hide reason.

Menu-bar entries:

- Show / Hide Reader.
- Boss Mode toggle.
- Profile selector or concise submenu.
- Lock as Interactive.
- Appearance selector.
- Existing recent books/import/settings/quit actions.

Settings should expose the durable versions of the same controls with concise explanations.

## 10. App icon, logo, and SVG icon policy

The application needs an identifiable visual mark rather than shipping with no branded app icon.

### 10.1 App icon/logo

Use a custom ReadBook mark rather than using an off-the-shelf book SVG as the application identity.

Recommended visual direction:

- macOS squircle base.
- Minimal folded reading page / book-page silhouette.
- A subtle negative-space `R` integrated into the fold/spine.
- Strong enough silhouette to survive 16–32 px rendering.
- Avoid detailed literal open-book artwork and avoid generic "blue book" clip-art appearance.
- Produce a vector master first, then generate the required macOS icon sizes/assets from it.

The same mark should have a simplified monochrome form suitable for the menu bar.

### 10.2 UI SVG sources

For any custom vector controls that are not better served by SF Symbols, prefer one consistent open-source set rather than mixing random icons.

Primary candidate: **Tabler Icons**.

- 24×24 grid and consistent 2 px stroke.
- 6,000+ SVG icons.
- MIT licensed and explicitly supports personal/commercial use.
- Suitable candidates include book/library, eye/eye-off, ghost/stealth, pin, layout, and settings metaphors.

Secondary candidate: **Lucide**.

- Lightweight optimized SVGs with a similarly restrained stroke style.
- ISC license.
- Useful fallback if a Tabler metaphor is visually weaker.

Heroicons is acceptable as a reference set but should not be mixed into the shipped control set unless a specific icon is clearly superior.

Licensing files/notices for bundled third-party SVGs must be retained in the repository/distribution as required by their licenses.

### 10.3 Native symbols

Do not replace good SF Symbols merely to say the app uses SVG. macOS-native controls may continue using SF Symbols where they already look correct. External SVGs are for branding and places where a custom metaphor materially improves the UI.

## 11. Component boundaries

Proposed responsibilities:

### `ReaderWindowStateController`

Owns:

- Current behavioral state.
- Last visible stealth state.
- Hide reason.
- Hide/reveal timers.
- Pointer-enter stored-frame logic.
- Option modifier interaction.
- Pointer pass-through.
- Global shortcut intent.

It does not own reading position or text layout.

### `WindowRegistry`

Remains responsible for locating the actual reader `NSWindow` and applying commands from the state controller. It becomes the AppKit execution layer rather than the behavioral decision maker.

### `ReaderChromeController` / SwiftUI view state

Owns top/bottom hot-zone dwell and visible control-region state. This is separate from the window state machine so toolbar timing cannot accidentally hide the entire reader.

### `ReaderDragRegion`

Small AppKit bridge that converts a mouse down in an approved drag area into `window.performDrag(with:)`.

### Global input monitors

A narrowly scoped service owns global shortcut/modifier/mouse-location monitors and tears them down deterministically on termination. It emits semantic events to `ReaderWindowStateController` rather than mutating windows itself.

## 12. Data flow

Typical concealed workflow:

1. User enables Boss Mode / Concealed.
2. State controller configures stealth appearance and remembers the reader frame.
3. Pointer exits frame.
4. Global mouse monitor emits pointer-exit event.
5. State controller starts 300 ms timer.
6. Timer fires and asks `WindowRegistry` to `orderOut` the reader.
7. State becomes `hidden(.automaticPointerExit)`.
8. Global mouse monitor later observes pointer entering the stored frame.
9. State controller restores the previous visible stealth state.
10. Reader position/text state is unchanged because only the window visibility changed.

Emergency shortcut path:

1. Global hotkey emits toggle event.
2. Visible reader becomes `hidden(.explicitShortcut)` immediately.
3. Pointer-in-frame events are ignored while lock-hidden.
4. Second hotkey or explicit menu Show clears lock-hidden and restores the last state.

## 13. Error handling and safety fallbacks

- If global shortcut registration fails, Boss Mode remains usable through the menu bar and Settings reports that `⌃⌥R` is unavailable rather than silently pretending it works.
- If a global event monitor cannot be installed, concealed auto-return falls back to menu-bar/global-shortcut restoration; no polling loop is introduced.
- Window frame detection uses global screen coordinates consistently across multiple displays.
- Stored frame is clamped/revalidated if a display is disconnected.
- Any unexpected state/controller failure prefers leaving a visible, interactive reader rather than trapping the user in an invisible unclickable overlay.
- Explicit Quit always unregisters global monitors/hotkeys.

## 14. Testing

### State-machine unit tests

Cover at minimum:

- Floating profile transitions.
- Concealed pointer-exit -> delayed hidden.
- Re-entry before 300 ms cancels hide.
- Automatic hidden -> pointer re-entry restores.
- Explicit shortcut hidden -> pointer re-entry does not restore.
- Second shortcut restores.
- Option enters/exits interactive stealth.
- Lock-interactive overrides pass-through.

### Window/AppKit tests

- Transparent mode sets background/shadow/mouse-event behavior as specified.
- Frameless mode remains resizable and has no shadow.
- Title/empty toolbar drag invokes approved drag path while buttons remain clickable.
- Window show/hide does not reset frame or reading position.

### Chrome tests

- Body hover does not show controls.
- Scroll events do not show controls.
- 250 ms top dwell reveals only top chrome.
- 250 ms bottom dwell reveals only bottom chrome.
- Controls have scrim/background separation from body content.
- Returning to body dismisses controls after 200 ms.

### Performance/regression

- Existing 33+ tests remain green.
- Existing virtualized continuous renderer remains bounded.
- Global mouse/modifier monitoring must not cause high idle CPU usage.
- No timer/event-monitor retain cycles.

### Manual acceptance on macOS 26

- Work with VS Code/Chrome behind a fully transparent reader.
- Verify click/scroll pass-through.
- Hold Option and immediately interact with reader.
- Move pointer out in Concealed profile; window disappears 300 ms later unless the pointer re-enters first.
- Move pointer back to the old frame; automatically hidden reader returns.
- Hit `⌃⌥R`; reader disappears immediately and stays hidden even with pointer in its old frame.
- Hit shortcut again; reader returns.
- Scroll the novel for several minutes without toolbar/footer appearing accidentally.
- Move pointer intentionally into top/bottom hot zones and verify controls remain readable without body-text overlap.
- Verify Frameless default background is 18% opacity and Transparent is 0%.

## 15. Release strategy

Implement on a feature branch and publish as the next release only after:

1. Full macOS CI is green.
2. App bundle strict codesign verification is green.
3. Manual acceptance covers transparent/pass-through/shortcut/auto-hide on a real macOS 26 desktop.
4. New app icon is visible in the generated `.app` bundle and Finder/Dock presentation.

Do not publish from a design-only commit.

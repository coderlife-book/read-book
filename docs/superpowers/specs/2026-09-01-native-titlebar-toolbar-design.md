# ReadBook v0.1.9 Native Titlebar Toolbar Design

## Problem

The v0.1.9 RC restored native macOS titlebar dragging and native resize behavior, but the visual result exposes two stacked header regions:

1. the native macOS titlebar area, currently empty but still occupying height;
2. the SwiftUI `ReaderToolbar` rendered inside `ReaderRootView` below it.

This breaks the pure-reading appearance even though dragging and scrolling are now reliable.

## Goal

Keep the native AppKit titlebar as the only top chrome region, and move ReadBook's controls into that same native titlebar. The result must look like one single header, not a system header plus an app header.

The controls remain auto-hidden: they appear only when the pointer enters the top/titlebar reveal area, and fade out again using the existing chrome timing behavior.

## Chosen architecture

Use a native `NSToolbar` unified into the existing titlebar. Do not use `NSTitlebarAccessoryViewController`, because an accessory controller can introduce additional titlebar/accessory height and risks recreating the same double-header problem.

### Window

`WindowCoordinator` keeps the reliable native window contract:

- `.titled`
- `.resizable`
- `.closable`
- no custom drag region
- no custom resize overlay
- hidden standard traffic-light buttons
- hidden native window title
- transparent titlebar appearance
- `.fullSizeContentView` remains disabled

Additionally:

- `window.titlebarSeparatorStyle = .none`
- attach one `NSToolbar` configured for the unified titlebar style
- disable the toolbar baseline separator

Reader content remains below the native titlebar hit-testing region, so the scroll/text surface cannot steal titlebar drag events.

### Toolbar composition

The native toolbar contains the same logical controls as the current `ReaderToolbar`:

- library button
- current book title
- reading-mode control
- always-on-top control
- more/settings control

Use native `NSToolbarItem` / `NSToolbarItemGroup` items. SwiftUI `NSHostingView` may be used only for individual custom item content where needed; it must not create another full-width toolbar row.

The title item is flexible and truncates as today. Empty toolbar/titlebar space remains native window drag space. Buttons consume only their own hit regions.

### Toolbar state bridge

Add a narrow `ReaderTitlebarState` observable object owned by `AppRuntime`.

It exposes only titlebar state/actions:

- current book title
- current reading mode
- always-on-top state
- titlebar control visibility
- library action
- reading-mode change action
- pin action
- more/settings action

`ReaderRootView` synchronizes current `AppModel` / `ReaderChromeController` state into `ReaderTitlebarState`. `WindowRegistry` owns the native toolbar and observes that state to update toolbar items.

No reading text, pagination, scrolling, chapter parsing, or persistence logic moves into the titlebar layer.

## Auto-hide behavior

Preserve the existing `ReaderChromeController` timing semantics.

- Pointer entering the native titlebar/top reveal area starts the existing top dwell behavior.
- After the configured dwell, toolbar item content fades or becomes visible in the native titlebar.
- Hovering toolbar controls holds the chrome visible.
- Leaving the titlebar/control area dismisses it using the existing delay.
- `interactiveStealth` still reveals controls immediately.
- `floatingText` / hidden states keep the controls hidden as today.

A small native titlebar tracking view or tracking area forwards titlebar enter/exit events to `ReaderChromeController`. It does not intercept mouse-down events and therefore does not replace AppKit's drag handling.

The old transparent `Color.clear.frame(height: 20)` top hover zone inside `ReaderRootView` is removed. This eliminates another invisible hit layer from the reader body.

## ReaderRootView changes

Remove the top `ReaderToolbar` block from the reader content `VStack`.

The reader surface starts directly below the single native titlebar. Bottom status chrome remains unchanged.

There must be no second app-level header row in the reader body.

## Appearance

For card mode, the native titlebar/window background uses the same resolved theme background as the reader surface. With `titlebarSeparatorStyle = .none` and the toolbar baseline separator disabled, there is no system divider between titlebar and reader content.

For frameless/transparent modes, the titlebar follows the same window appearance behavior as the rest of the window.

The visual target is one continuous rounded reader card with one native top region whose controls are invisible while idle.

## Testing

Add regression tests that verify:

1. `WindowCoordinator` keeps `.titled` and `.resizable`, hides traffic-light buttons, disables `.fullSizeContentView`, and sets `titlebarSeparatorStyle == .none`.
2. exactly one native `NSToolbar` is attached to the reader window and its baseline separator is disabled.
3. `ReaderRootView.swift` no longer embeds `ReaderToolbar` in the reader body.
4. the old SwiftUI top transparent hover zone is removed.
5. toolbar button hit regions invoke their callbacks without moving the window.
6. unused native titlebar/toolbar space remains available for native window dragging.
7. native titlebar tracking forwards enter/exit to the existing chrome controller without intercepting mouse-down.
8. auto-hide timing remains the same as the existing chrome contract.
9. continuous scrolling, saved-anchor restore, debounce, and no-snap-back tests from the v0.1.9 refactor remain green.

## Manual release gate

The next RC remains on `refactor/native-window-scroll-v0.1.9` and does not merge to `main` until a real-Mac smoke test confirms:

- only one visible header region;
- controls appear on top hover and disappear afterward;
- dragging from unused titlebar space moves the window;
- toolbar buttons remain clickable;
- native edge/corner resize works;
- continuous scrolling still works and does not snap back;
- card/frameless/transparent visual modes remain correct.

The next RC uses marketing version `v0.1.9` and increments the internal build to **11**, so the already-tested build 10 artifact is never overwritten or confused with the new package.

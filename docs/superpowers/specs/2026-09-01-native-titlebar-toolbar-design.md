# ReadBook v0.1.9 Native Titlebar Toolbar Design

## Problem

The v0.1.9 RC restored native macOS titlebar dragging and native resize behavior, but the visual result exposes two stacked header regions:

1. the native macOS titlebar area, currently empty but still occupying height;
2. the SwiftUI `ReaderToolbar` rendered inside `ReaderRootView` below it.

This breaks the pure-reading appearance even though dragging and scrolling are now reliable.

## Goal

Keep the native AppKit titlebar as the only top chrome region, and move ReadBook's toolbar into that titlebar. The result should look like one single header, not a system header plus an app header.

The toolbar remains auto-hidden: it appears only when the pointer enters the top reveal zone, and fades out again using the existing chrome timing behavior.

## Architecture

### Window

`WindowCoordinator` keeps the existing native window contract:

- `.titled`
- `.resizable`
- `.closable`
- no custom drag region
- no custom resize overlay
- hidden standard traffic-light buttons
- hidden native window title
- transparent titlebar appearance

Additionally:

- `window.titlebarSeparatorStyle = .none`
- `.fullSizeContentView` remains disabled so reader content does not enter the native titlebar hit-testing region

This preserves reliable native window dragging and resize behavior.

### Native toolbar host

Add a titlebar accessory host managed from the window layer using `NSTitlebarAccessoryViewController`.

The accessory view hosts a SwiftUI toolbar through `NSHostingView`. The toolbar UI remains visually consistent with the current `ReaderToolbar`, but it is no longer part of `ReaderRootView`'s content ZStack.

The native titlebar remains the event owner. Empty space in the accessory/titlebar continues to drag the window; toolbar buttons consume only their own hit regions.

### Toolbar state bridge

`ReaderRootView` currently owns the model/runtime values needed by `ReaderToolbar`. The titlebar host must not create a second app model or duplicate business state.

Introduce a small observable titlebar state object owned by `AppRuntime` or the existing window/runtime layer. It exposes only the values/actions required by the titlebar:

- current book title
- current reading mode
- always-on-top state
- toolbar visibility
- library action
- reading-mode change action
- pin action

`ReaderRootView` synchronizes current model/runtime state into this bridge. `WindowRegistry` / the titlebar host observes the bridge and updates the hosted SwiftUI toolbar.

The bridge is intentionally narrow; no reading text, pagination, scrolling, or persistence logic moves into the titlebar layer.

## Auto-hide behavior

Use the existing `ReaderChromeController` timing semantics.

- Pointer entering the native titlebar/top reveal area starts the existing top dwell behavior.
- After the configured dwell, toolbar content fades in inside the native titlebar.
- Hovering toolbar controls holds the chrome visible.
- Leaving the titlebar/control area dismisses it using the existing delay.
- `interactiveStealth` still reveals controls immediately.
- `floatingText` / hidden states keep the toolbar hidden as today.

The old transparent `Color.clear.frame(height: 20)` top hover zone inside `ReaderRootView` is removed or restricted so it no longer represents the top titlebar interaction region.

A small native titlebar tracking view becomes responsible for top-zone enter/exit events and forwards them to `ReaderChromeController`. This avoids stretching SwiftUI content into the titlebar and avoids the old overlapping transparent hit layers.

## ReaderRootView changes

Remove the top `ReaderToolbar` block from the reader content `VStack`.

The reader surface should start immediately at the content view boundary beneath the native titlebar. Bottom status chrome remains unchanged.

There must be no second app-level header row in the reader body.

## Appearance

For card mode, the titlebar uses the same resolved theme background as the reader window. With `titlebarSeparatorStyle = .none`, the boundary between titlebar and content should not render as a system divider.

For frameless/transparent modes, the titlebar background follows the same window appearance behavior as the rest of the window.

The visual target is one continuous rounded reader card with one top toolbar region that is invisible while idle.

## Testing

Add regression tests that verify:

1. `WindowCoordinator` keeps `.titled` and `.resizable`, hides traffic-light buttons, disables `.fullSizeContentView`, and sets `titlebarSeparatorStyle == .none`.
2. `ReaderRootView.swift` no longer embeds `ReaderToolbar` in the reader body.
3. the native window installs exactly one ReadBook titlebar accessory host.
4. toolbar button hit regions still invoke their callbacks without moving the window.
5. native titlebar background/empty area remains available for window dragging.
6. native titlebar tracking forwards top enter/exit to the existing chrome controller.
7. auto-hide timing remains the same as the existing chrome contract.
8. continuous scrolling and native scroll-wheel regression tests from the v0.1.9 refactor remain green.

## Release gate

This change stays on the existing `refactor/native-window-scroll-v0.1.9` PR and does not merge to `main` until a new RC artifact is manually verified on a real Mac for:

- only one visible header region;
- toolbar appears on top hover and disappears afterward;
- dragging from unused titlebar area moves the window;
- toolbar buttons remain clickable;
- native edge/corner resize works;
- continuous scrolling still works and does not snap back;
- card/frameless/transparent visual modes remain correct.

Because the existing v0.1.9 RC has already been distributed for manual testing but not released, the final release version can remain v0.1.9/build 10 only if the packaging workflow still has not published that version. If build-number immutability is preferred for RC traceability, increment the build number before the next RC artifact while keeping marketing version v0.1.9.

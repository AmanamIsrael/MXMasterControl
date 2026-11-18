# Architecture

MX Master Control is a macOS-only menu-bar utility. It keeps the system small while preserving
hard boundaries around hardware access.

## Modules

- `MXMasterCore`: pure, testable value types, HID++ packet models, configuration, and state
  reconciliation.
- `MXMasterHID`: macOS IOHID discovery, transport, report delivery, and device lifecycle.
- `MXMasterActions`: gesture/button interpretation handoff, Accessibility checks, and macOS action
  and phased desktop-swipe posting behind injectable sinks.
- `mxmasterctl`: a permanent diagnostic surface that remains usable without the graphical app.
- `MXMasterControl`: the SwiftUI menu-bar extra, Settings scene, and AppKit lifecycle integration.

The graphical app will remain a single accessory process. IOHID work will run outside the main
actor through one serialized device session. A helper process is not part of the architecture:
unlike legacy IOBluetooth RFCOMM, IOHID can be isolated on its own queue without owning the AppKit
main run loop.

The application delegate starts the controller at process launch. Menu-bar content remains lazy,
but hardware connection and configured controls do not depend on opening the menu or Settings.

## State rules

- Saved configuration is desired state; the mouse is the source of actual state.
- Every supported write is followed by a read-back before the UI reports success.
- Device removal, mouse wake, Mac wake, permission restoration, and stale delivery recreate the
  session and increment its generation.
- Device removal is callback-driven. A two-second retry task exists only while disconnected, so a
  healthy idle connection has no polling timer.
- A new generation cancels old requests, re-probes features, reconciles desired settings, and
  re-arms volatile control diversion.
- Before arming desired mappings, the session clears stale non-persistent diversion on supported
  secondary controls. It never clears or overwrites a persistent remap.
- Control capture reads and preserves reporting state, changes only temporary diversion fields,
  and restores the original state when the capture session closes.
- Only Back, Forward, Gesture, and SmartShift are eligible for capture. Primary buttons are outside
  the action model, so a configuration bug cannot disable basic pointing and clicking.
- Native behavior is the default. If an action needs Accessibility and access is unavailable, the
  app restores native reporting instead of intercepting the button.
- Gesture interpretation and action planning are `MXMasterCore` state. Their only outside input is
  an injected check of the Dock's trackpad gesture settings. When an axis is mapped to its Dock
  pair (Desktop Left/Right, or App Exposé/Mission Control), the gesture emits a streamed
  begin/change/end sequence so the Space or Mission Control follows the held mouse movement. Any
  other mapping fires one action on release. The Dock ignores a vertical swipe when the matching
  trackpad gesture is off in System Settings, and App Exposé's is off by default. Such a swipe
  also fires one action on release. All macOS event posting remains isolated in `MXMasterActions`.
- A settings change, disconnect, or app shutdown explicitly cancels any in-progress desktop swipe
  before control capture is replaced or closed.
- The event that ends a desktop swipe is posted again after 200 ms and 500 ms. WindowServer can
  drop it under load, which leaves the Space transition stuck halfway. A repeat is skipped once the
  next swipe has started.
- Swipe progress is scaled by the display width and the number of Spaces on the display under the
  pointer, so the Space moves as far as the hand. The Space count comes from SkyLight at the start
  of each swipe.
- The undocumented Dock-swipe event encoding required for trackpad-style Space transitions is
  confined to one synthesizer. The rest of the app depends only on typed `DesktopSwipeUpdate`
  values, keeping future macOS-specific changes local.
- System actions (Mission Control, App Exposé, Show Desktop, and moving between Spaces) post the
  shortcut that WindowServer has bound to the feature at that moment, read through the private
  symbolic hot key API. A user's custom shortcut keeps working. A shortcut the user turned off is
  rebound, for the session only, to a key code no keyboard produces. The feature still runs, and
  the user's keys and saved shortcuts stay as they are.
- Back and Forward pick a method for the frontmost app from a pure routing table in
  `MXMasterCore`: mouse buttons 4 and 5 by default, the trackpad page swipe for Apple apps, and a
  per-app shortcut where ⌘[ would edit text or does nothing.
- Firmware update commands are permanently outside the project scope.

## Dependency policy

Use Apple frameworks and the installed Swift toolchain. A third-party dependency requires a
capability and version check plus a clear benefit that native frameworks cannot provide.

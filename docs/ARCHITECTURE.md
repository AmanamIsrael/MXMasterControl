# Architecture

MX Master Control is a macOS-only menu-bar utility. It keeps the system small while preserving
hard boundaries around hardware access.

## Modules

- `MXMasterCore`: pure, testable value types, HID++ packet models, configuration, and state
  reconciliation.
- `MXMasterHID`: macOS IOHID discovery, transport, report delivery, and device lifecycle.
- `mxmasterctl`: a permanent diagnostic surface that remains usable without the graphical app.
- `MXMasterControl`: the SwiftUI menu-bar extra, Settings scene, and AppKit lifecycle integration.

The graphical app will remain a single accessory process. IOHID work will run outside the main
actor through one serialized device session. A helper process is not part of the architecture:
unlike legacy IOBluetooth RFCOMM, IOHID can be isolated on its own queue without owning the AppKit
main run loop.

## State rules

- Saved configuration is desired state; the mouse is the source of actual state.
- Every supported write is followed by a read-back before the UI reports success.
- Device removal, mouse wake, Mac wake, permission restoration, and stale delivery recreate the
  session and increment its generation.
- Device removal is callback-driven. A five-second retry task exists only while disconnected, so a
  healthy idle connection has no polling timer.
- A new generation cancels old requests, re-probes features, reconciles desired settings, and
  re-arms volatile control diversion.
- Control capture reads and preserves reporting state, changes only temporary diversion fields,
  and restores the original state when the capture session closes.
- Only Back, Forward, Gesture, and SmartShift are eligible for capture. Primary buttons are outside
  the action model, so a configuration bug cannot disable basic pointing and clicking.
- Native behavior is the default. If an action needs Accessibility and access is unavailable, the
  app restores native reporting instead of intercepting the button.
- Gesture interpretation and action planning are pure `MXMasterCore` state, while macOS event
  posting remains in the app target.
- Firmware update commands are permanently outside the project scope.

## Dependency policy

Use Apple frameworks and the installed Swift toolchain. A third-party dependency requires a
capability and version check plus a clear benefit that native frameworks cannot provide.

# Architecture

MX Master Control is a macOS-only menu-bar utility. It keeps the system small while preserving
hard boundaries around hardware access.

## Modules

- `MXMasterCore`: pure, testable value types, HID++ packet models, configuration, and state
  reconciliation.
- `MXMasterHID`: macOS IOHID discovery, transport, report delivery, and device lifecycle.
- `mxmasterctl`: a permanent diagnostic surface that remains usable without the graphical app.
- `MXMasterControl`: the AppKit status item and lazily loaded SwiftUI controls (planned).

The graphical app will remain a single accessory process. IOHID work will run outside the main
actor through one serialized device session. A helper process is not part of the architecture:
unlike legacy IOBluetooth RFCOMM, IOHID can be isolated on its own queue without owning the AppKit
main run loop.

## State rules

- Saved configuration is desired state; the mouse is the source of actual state.
- Every supported write is followed by a read-back before the UI reports success.
- Device removal, mouse wake, Mac wake, permission restoration, and stale delivery recreate the
  session and increment its generation.
- A new generation cancels old requests, re-probes features, reconciles desired settings, and
  re-arms volatile control diversion.
- Control capture reads and preserves reporting state, changes only temporary diversion fields,
  and restores the original state when the capture session closes.
- Firmware update commands are permanently outside the project scope.

## Dependency policy

Use Apple frameworks and the installed Swift toolchain. A third-party dependency requires a
capability and version check plus a clear benefit that native frameworks cannot provide.

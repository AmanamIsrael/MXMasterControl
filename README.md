# MX Master Control

A lightweight, native macOS controller for a Logitech MX Master 3 connected directly over
Bluetooth. The project is intentionally scoped to the device currently under test: Logitech
USB identifier `046d:b023`.

The current build supports live battery/state reporting, DPI, SmartShift, wheel direction,
secondary-button actions, and native, continuous Space-swipe navigation from the Gesture button.
Hardware writes are read back before the UI reports success, and control diversion is temporary
and restored when the app exits.

## Requirements

- macOS 15 or newer
- Apple Swift 6 toolchain
- Logitech MX Master 3 connected directly over Bluetooth
- Input Monitoring permission for the bundled app
- Accessibility permission when custom actions are enabled

## Read-only diagnostic

```sh
swift run mxmasterctl --diagnose
```

The diagnostic enumerates matching IOHID interfaces and prints redacted JSON. It does not seize
the mouse, register an input hook, send HID reports, or change settings.

To query the HID++ feature table without changing settings:

```sh
swift run mxmasterctl --probe-features
```

Read the current supported settings and reprogrammable-control table:

```sh
swift run mxmasterctl --read-state
swift run mxmasterctl --read-control-reporting
```

If an interrupted development session leaves a secondary control temporarily diverted, restore
native volatile reporting without touching persistent remaps:

```sh
swift run mxmasterctl --restore-native-control-reporting
```

For a bounded physical-input check, the capture command arms the four secondary controls for 15
seconds, prints JSON events, and verifies restoration before it exits:

```sh
swift run mxmasterctl --capture-events
```

A development-only reversible DPI round-trip is also available. It always attempts to restore
the original DPI and verifies the restoration before reporting success:

```sh
swift run mxmasterctl --test-dpi-round-trip
```

SmartShift and vertical-wheel settings have a matching restore-first validation:

```sh
swift run mxmasterctl --test-settings-round-trip
swift run mxmasterctl --test-control-capture-round-trip
```

The control-capture round-trip temporarily diverts Back, Forward, Gesture, and SmartShift through
one HID++ session, verifies the diversion, then restores and verifies all original states.

## Validate

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

The app stays in the menu bar and keeps its icon visible when the mouse is unavailable so
permissions and recovery remain accessible.

The app requests Input Monitoring through Apple's HID access API and links directly to the matching
System Settings pane when access is missing. Custom actions request Accessibility only when they
are enabled; without it, controls remain native rather than being swallowed.

For stable privacy permissions, sign builds with an Apple Development or Developer ID identity:

```sh
MXMASTER_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

If no identity is supplied, the build is ad-hoc signed and warns that privacy access can require
reauthorization after a rebuild.

Development builds can open the Settings scene directly for UI testing:

```sh
open "dist/MX Master Control.app" --args --show-settings
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design boundaries and
[docs/VALIDATION.md](docs/VALIDATION.md) for current hardware evidence, and
[docs/COMPLETION-AUDIT.md](docs/COMPLETION-AUDIT.md) for the requirement-by-requirement status.

## License

MIT. Logitech and MX Master are trademarks of Logitech International S.A. This project is not
affiliated with or endorsed by Logitech.

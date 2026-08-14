# MX Master Control

A lightweight, native macOS controller for a Logitech MX Master 3 connected directly over
Bluetooth. The project is intentionally scoped to the device currently under test: Logitech
USB identifier `046d:b023`.

The project is under active development. The current checkpoint is read-only HID discovery and
HID++ feature probing; no mouse-setting commands are sent yet.

## Requirements

- macOS 15 or newer
- Apple Swift 6 toolchain
- Logitech MX Master 3 connected directly over Bluetooth
- Input Monitoring permission for the bundled app

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
```

A development-only reversible DPI round-trip is also available. It always attempts to restore
the original DPI and verifies the restoration before reporting success:

```sh
swift run mxmasterctl --test-dpi-round-trip
```

## Validate

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

The app stays in the menu bar and keeps its icon visible when the mouse is unavailable so
permissions and recovery remain accessible.

The app links directly to System Settings → Privacy & Security → Input Monitoring when access is
missing. Development bundles use a stable designated code-signing requirement so permission does
not churn after every rebuild.

Development builds can open the Settings scene directly for UI testing:

```sh
open "dist/MX Master Control.app" --args --show-settings
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design boundaries and
[docs/VALIDATION.md](docs/VALIDATION.md) for current hardware evidence.

## License

MIT. Logitech and MX Master are trademarks of Logitech International S.A. This project is not
affiliated with or endorsed by Logitech.

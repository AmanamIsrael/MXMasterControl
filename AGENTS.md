# Repository guidance

- Keep the app macOS-only and focused on the Logitech MX Master 3 (`046d:b023`) over direct Bluetooth until that path is reliable.
- Prefer Apple frameworks and the installed Swift toolchain over third-party dependencies.
- Keep HID transport, HID++ protocol, lifecycle reconciliation, configuration, action dispatch, and UI concerns separate.
- Device writes must be typed, serialized, bounded by timeouts, read back, and reversible where practical.
- Never implement or send firmware-update commands.
- Preserve read-only diagnostics even when permissions or device ownership prevent control.
- Run `swift test` and `swift build -c release` after changes.

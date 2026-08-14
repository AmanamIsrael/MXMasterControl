# Validation evidence

## Environment

- Hardware target: Logitech MX Master 3
- Connection: direct Bluetooth Low Energy
- USB identifier: `046d:b023`
- Development host: Apple silicon macOS

## Checkpoints

### Read-only discovery

Status: passed on 2026-08-14.

Required evidence:

- `swift test` passes.
- `swift build -c release` passes.
- `swift run mxmasterctl --diagnose` returns at least one matching interface.
- Diagnostic output contains no serial number or other stable device identifier.

Observed interfaces:

- Product: MX Master 3
- Transport: Bluetooth Low Energy
- Primary usage: `0x0001:0x0006`
- HID++ usage pair: `0xff43:0x0202`
- Report descriptor: 140 bytes
- Input Monitoring/listen access: granted

### HID++ feature probe

Status: passed on 2026-08-14.

- Protocol number: 4
- Feature count: 30
- Battery Status `0x1000`: table index 8
- Reprogrammable Controls `0x1b04`: table index 9
- Adjustable DPI `0x2201`: table index 12
- SmartShift `0x2110`: table index 13
- HiRes Wheel `0x2121`: table index 14
- Thumb Wheel `0x2150`: table index 15

Only read-only HID++ queries were sent. No setting function was called.

### Read-only device state

Status: passed on 2026-08-14.

- Battery: 100%, discharging
- DPI: 1000; one sensor; supported range 200–4000 in 50-DPI increments
- SmartShift: free-spin mode; auto-disengage 10; default 10
- HiRes wheel: native, low-resolution, non-inverted; inversion and ratchet switch supported
- Thumb wheel: native, non-inverted; touch, proximity, timestamp, and tap capabilities reported
- Reprogrammable controls: 8 rows

### Reversible DPI round-trip

Status: passed on 2026-08-14.

- Original DPI: 1000
- Test DPI: 1050
- Test value read back: 1050
- Restored DPI read back: 1000
- A second read-only state capture confirmed the mouse remained at 1000 DPI.

### Bundled app

Status: permission remediation verified; control validation pending Input Monitoring grant.

- The signed app launches without crashing.
- The Settings UI is accessible through the development launch path.
- Without app-specific Input Monitoring access, IOHID returns `kIOReturnNotPermitted`.
- The UI translates that status into permission guidance instead of exposing a numeric IOReturn.
- The deep link opens the correct Input Monitoring pane and the app is present in its list.
- The existing enabled entry was created by an earlier changing ad-hoc signature; a one-time
  off/on toggle or remove/re-add is required to refresh the TCC record for the stable requirement.

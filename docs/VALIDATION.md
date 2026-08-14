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

Status: passed on 2026-08-14.

- The signed app launches without crashing.
- The Settings UI is accessible through the development launch path.
- Without app-specific Input Monitoring access, IOHID returns `kIOReturnNotPermitted`.
- The UI translates that status into permission guidance instead of exposing a numeric IOReturn.
- The app explicitly requests access with `IOHIDRequestAccess` and links to the correct pane.
- After removing the stale TCC record for an earlier ad-hoc build, the newly requested grant was
  recognized on the next connection attempt.
- The bundled process connected and displayed battery 100%, 1000 DPI, free-spin mode, SmartShift
  threshold 10, and normal wheel direction.
- There is no development signing identity on this host. Ad-hoc rebuilds can require permission
  reauthorization; `MXMASTER_SIGNING_IDENTITY` selects stable signing when a certificate exists.

### Reversible SmartShift and wheel round-trip

Status: passed on 2026-08-14.

- SmartShift threshold: 10 → 11 → 10; both the test value and restoration were read back.
- SmartShift mode remained 1 (free spin) after restoration.
- Wheel inversion: false → true → false; both the test value and restoration were read back.
- A final read-only snapshot confirmed DPI 1000, SmartShift threshold 10, and non-inverted wheel.

### Reversible control-capture round-trip

Status: passed on 2026-08-14.

- One shared HID++ channel temporarily diverted Back (`0x0053`), Forward (`0x0056`), Gesture
  (`0x00c3`, with raw movement), and SmartShift (`0x00c4`).
- Each diversion was read back before the session was considered armed.
- Session close restored and read back every original reporting state.
- A post-test device snapshot confirmed DPI 1000, SmartShift threshold 10, and non-inverted wheel.

### Performance and lifecycle

Status: passed on 2026-08-15; sleep/wake remains optional manual coverage.

- Release app bundle: 1.3 MB, with no third-party runtime dependencies.
- Normal menu-bar idle: 15.0 MB physical footprint and 0.0% sampled CPU after launch.
- Settings window open: 40.1 MB physical footprint and 0.0% sampled CPU after settling.
- The HID device registers a removal callback; removal invalidates the vanished session without
  blocking on dead-channel restoration.
- Reconnect checks run every two seconds only while disconnected. Mac wake and screen wake also
  invalidate, reopen, re-probe, reconcile settings, and re-arm configured volatile controls.
- During a real mouse power cycle, the UI transitioned from Connected to Mouse not found, then to
  Connecting and back to Connected.
- Once reconnect entered Connecting, it reached Connected in approximately three seconds.
- Hardware reads after reconnect confirmed desired 1900 DPI, SmartShift threshold 10, reversed
  scrolling, and Gesture temporary diversion with raw movement all reapplied.

### Action safety and clean shutdown

Status: passed on physical hardware on 2026-08-15.

- All four mappings default to System Default and Diagnostics reports `Native`.
- Selecting Mission Control for SmartShift without Accessibility displayed remediation while
  Diagnostics remained `Native`; the button was not diverted or swallowed.
- Restoring System Default removed the desired binding from the version-2 configuration file.
- Command-Q used the asynchronous application termination path and the process exited normally.
- A post-exit hardware read confirmed DPI 1000, SmartShift threshold 10, and non-inverted wheel.
- Bounded real-device capture observed Back (`0x0053`), Forward (`0x0056`), Gesture (`0x00c3`),
  SmartShift (`0x00c4`), matching releases, and hundreds of signed raw-movement packets.
- Production app logs observed `desktopLeft`, `desktopRight`, and `missionControl` classification
  from physical Gesture input.
- Mission Control uses the public system application launcher and logged successful launch.
- Desktop switching emits phased Dock-swipe events from the live HID++ raw-movement stream rather
  than a shortcut after release. The user confirmed that desktops follow the held mouse movement,
  settle correctly on release, and work in both directions.
- The mouse-oriented direction was reversed after physical testing and the user confirmed the
  resulting interaction feels natural.
- Lifecycle cancellation covers configuration replacement, device removal, and app shutdown so an
  interrupted swipe cannot leave a transition active.
- A normal menu-bar-only launch, without opening any app UI, read back Gesture `0x00c3` as diverted
  with raw movement. This closes a discovered bug where lazy `MenuBarExtra` content delayed startup.

### Volatile reporting reconciliation

Status: passed on 2026-08-14.

- A new read-only reporting probe found stale temporary diversion on Gesture (`0x00c3`) while all
  configured mappings were native.
- Reconciliation cleared only that non-persistent diversion and read it back as false. Persistent
  diversion, remap, analytics, force-raw, and raw-wheel fields are preserved by construction.
- A second read-only probe showed Back, Forward, Gesture, and SmartShift all native.
- With SmartShift configured as Do Nothing, the UI reported `Active` and the hardware probe showed
  only `0x00c4` temporarily diverted.
- Command-Q restored `0x00c4`; all four controls read native after process exit.
- Relaunch loaded the version-2 configuration and re-armed only `0x00c4`.
- Changing SmartShift to System Default while running restored native reporting without restart and
  removed the binding from the configuration file.
- Two 15-second physical captures recorded 265 and 203 events respectively, covering all four
  secondary control IDs, release packets, and raw movement. Both runs restored all controls.

### Action pipeline tests

Status: passed on 2026-08-15.

- A configured SmartShift press reaches the injected action sink exactly once; repeated held-state
  packets do not duplicate the action.
- Gesture press and raw horizontal movement stream begin/change/end desktop-swipe updates; vertical
  and click gestures retain dominant-direction discrete action dispatch.
- Tests cover direction reversal, vertical axis lock, and cancellation of an active swipe during a
  lifecycle/configuration change.
- Every action that requires event posting maps to a concrete macOS key code and modifier set;
  System Default and Do Nothing intentionally map to no synthetic event.
- These tests exercise the same `MXMasterActions` coordinator used by the bundled app. Production
  unified logs additionally confirmed physical HID input reached the Accessibility-authorized
  action posting path.

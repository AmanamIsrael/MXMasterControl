import Testing

@testable import MXMasterCore

@Test func capturePlanLeavesNativeControlsUntouchedByDefault() {
  #expect(ControlCapturePlanner.requests(for: MXMasterConfiguration()).isEmpty)
}

@Test func capturePlanUsesRawMovementOnlyForGestureNavigation() {
  var configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  configuration.setAction(.missionControl, for: .smartShift)

  #expect(
    ControlCapturePlanner.requests(for: configuration) == [
      ControlCaptureRequest(controlID: MouseControl.gesture.rawValue, rawMovement: true),
      ControlCaptureRequest(controlID: MouseControl.smartShift.rawValue, rawMovement: false),
    ])
}

@Test func buttonActionFiresOnlyOnPress() {
  var configuration = MXMasterConfiguration()
  configuration.setAction(.missionControl, for: .smartShift)
  var interpreter = ControlEventInterpreter(configuration: configuration)

  #expect(
    interpreter.handle(.divertedButtons([MouseControl.smartShift.rawValue])) == [
      .action(.missionControl)
    ])
  #expect(interpreter.handle(.divertedButtons([MouseControl.smartShift.rawValue])).isEmpty)
  #expect(interpreter.handle(.divertedButtons([])).isEmpty)
}

@Test func gestureChoosesDominantDirectionOnRelease() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  var interpreter = ControlEventInterpreter(configuration: configuration, movementThreshold: 40)

  #expect(interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue])).isEmpty)
  #expect(
    interpreter.handle(.rawMovement(dx: -45, dy: 5)) == [
      .desktopSwipe(DesktopSwipeUpdate(phase: .began, deltaX: -45))
    ])
  #expect(
    interpreter.handle(.rawMovement(dx: -12, dy: 1)) == [
      .desktopSwipe(DesktopSwipeUpdate(phase: .changed, deltaX: -12))
    ])
  #expect(
    interpreter.handle(.divertedButtons([])) == [
      .desktopSwipe(DesktopSwipeUpdate(phase: .ended, deltaX: 0))
    ])
}

@Test func shortGestureUsesClickAction() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  var interpreter = ControlEventInterpreter(configuration: configuration, movementThreshold: 40)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  _ = interpreter.handle(.rawMovement(dx: 10, dy: 4))
  #expect(interpreter.handle(.divertedButtons([])) == [.action(.showDesktop)])
}

@Test func gestureDirectionsCanBeCustomizedIndependently() {
  var configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  configuration.gestureActions.setAction(.disabled, for: .left)
  configuration.gestureActions.setAction(.forward, for: .right)
  var interpreter = ControlEventInterpreter(configuration: configuration, movementThreshold: 40)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  _ = interpreter.handle(.rawMovement(dx: -50, dy: 0))
  #expect(interpreter.handle(.divertedButtons([])).isEmpty)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  _ = interpreter.handle(.rawMovement(dx: 50, dy: 0))
  #expect(interpreter.handle(.divertedButtons([])) == [.action(.forward)])
}

@Test func desktopSwipeCanBeDirectionReversedByConfiguration() {
  var configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  configuration.gestureActions.left = .desktopRight
  configuration.gestureActions.right = .desktopLeft
  var interpreter = ControlEventInterpreter(configuration: configuration)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  #expect(
    interpreter.handle(.rawMovement(dx: -50, dy: 0)) == [
      .desktopSwipe(DesktopSwipeUpdate(phase: .began, deltaX: 50))
    ])
}

@Test func verticalGestureStaysDiscreteAfterAxisLocks() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  var interpreter = ControlEventInterpreter(configuration: configuration)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  #expect(interpreter.handle(.rawMovement(dx: 2, dy: -25)).isEmpty)
  #expect(interpreter.handle(.rawMovement(dx: -100, dy: 0)).isEmpty)
  #expect(interpreter.handle(.divertedButtons([])) == [.action(.desktopLeft)])
}

@Test func pendingDesktopSwipeCanBeCancelledOnLifecycleChange() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  var interpreter = ControlEventInterpreter(configuration: configuration)

  _ = interpreter.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  _ = interpreter.handle(.rawMovement(dx: 50, dy: 0))

  #expect(
    interpreter.cancelPendingGesture()
      == .desktopSwipe(DesktopSwipeUpdate(phase: .cancelled, deltaX: 0)))
  #expect(interpreter.cancelPendingGesture() == nil)
  #expect(interpreter.handle(.rawMovement(dx: 50, dy: 0)).isEmpty)
}

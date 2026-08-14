import Foundation

public enum MouseControl: UInt16, Codable, CaseIterable, Identifiable, Sendable {
  case back = 0x0053
  case forward = 0x0056
  case gesture = 0x00C3
  case smartShift = 0x00C4

  public var id: UInt16 { rawValue }

  public var title: String {
    switch self {
    case .back: "Back button"
    case .forward: "Forward button"
    case .gesture: "Gesture button"
    case .smartShift: "SmartShift button"
    }
  }
}

public enum MouseAction: String, Codable, CaseIterable, Identifiable, Sendable {
  case systemDefault
  case disabled
  case back
  case forward
  case missionControl
  case appExpose
  case showDesktop
  case desktopLeft
  case desktopRight

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .systemDefault: "System Default"
    case .disabled: "Do Nothing"
    case .back: "Back"
    case .forward: "Forward"
    case .missionControl: "Mission Control"
    case .appExpose: "App Exposé"
    case .showDesktop: "Show Desktop"
    case .desktopLeft: "Desktop Left"
    case .desktopRight: "Desktop Right"
    }
  }

  public var postsKeyboardEvent: Bool {
    self != .systemDefault && self != .disabled
  }
}

public struct MouseControlBinding: Codable, Equatable, Sendable {
  public var control: MouseControl
  public var action: MouseAction

  public init(control: MouseControl, action: MouseAction) {
    self.control = control
    self.action = action
  }
}

public struct GestureActions: Codable, Equatable, Sendable {
  public var click: MouseAction
  public var up: MouseAction
  public var down: MouseAction
  public var left: MouseAction
  public var right: MouseAction

  public init(
    click: MouseAction = .showDesktop,
    up: MouseAction = .missionControl,
    down: MouseAction = .appExpose,
    left: MouseAction = .desktopLeft,
    right: MouseAction = .desktopRight
  ) {
    self.click = click
    self.up = up
    self.down = down
    self.left = left
    self.right = right
  }

  public func action(for direction: GestureDirection) -> MouseAction {
    switch direction {
    case .click: click
    case .up: up
    case .down: down
    case .left: left
    case .right: right
    }
  }

  public mutating func setAction(_ action: MouseAction, for direction: GestureDirection) {
    switch direction {
    case .click: click = action
    case .up: up = action
    case .down: down = action
    case .left: left = action
    case .right: right = action
    }
  }
}

public enum GestureDirection: String, Codable, CaseIterable, Identifiable, Sendable {
  case click
  case up
  case down
  case left
  case right

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .click: "Click"
    case .up: "Move Up"
    case .down: "Move Down"
    case .left: "Move Left"
    case .right: "Move Right"
    }
  }
}

public struct ControlCaptureRequest: Equatable, Sendable {
  public let controlID: UInt16
  public let rawMovement: Bool

  public init(controlID: UInt16, rawMovement: Bool) {
    self.controlID = controlID
    self.rawMovement = rawMovement
  }
}

public enum ControlCapturePlanner {
  public static func requests(for configuration: MXMasterConfiguration) -> [ControlCaptureRequest] {
    MouseControl.allCases.compactMap { control in
      let action = configuration.action(for: control)
      let isGestureControl = control == .gesture && configuration.gestureNavigationEnabled
      guard action != .systemDefault || isGestureControl else { return nil }
      return ControlCaptureRequest(
        controlID: control.rawValue,
        rawMovement: isGestureControl
      )
    }
  }
}

public struct DesktopSwipeUpdate: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
  }

  public let phase: Phase
  public let deltaX: Int32

  public init(phase: Phase, deltaX: Int32) {
    self.phase = phase
    self.deltaX = deltaX
  }
}

public enum MouseInputEffect: Equatable, Sendable {
  case action(MouseAction)
  case desktopSwipe(DesktopSwipeUpdate)
}

public struct ControlEventInterpreter: Sendable {
  private enum GestureMode: Sendable {
    case undecided
    case discrete
    case desktopSwipe(directionMultiplier: Int32)
  }

  private let configuration: MXMasterConfiguration
  private let movementThreshold: Int32
  private let swipeActivationThreshold: Int32
  private var pressedControls: Set<UInt16> = []
  private var gestureMovementX: Int32 = 0
  private var gestureMovementY: Int32 = 0
  private var gestureMode = GestureMode.undecided

  public init(
    configuration: MXMasterConfiguration,
    movementThreshold: Int32 = 40,
    swipeActivationThreshold: Int32 = 20
  ) {
    self.configuration = configuration
    self.movementThreshold = movementThreshold
    self.swipeActivationThreshold = swipeActivationThreshold
  }

  public mutating func handle(_ event: HIDPPControlEvent) -> [MouseInputEffect] {
    switch event {
    case .rawMovement(let dx, let dy):
      guard pressedControls.contains(MouseControl.gesture.rawValue) else { return [] }
      gestureMovementX = Int32(clamping: Int64(gestureMovementX) + Int64(dx))
      gestureMovementY = Int32(clamping: Int64(gestureMovementY) + Int64(dy))

      switch gestureMode {
      case .desktopSwipe(let directionMultiplier):
        return [
          .desktopSwipe(
            DesktopSwipeUpdate(
              phase: .changed,
              deltaX: Int32(clamping: Int64(dx) * Int64(directionMultiplier))
            ))
        ]
      case .discrete:
        return []
      case .undecided:
        return activateGestureIfNeeded()
      }

    case .divertedButtons(let currentControls):
      let current = Set(currentControls)
      let pressed = current.subtracting(pressedControls)
      let released = pressedControls.subtracting(current)
      pressedControls = current

      var effects: [MouseInputEffect] = []
      for controlID in pressed.sorted() {
        guard let control = MouseControl(rawValue: controlID) else { continue }
        if control == .gesture, configuration.gestureNavigationEnabled {
          gestureMovementX = 0
          gestureMovementY = 0
          gestureMode = .undecided
        } else {
          append(configuration.action(for: control), to: &effects)
        }
      }

      if released.contains(MouseControl.gesture.rawValue), configuration.gestureNavigationEnabled {
        if case .desktopSwipe = gestureMode {
          effects.append(
            .desktopSwipe(DesktopSwipeUpdate(phase: .ended, deltaX: 0)))
        } else {
          append(gestureAction(), to: &effects)
        }
        gestureMovementX = 0
        gestureMovementY = 0
        gestureMode = .undecided
      }
      return effects
    }
  }

  public mutating func cancelPendingGesture() -> MouseInputEffect? {
    defer {
      pressedControls.remove(MouseControl.gesture.rawValue)
      gestureMovementX = 0
      gestureMovementY = 0
      gestureMode = .undecided
    }
    guard case .desktopSwipe = gestureMode else { return nil }
    return .desktopSwipe(DesktopSwipeUpdate(phase: .cancelled, deltaX: 0))
  }

  private mutating func activateGestureIfNeeded() -> [MouseInputEffect] {
    let horizontal = abs(Int64(gestureMovementX))
    let vertical = abs(Int64(gestureMovementY))
    guard max(horizontal, vertical) >= swipeActivationThreshold else { return [] }

    guard horizontal > vertical else {
      gestureMode = .discrete
      return []
    }

    let gestures = configuration.gestureActions
    let directionMultiplier: Int32
    if gestures.left == .desktopLeft, gestures.right == .desktopRight {
      directionMultiplier = 1
    } else if gestures.left == .desktopRight, gestures.right == .desktopLeft {
      directionMultiplier = -1
    } else {
      gestureMode = .discrete
      return []
    }

    gestureMode = .desktopSwipe(directionMultiplier: directionMultiplier)
    return [
      .desktopSwipe(
        DesktopSwipeUpdate(
          phase: .began,
          deltaX: Int32(clamping: Int64(gestureMovementX) * Int64(directionMultiplier))
        ))
    ]
  }

  private func gestureAction() -> MouseAction {
    let gestures = configuration.gestureActions
    let horizontal = abs(Int64(gestureMovementX))
    let vertical = abs(Int64(gestureMovementY))
    guard max(horizontal, vertical) >= Int64(movementThreshold) else { return gestures.click }
    if horizontal > vertical {
      return gestureMovementX < 0 ? gestures.left : gestures.right
    }
    return gestureMovementY < 0 ? gestures.up : gestures.down
  }

  private func append(_ action: MouseAction, to effects: inout [MouseInputEffect]) {
    guard action.postsKeyboardEvent else { return }
    effects.append(.action(action))
  }
}

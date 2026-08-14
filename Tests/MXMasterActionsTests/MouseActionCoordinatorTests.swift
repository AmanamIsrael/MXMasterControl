import CoreGraphics
import Foundation
import MXMasterCore
import Testing

@testable import MXMasterActions

private final class ActionRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedActions: [MouseAction] = []

  func record(_ action: MouseAction) {
    lock.lock()
    recordedActions.append(action)
    lock.unlock()
  }

  var actions: [MouseAction] {
    lock.lock()
    defer { lock.unlock() }
    return recordedActions
  }
}

@Test func coordinatorDispatchesConfiguredButtonActionOncePerPress() {
  var configuration = MXMasterConfiguration()
  configuration.setAction(.missionControl, for: .smartShift)
  let recorder = ActionRecorder()
  let coordinator = MouseActionCoordinator(
    configuration: configuration,
    postAction: recorder.record
  )

  coordinator.handle(.divertedButtons([MouseControl.smartShift.rawValue]))
  coordinator.handle(.divertedButtons([MouseControl.smartShift.rawValue]))
  coordinator.handle(.divertedButtons([]))

  #expect(recorder.actions == [.missionControl])
}

@Test func coordinatorDispatchesGestureAfterMovementAndRelease() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  let recorder = ActionRecorder()
  let coordinator = MouseActionCoordinator(
    configuration: configuration,
    postAction: recorder.record
  )

  coordinator.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  coordinator.handle(.rawMovement(dx: -50, dy: 3))
  coordinator.handle(.divertedButtons([]))

  #expect(recorder.actions == [.desktopLeft])
}

@Test func everyPostableActionHasAKeyboardShortcut() {
  for action in MouseAction.allCases {
    let shortcut = MouseActionDispatcher.shortcut(for: action)
    #expect((shortcut != nil) == action.postsKeyboardEvent)
  }
  #expect(MouseActionDispatcher.shortcut(for: .back)?.flags == .maskCommand)
  #expect(MouseActionDispatcher.shortcut(for: .desktopRight)?.flags == .maskControl)
}

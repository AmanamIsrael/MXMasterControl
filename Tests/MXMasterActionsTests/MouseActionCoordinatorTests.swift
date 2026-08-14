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

private final class SwipeRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedUpdates: [DesktopSwipeUpdate] = []

  func record(_ update: DesktopSwipeUpdate) {
    lock.lock()
    recordedUpdates.append(update)
    lock.unlock()
  }

  var updates: [DesktopSwipeUpdate] {
    lock.lock()
    defer { lock.unlock() }
    return recordedUpdates
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
  let actionRecorder = ActionRecorder()
  let swipeRecorder = SwipeRecorder()
  let coordinator = MouseActionCoordinator(
    configuration: configuration,
    postAction: actionRecorder.record,
    postDesktopSwipe: swipeRecorder.record
  )

  coordinator.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  coordinator.handle(.rawMovement(dx: -50, dy: 3))
  coordinator.handle(.divertedButtons([]))

  #expect(actionRecorder.actions.isEmpty)
  #expect(
    swipeRecorder.updates == [
      DesktopSwipeUpdate(phase: .began, deltaX: -50),
      DesktopSwipeUpdate(phase: .ended, deltaX: 0),
    ])
}

@Test func coordinatorCancelsActiveSwipeBeforeReplacingConfiguration() {
  let configuration = MXMasterConfiguration(gestureNavigationEnabled: true)
  let swipeRecorder = SwipeRecorder()
  let coordinator = MouseActionCoordinator(
    configuration: configuration,
    postAction: { _ in },
    postDesktopSwipe: swipeRecorder.record
  )

  coordinator.handle(.divertedButtons([MouseControl.gesture.rawValue]))
  coordinator.handle(.rawMovement(dx: 50, dy: 0))
  coordinator.update(configuration: MXMasterConfiguration())

  #expect(swipeRecorder.updates.last?.phase == .cancelled)
}

@Test func everyPostableActionHasAKeyboardShortcut() {
  for action in MouseAction.allCases {
    let shortcut = MouseActionDispatcher.shortcut(for: action)
    #expect((shortcut != nil) == action.postsKeyboardEvent)
  }
  #expect(MouseActionDispatcher.shortcut(for: .back)?.flags == .maskCommand)
  #expect(MouseActionDispatcher.shortcut(for: .desktopRight)?.flags == .maskControl)
  #expect(MouseActionDispatcher.modifierKeys(for: .maskControl).map(\.keyCode) == [59])
  #expect(MouseActionDispatcher.modifierKeys(for: .maskCommand).map(\.keyCode) == [55])
}

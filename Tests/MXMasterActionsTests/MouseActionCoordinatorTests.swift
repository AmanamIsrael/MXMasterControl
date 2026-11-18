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
      DesktopSwipeUpdate(phase: .began, axis: .horizontal, delta: -50),
      DesktopSwipeUpdate(phase: .ended, axis: .horizontal, delta: 0),
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

@Test func everyPostableActionHasARoute() {
  for action in MouseAction.allCases {
    #expect((MouseActionDispatcher.route(for: action) != nil) == action.postsKeyboardEvent)
  }
  #expect(MouseActionDispatcher.route(for: .missionControl) == .systemHotKey(.missionControl))
  #expect(MouseActionDispatcher.route(for: .desktopRight) == .systemHotKey(.moveRightASpace))
  #expect(MouseActionDispatcher.modifierKeys(for: .maskControl).map(\.keyCode) == [59])
  #expect(
    MouseActionDispatcher.modifierKeys(for: [.maskCommand, .maskAlternate]).map(\.keyCode)
      == [58, 55])
}

@Test func enabledHotKeyPostsTheUsersBinding() {
  #expect(
    SystemHotKeys.usableBinding(enabled: true, keyCode: 126, modifiers: 0x84_0000)
      == SystemHotKeys.Binding(keyCode: 126, flags: [.maskControl, .maskSecondaryFn]))
}

@Test func disabledOrUnboundHotKeyNeedsTheUnreachableBinding() {
  #expect(SystemHotKeys.usableBinding(enabled: false, keyCode: 126, modifiers: 0x4_0000) == nil)
  #expect(
    SystemHotKeys.usableBinding(enabled: true, keyCode: SystemHotKeys.unset, modifiers: 0) == nil)
  let fallback = SystemHotKeys.unreachableBinding(for: .appExpose)
  #expect(fallback.keyCode == 433)
  #expect(fallback.flags == [.maskNumericPad, .maskSecondaryFn])
}

@Test func navigationOutputMatchesEachMethod() {
  #expect(
    NavigationPoster.output(for: .mouseButton, direction: .back)
      == .mouseButton(CGMouseButton(rawValue: 3)!))
  #expect(
    NavigationPoster.output(for: .mouseButton, direction: .forward)
      == .mouseButton(CGMouseButton(rawValue: 4)!))
  #expect(NavigationPoster.output(for: .pageSwipe, direction: .back) == .pageSwipe(.back))
  #expect(
    NavigationPoster.output(for: .optionCommandBracket, direction: .forward)
      == .shortcut(MouseKeyboardShortcut(keyCode: 30, flags: [.maskCommand, .maskAlternate])))
  #expect(
    NavigationPoster.output(for: .commandArrow, direction: .back)
      == .shortcut(MouseKeyboardShortcut(keyCode: 123, flags: .maskCommand)))
}

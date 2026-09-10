import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: Error, Sendable {
  case inputMonitoringPermissionMissing
  case eventTapCreationFailed
  case eventTapStartupTimedOut
}

actor CGEventTapHotKeyMonitor: GlobalHotKeyMonitoring {
  private var runner: EventTapRunner?
  private var continuation: AsyncStream<HotKeyEvent>.Continuation?

  init() {}

  func events(for binding: WakeBinding) async throws -> AsyncStream<HotKeyEvent> {
    guard CGPreflightListenEventAccess() else {
      throw GlobalHotKeyError.inputMonitoringPermissionMissing
    }
    stopCurrentRunner()

    var continuation: AsyncStream<HotKeyEvent>.Continuation?
    let stream = AsyncStream<HotKeyEvent>(bufferingPolicy: .bufferingNewest(32)) {
      continuation = $0
    }
    guard let continuation else {
      throw GlobalHotKeyError.eventTapCreationFailed
    }

    let runner = EventTapRunner(binding: binding) { event in
      continuation.yield(event)
    }
    try runner.start()
    self.runner = runner
    self.continuation = continuation
    return stream
  }

  func stop() async {
    stopCurrentRunner()
  }

  private func stopCurrentRunner() {
    runner?.stop()
    runner = nil
    continuation?.finish()
    continuation = nil
  }
}

private final class EventTapRunner: @unchecked Sendable {
  private let binding: WakeBinding
  private let emit: @Sendable (HotKeyEvent) -> Void
  private let lock = NSLock()
  private let startupSemaphore = DispatchSemaphore(value: 0)

  private var startupError: GlobalHotKeyError?
  private var runLoop: CFRunLoop?
  private var tap: CFMachPort?
  private var bindingIsPressed = false

  init(binding: WakeBinding, emit: @escaping @Sendable (HotKeyEvent) -> Void) {
    self.binding = binding
    self.emit = emit
  }

  func start() throws {
    let thread = Thread { [weak self] in
      self?.runEventTap()
    }
    thread.name = "SwiftWhisper.GlobalHotKey"
    thread.qualityOfService = .userInteractive
    thread.start()

    guard startupSemaphore.wait(timeout: .now() + 2) == .success else {
      throw GlobalHotKeyError.eventTapStartupTimedOut
    }
    if let startupError {
      throw startupError
    }
  }

  func stop() {
    lock.lock()
    let runLoop = self.runLoop
    let tap = self.tap
    self.runLoop = nil
    self.tap = nil
    bindingIsPressed = false
    lock.unlock()

    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
  }

  private func runEventTap() {
    let eventMask = mask(for: [
      .flagsChanged,
      .keyDown,
      .keyUp,
    ])
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      startupError = .eventTapCreationFailed
      startupSemaphore.signal()
      return
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    let runLoop = CFRunLoopGetCurrent()

    lock.lock()
    self.tap = tap
    self.runLoop = runLoop
    lock.unlock()

    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    startupSemaphore.signal()
    CFRunLoopRun()

    CFRunLoopRemoveSource(runLoop, source, .commonModes)
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      bindingIsPressed = false
      emit(.tapDisabled)
      emit(.physicalStateInvalidated)
      lock.lock()
      let tap = self.tap
      lock.unlock()
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyDown,
      keyCode == CGKeyCode(kVK_Escape),
      event.getIntegerValueField(.keyboardEventAutorepeat) == 0
    {
      emit(.cancelRequested)
      return
    }

    switch binding {
    case .modifierOnly(let modifier):
      guard type == .flagsChanged,
        keyCode == Self.keyCode(for: modifier)
      else { return }
      let isPressed = Self.isPressed(modifier, in: event.flags)
      emitTransition(isPressed: isPressed)

    case .chord(let configuredKeyCode, let modifiers):
      if type == .flagsChanged, bindingIsPressed {
        let stillHeld = Self.modifierMask(from: event.flags).isSuperset(of: modifiers)
        if !stillHeld { emitTransition(isPressed: false) }
        return
      }
      guard keyCode == CGKeyCode(configuredKeyCode) else { return }
      if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        guard Self.modifierMask(from: event.flags).isSuperset(of: modifiers) else { return }
        emitTransition(isPressed: true)
      } else if type == .keyUp {
        emitTransition(isPressed: false)
      }
    }

  }

  private func emitTransition(isPressed: Bool) {
    guard isPressed != bindingIsPressed else { return }
    bindingIsPressed = isPressed
    let now = ContinuousClock().now
    emit(isPressed ? .pressed(monotonicTime: now) : .released(monotonicTime: now))
  }

  private static func keyCode(for key: PhysicalModifierKey) -> CGKeyCode {
    switch key {
    case .rightOption: CGKeyCode(kVK_RightOption)
    case .leftOption: CGKeyCode(kVK_Option)
    case .function: CGKeyCode(kVK_Function)
    case .rightShift: CGKeyCode(kVK_RightShift)
    case .leftShift: CGKeyCode(kVK_Shift)
    case .rightCommand: CGKeyCode(kVK_RightCommand)
    case .leftCommand: CGKeyCode(kVK_Command)
    case .rightControl: CGKeyCode(kVK_RightControl)
    case .leftControl: CGKeyCode(kVK_Control)
    }
  }

  private static func isPressed(
    _ key: PhysicalModifierKey,
    in flags: CGEventFlags
  ) -> Bool {
    // Device-dependent modifier bits preserve left/right identity. These
    // values are defined by IOLLEvent.h and are included in CGEvent flags.
    let deviceMask: UInt64
    switch key {
    case .leftControl: deviceMask = 0x0000_0001
    case .leftShift: deviceMask = 0x0000_0002
    case .rightShift: deviceMask = 0x0000_0004
    case .leftCommand: deviceMask = 0x0000_0008
    case .rightCommand: deviceMask = 0x0000_0010
    case .leftOption: deviceMask = 0x0000_0020
    case .rightOption: deviceMask = 0x0000_0040
    case .rightControl: deviceMask = 0x0000_2000
    case .function:
      return flags.contains(.maskSecondaryFn)
    }
    return flags.rawValue & deviceMask != 0
  }

  private static func modifierMask(from flags: CGEventFlags) -> ModifierMask {
    var result: ModifierMask = []
    if flags.contains(.maskCommand) { result.insert(.command) }
    if flags.contains(.maskAlternate) { result.insert(.option) }
    if flags.contains(.maskControl) { result.insert(.control) }
    if flags.contains(.maskShift) { result.insert(.shift) }
    if flags.contains(.maskSecondaryFn) { result.insert(.function) }
    return result
  }

  private func mask(for types: [CGEventType]) -> CGEventMask {
    types.reduce(CGEventMask(0)) { partial, type in
      partial | (CGEventMask(1) << CGEventMask(type.rawValue))
    }
  }
}

private func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let runner = Unmanaged<EventTapRunner>.fromOpaque(userInfo).takeUnretainedValue()
  runner.handle(type: type, event: event)
  return Unmanaged.passUnretained(event)
}

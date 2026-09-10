import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchOverlayController {
  private enum Layout {
    static let canvasSize = NSSize(width: 320, height: 82)
    static let hideAnimationDuration: Duration = .milliseconds(240)
  }

  private let model = OverlayModel()
  private let panel: NSPanel
  private var cancellables: Set<AnyCancellable> = []
  private var hideTask: Task<Void, Never>?

  init() {
    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: Layout.canvasSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(rootView: NotchOverlayView(model: model))
  }

  func bind(to controller: DictationController) {
    controller.$displayState
      .combineLatest(controller.$audioLevel, controller.$permissionSnapshot)
      .sink { [weak self] state, level, permissions in
        self?.update(state: state, level: level, permissions: permissions)
      }
      .store(in: &cancellables)
  }

  private func update(
    state: DictationController.DisplayState,
    level: Float,
    permissions: PermissionSnapshot?
  ) {
    model.state = state
    model.level = level
    model.needsPermissionAttention = permissions.map { !$0.hasRequiredPermissions } ?? false
    panel.ignoresMouseEvents = !model.needsPermissionAttention

    guard state.keepsOverlayVisible || model.needsPermissionAttention else {
      dismiss()
      return
    }

    hideTask?.cancel()
    hideTask = nil
    configureForCurrentScreen()
    panel.orderFrontRegardless()

    guard !model.isPresented else { return }
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.model.isPresented = true
    }
  }

  private func dismiss() {
    guard model.isPresented else {
      panel.orderOut(nil)
      return
    }

    model.isPresented = false
    hideTask?.cancel()
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Layout.hideAnimationDuration)
      guard !Task.isCancelled else { return }
      self?.panel.orderOut(nil)
    }
  }

  private func configureForCurrentScreen() {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
      ?? NSScreen.main
    guard let screen else { return }

    let notch = notchGeometry(for: screen)
    model.hasPhysicalNotch = notch != nil
    if let notch {
      model.notchWidth = notch.width
      model.notchDepth = notch.depth
    }

    let x = screen.frame.midX - Layout.canvasSize.width / 2
    let y =
      model.hasPhysicalNotch
      ? screen.frame.maxY - Layout.canvasSize.height
      : screen.visibleFrame.maxY - Layout.canvasSize.height - 8
    panel.setFrame(
      NSRect(origin: NSPoint(x: x, y: y), size: Layout.canvasSize),
      display: true
    )
  }

  private func notchGeometry(for screen: NSScreen) -> (width: CGFloat, depth: CGFloat)? {
    guard screen.safeAreaInsets.top > 0,
      let leftArea = screen.auxiliaryTopLeftArea,
      let rightArea = screen.auxiliaryTopRightArea
    else { return nil }

    let width = rightArea.minX - leftArea.maxX
    guard width > 0 else { return nil }
    return (
      width: min(max(width, 120), 220),
      depth: min(max(screen.safeAreaInsets.top, 24), 44)
    )
  }
}

@MainActor
private final class OverlayModel: ObservableObject {
  @Published var state: DictationController.DisplayState = .idle
  @Published var level: Float = 0
  @Published var isPresented = false
  @Published var hasPhysicalNotch = false
  @Published var notchWidth: CGFloat = 160
  @Published var notchDepth: CGFloat = 32
  @Published var needsPermissionAttention = false
}

private struct NotchOverlayView: View {
  private static let expandedWidth: CGFloat = 284

  @ObservedObject var model: OverlayModel
  @AppStorage(NotchAnimationStyle.storageKey) private var animationStyleRawValue =
    NotchAnimationStyle.defaultStyle.rawValue
  @AppStorage(SettingsPage.storageKey) private var settingsPageRawValue =
    SettingsPage.control.rawValue
  private let shapeStyle = NotchShapeStyle.defaultStyle

  @ViewBuilder
  var body: some View {
    if model.needsPermissionAttention {
      SettingsLink {
        notchContent
      }
      .buttonStyle(.plain)
      .simultaneousGesture(
        TapGesture().onEnded {
          settingsPageRawValue = SettingsPage.permission.rawValue
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
      )
    } else {
      notchContent
    }
  }

  private var notchContent: some View {
    Group {
      if model.hasPhysicalNotch { integratedIsland } else { fallbackCapsule }
    }
    .frame(width: 320, height: 82, alignment: .top)
  }

  private var integratedIsland: some View {
    let width = model.isPresented ? Self.expandedWidth : model.notchWidth
    let height = model.isPresented ? 68.0 : model.notchDepth

    return ZStack(alignment: .top) {
      NotchContainerShape(style: shapeStyle, attachedToTop: true)
      .fill(.black)
      .frame(width: width, height: height)
      .shadow(color: .black.opacity(0.28), radius: 8, y: 4)

      HStack(spacing: 10) {
        statusIndicator
        Text(statusLabel)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(.white)
      .padding(.bottom, 9)
      .frame(width: Self.expandedWidth, height: 68, alignment: .bottom)
      .opacity(model.isPresented ? 1 : 0)
      .offset(y: model.isPresented ? 0 : -5)
    }
    .frame(width: width, height: height, alignment: .top)
    .contentShape(NotchContainerShape(style: shapeStyle, attachedToTop: true))
    .frame(width: 320, height: 82, alignment: .top)
    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.isPresented)
    .animation(.snappy(duration: 0.2), value: model.state)
  }

  private var fallbackCapsule: some View {
    HStack(spacing: 10) {
      statusIndicator
      Text(statusLabel)
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .frame(width: 232, height: 44)
    .background(
      .black.opacity(0.94),
      in: NotchContainerShape(style: shapeStyle, attachedToTop: false)
    )
    .contentShape(NotchContainerShape(style: shapeStyle, attachedToTop: false))
    .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    .scaleEffect(model.isPresented ? 1 : 0.88, anchor: .top)
    .opacity(model.isPresented ? 1 : 0)
    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.isPresented)
    .animation(.snappy(duration: 0.2), value: model.state)
  }

  private var animationStyle: NotchAnimationStyle {
    NotchAnimationStyle(rawValue: animationStyleRawValue) ?? .defaultStyle
  }

  private var statusLabel: String {
    model.needsPermissionAttention ? "Permissions Needed" : model.state.label
  }

  @ViewBuilder
  private var statusIndicator: some View {
    if model.needsPermissionAttention {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } else {
      NotchAnimationIndicator(style: animationStyle, level: model.level)
    }
  }

}

private struct NotchContainerShape: Shape {
  let style: NotchShapeStyle
  let attachedToTop: Bool

  func path(in rect: CGRect) -> Path {
    switch style {
    case .rectangle:
      if attachedToTop {
        return UnevenRoundedRectangle(
          cornerRadii: RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: 19,
            bottomTrailing: 19,
            topTrailing: 0
          ),
          style: .continuous
        ).path(in: rect)
      }
      return RoundedRectangle(cornerRadius: 15, style: .continuous).path(in: rect)

    case .halfCircle:
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
      path.addCurve(
        to: CGPoint(x: rect.midX, y: rect.maxY),
        control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.72),
        control2: CGPoint(x: rect.midX + rect.width * 0.24, y: rect.maxY)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2),
        control1: CGPoint(x: rect.midX - rect.width * 0.24, y: rect.maxY),
        control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.72)
      )
      path.closeSubpath()
      return path

    case .splash:
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))

      // A broad horizontal finger on the right.
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.87, y: rect.minY + rect.height * 0.34),
        control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28),
        control2: CGPoint(x: rect.minX + rect.width * 0.91, y: rect.minY + rect.height * 0.34)
      )
      path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.53),
        control1: CGPoint(x: rect.minX + rect.width * 0.93, y: rect.minY + rect.height * 0.34),
        control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.43)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.63),
        control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.63),
        control2: CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY + rect.height * 0.63)
      )

      // A diagonal lower-right lobe.
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.86),
        control1: CGPoint(x: rect.minX + rect.width * 0.79, y: rect.minY + rect.height * 0.63),
        control2: CGPoint(x: rect.minX + rect.width * 0.79, y: rect.minY + rect.height * 0.86)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + rect.height * 0.7),
        control1: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.86),
        control2: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.7)
      )

      // The deepest lower-right finger.
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.57, y: rect.maxY),
        control1: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.7),
        control2: CGPoint(x: rect.minX + rect.width * 0.61, y: rect.maxY)
      )
      path.addCurve(
        to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.75),
        control1: CGPoint(x: rect.minX + rect.width * 0.53, y: rect.maxY),
        control2: CGPoint(x: rect.minX + rect.width * 0.53, y: rect.minY + rect.height * 0.75)
      )

      // A slightly shorter lower-left finger keeps the splash organic.
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.95),
        control1: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.75),
        control2: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.95)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.69),
        control1: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.95),
        control2: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.69)
      )

      // A diagonal lower-left lobe.
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.83),
        control1: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.minY + rect.height * 0.69),
        control2: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.minY + rect.height * 0.83)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.62),
        control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.83),
        control2: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.62)
      )

      // The left horizontal finger mirrors the impact without perfect symmetry.
      path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.56),
        control1: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.62),
        control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.66)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.33),
        control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.43),
        control2: CGPoint(x: rect.minX + rect.width * 0.07, y: rect.minY + rect.height * 0.33)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2),
        control1: CGPoint(x: rect.minX + rect.width * 0.09, y: rect.minY + rect.height * 0.33),
        control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28)
      )
      path.closeSubpath()
      return path
    }
  }
}

private struct NotchAnimationIndicator: View {
  let style: NotchAnimationStyle
  let level: Float

  var body: some View {
    Group {
      switch style {
      case .voiceWave:
        VoiceWaveView(level: level)
      case .particleOrbit:
        SignalCoreView(level: level)
      case .auroraPulse:
        AuroraPulseView(level: level)
      }
    }
    .frame(width: 38, height: 26)
    .transition(.blurReplace)
  }
}

private struct VoiceWaveView: View {
  let level: Float

  private let weights: [CGFloat] = [0.38, 0.7, 1, 0.68, 0.92, 0.58, 0.34]

  var body: some View {
    HStack(spacing: 2.2) {
      ForEach(weights.indices, id: \.self) { index in
        Capsule()
          .fill(
            LinearGradient(
              colors: [.cyan, .blue.opacity(0.9)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(
            width: 2.4,
            height: 4 + weights[index] * (5 + CGFloat(level) * 17)
          )
      }
    }
    .frame(width: 38, height: 26)
    .animation(.linear(duration: 0.08), value: level)
  }
}

private struct SignalCoreView: View {
  let level: Float
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
      let intensity = CGFloat(level)
      let voice = Double(level)
      let pulse = CGFloat((sin(time * 2.1) + 1) / 2)
      let sphereSize: CGFloat = 18.5 + intensity * 3.5
      let driftX = CGFloat(sin(time * 0.82)) * 2.1
      let driftY = CGFloat(cos(time * 0.67)) * 1.6

      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [
                .cyan.opacity(0.22 + voice * 0.15),
                .blue.opacity(0.3 + voice * 0.2),
                .purple.opacity(0.22 + voice * 0.16),
                .clear,
              ],
              center: .center,
              startRadius: 1,
              endRadius: 18
            )
          )
          .frame(width: sphereSize + 18, height: sphereSize + 18)
          .blur(radius: 6.5)
          .scaleEffect(0.98 + intensity * 0.15 + pulse * 0.05)

        Circle()
          .fill(.purple.opacity(0.12 + voice * 0.1))
          .frame(width: sphereSize + 7, height: sphereSize + 7)
          .blur(radius: 4.2)
          .offset(x: driftX * 0.6, y: driftY * 0.6)

        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  Color(red: 0.34, green: 0.82, blue: 1),
                  Color(red: 0.12, green: 0.36, blue: 0.96),
                  Color(red: 0.2, green: 0.08, blue: 0.54),
                  Color(red: 0.035, green: 0.025, blue: 0.12),
                ],
                center: UnitPoint(x: 0.3, y: 0.22),
                startRadius: 0,
                endRadius: sphereSize * 0.68
              )
            )

          Circle()
            .fill(.cyan.opacity(0.32 + voice * 0.24))
            .frame(width: sphereSize * 0.6, height: sphereSize * 0.6)
            .blur(radius: 4.2)
            .offset(x: -sphereSize * 0.18 + driftX, y: -sphereSize * 0.08 + driftY)

          Circle()
            .fill(.purple.opacity(0.56 + voice * 0.2))
            .frame(width: sphereSize * 0.72, height: sphereSize * 0.72)
            .blur(radius: 4.8)
            .offset(x: sphereSize * 0.22 - driftX, y: sphereSize * 0.2 - driftY)

          Ellipse()
            .stroke(
              LinearGradient(
                colors: [.clear, .cyan.opacity(0.75), .white.opacity(0.55), .purple.opacity(0.65), .clear],
                startPoint: .leading,
                endPoint: .trailing
              ),
              style: StrokeStyle(lineWidth: 0.65, lineCap: .round)
            )
            .frame(width: sphereSize * 0.92, height: sphereSize * 0.3)
            .rotationEffect(.degrees(sin(time * 0.55) * 8 - 7))
            .blur(radius: 1.2)
            .opacity(0.24 + voice * 0.24)
        }
        .frame(width: sphereSize, height: sphereSize)
        .clipShape(Circle())
        .saturation(1.12 + voice * 0.22)
        .blur(radius: 1.15 + intensity * 0.35)

        Circle()
          .stroke(
            LinearGradient(
              colors: [.white.opacity(0.38), .cyan.opacity(0.22), .blue.opacity(0.1), .purple.opacity(0.3)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.8
          )
          .frame(width: sphereSize, height: sphereSize)
          .blur(radius: 0.9)

        Ellipse()
          .fill(.white.opacity(0.38 + voice * 0.12))
          .frame(width: sphereSize * 0.28, height: sphereSize * 0.12)
          .blur(radius: 1.2)
          .offset(x: -sphereSize * 0.18, y: -sphereSize * 0.25)
      }
      .scaleEffect(0.97 + intensity * 0.06)
    }
    .frame(width: 38, height: 26)
  }
}

private struct AuroraPulseView: View {
  let level: Float
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
      let intensity = CGFloat(level)

      ZStack {
        auroraOrb(
          colors: [.cyan, .blue],
          size: 17 + intensity * 7,
          x: sin(time * 1.7) * 8 - 7,
          y: cos(time * 1.2) * 3
        )
        auroraOrb(
          colors: [.purple, .pink],
          size: 15 + intensity * 9,
          x: cos(time * 1.35) * 9 + 7,
          y: sin(time * 1.8) * 4
        )
        auroraOrb(
          colors: [.mint, .cyan],
          size: 11 + intensity * 6,
          x: sin(time * 2.1) * 5,
          y: cos(time * 1.55) * 5
        )
      }
      .blur(radius: 1.6)
      .saturation(1.25)
      .scaleEffect(0.92 + intensity * 0.12)
    }
    .frame(width: 34, height: 20)
    .background {
      Capsule()
        .fill(.indigo.opacity(0.12 + Double(level) * 0.1))
        .blur(radius: 5)
        .scaleEffect(x: 1.25, y: 1.15)
    }
    .shadow(color: .cyan.opacity(0.18 + Double(level) * 0.2), radius: 6)
  }

  private func auroraOrb(
    colors: [Color],
    size: CGFloat,
    x: Double,
    y: Double
  ) -> some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [colors[0], colors[1].opacity(0.1)],
          center: .center,
          startRadius: 0,
          endRadius: size / 2
        )
      )
      .frame(width: size, height: size)
      .offset(x: x, y: y)
      .blendMode(.plusLighter)
  }
}

import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchOverlayController {
    private let model = OverlayModel()
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NotchCapsuleView(model: model))
    }

    func bind(to controller: PrototypeDictationController) {
        controller.$displayState
            .combineLatest(controller.$partialText, controller.$audioLevel)
            .sink { [weak self] state, partialText, level in
                self?.update(state: state, partialText: partialText, level: level)
            }
            .store(in: &cancellables)
    }

    func update(
        state: PrototypeDictationController.DisplayState,
        partialText: String,
        level: Float
    ) {
        model.state = state
        model.partialText = partialText
        model.level = level

        guard state.keepsOverlayVisible else {
            panel.orderOut(nil)
            return
        }
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }

        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var state: PrototypeDictationController.DisplayState = .idle
    @Published var partialText = ""
    @Published var level: Float = 0
}

private struct NotchCapsuleView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            levelBars
            VStack(alignment: .leading, spacing: 1) {
                Text(model.state.label)
                    .font(.system(size: 12, weight: .semibold))
                if !model.partialText.isEmpty {
                    Text(model.partialText)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(width: 232, height: 44)
        .background(.black.opacity(0.92), in: Capsule())
        .animation(.snappy(duration: 0.2), value: model.state)
    }

    private var levelBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.cyan)
                    .frame(width: 2, height: max(5, CGFloat(model.level) * CGFloat(10 + index * 5)))
            }
        }
        .frame(width: 18, height: 24)
    }
}

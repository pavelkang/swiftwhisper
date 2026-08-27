import AppKit
import SwiftUI

@main
struct SwiftWhisperApp: App {
    @StateObject private var controller: PrototypeDictationController
    private let overlay: NotchOverlayController

    init() {
        let controller = PrototypeDictationController()
        let overlay = NotchOverlayController()
        _controller = StateObject(wrappedValue: controller)
        self.overlay = overlay
        overlay.bind(to: controller)
        controller.startMonitoring()
    }

    var body: some Scene {
        MenuBarExtra("SwiftWhisper", systemImage: "waveform") {
            Button(controller.displayState == .listening ? "Stop Dictation" : "Start Dictation…") {
                controller.toggleManualDictation()
            }
            .keyboardShortcut("d")

            Button("Request Permissions…") {
                controller.requestPermissions()
            }

            Divider()
            Text(controller.permissionSummary)
                .font(.caption)

            if let latest = controller.history.first {
                Divider()
                Text("Latest")
                    .font(.caption)
                Text(latest)
                    .lineLimit(3)
                Button("Copy Latest") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(latest, forType: .string)
                }
            }

            Divider()
            Button("Quit SwiftWhisper") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)

        Window("SwiftWhisper History", id: "history") {
            HistoryPrototypeView(history: controller.history)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 680, height: 480)

        Settings {
            Form {
                LabeledContent("Wake key", value: "Right Option")
                LabeledContent("Model", value: "Apple Dictation")
                LabeledContent("Permissions", value: controller.permissionSummary)
            }
            .padding(24)
            .frame(width: 460)
        }
    }
}

private struct HistoryPrototypeView: View {
    let history: [String]

    var body: some View {
        NavigationSplitView {
            List(Array(history.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .lineLimit(2)
            }
            .navigationTitle("History")
        } detail: {
            if let first = history.first {
                ScrollView {
                    Text(first)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Hold Right Option to dictate.")
                )
            }
        }
    }
}

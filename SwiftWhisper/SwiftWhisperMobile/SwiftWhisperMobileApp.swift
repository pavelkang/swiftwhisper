import SwiftUI
import UIKit

@main
struct SwiftWhisperMobileApp: App {
  @StateObject private var controller = MobileDictationController()
  @StateObject private var history = DictationHistoryStore.shared

  var body: some Scene {
    WindowGroup {
      RootView(controller: controller, history: history)
    }
  }
}

private struct RootView: View {
  @ObservedObject var controller: MobileDictationController
  @ObservedObject var history: DictationHistoryStore

  var body: some View {
    TabView {
      DictateView(controller: controller)
        .tabItem { Label("Dictate", systemImage: "waveform") }

      NavigationStack {
        HistoryView(history: history)
      }
      .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

      NavigationStack {
        MobileSettingsView(controller: controller, history: history)
      }
      .tabItem { Label("Settings", systemImage: "gearshape") }
    }
    .tint(.cyan)
  }
}

private struct DictateView: View {
  @ObservedObject var controller: MobileDictationController
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      VStack(spacing: 28) {
        Spacer()

        VStack(spacing: 10) {
          Image(systemName: controller.state.symbol)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(controller.state.isError ? .red : .cyan)
            .symbolEffect(.pulse, isActive: controller.state.isBusy)
          Text(controller.state.title)
            .font(.title2.weight(.semibold))
          Text(controller.state.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        if let transcript = controller.transcript, !transcript.isEmpty {
          ScrollView {
            Text(transcript)
              .font(.body)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(18)
          }
          .frame(maxHeight: 220)
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
          .overlay(alignment: .topTrailing) {
            HStack {
              Button {
                UIPasteboard.general.string = transcript
              } label: {
                Image(systemName: "doc.on.doc")
              }
              ShareLink(item: transcript) {
                Image(systemName: "square.and.arrow.up")
              }
            }
            .buttonStyle(.bordered)
            .padding(10)
          }
          .padding(.horizontal)
        }

        Button {
          controller.toggleDictation()
        } label: {
          ZStack {
            Circle()
              .fill(controller.state.isRecording ? Color.red : Color.cyan)
              .frame(width: 92, height: 92)
              .shadow(color: (controller.state.isRecording ? Color.red : .cyan).opacity(0.25), radius: 18)
            Image(systemName: controller.state.isRecording ? "stop.fill" : "mic.fill")
              .font(.system(size: 32, weight: .bold))
              .foregroundStyle(.white)
          }
        }
        .accessibilityLabel(controller.state.isRecording ? "Stop dictation" : "Start dictation")
        .disabled(controller.state.isBusy && !controller.state.isRecording)

        Text(controller.state.isRecording ? "Tap to stop" : "Tap to dictate")
          .font(.callout)
          .foregroundStyle(.secondary)

        Spacer()
      }
      .padding()
      .navigationTitle("SwiftWhisper")
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { controller.cancel() }
      }
    }
  }
}

private struct HistoryView: View {
  @ObservedObject var history: DictationHistoryStore
  @State private var searchText = ""

  private var filteredEntries: [DictationHistoryEntry] {
    guard !searchText.isEmpty else { return history.entries }
    return history.entries.filter {
      $0.displayTranscript.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    Group {
      if filteredEntries.isEmpty {
        ContentUnavailableView(
          searchText.isEmpty ? "No Dictations Yet" : "No Results",
          systemImage: "waveform.badge.magnifyingglass",
          description: Text(searchText.isEmpty ? "New dictations will appear here and sync with your Mac." : "Try another search.")
        )
      } else {
        List {
          ForEach(filteredEntries) { entry in
            VStack(alignment: .leading, spacing: 8) {
              Text(entry.displayTranscript)
                .lineLimit(4)
              HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Button {
                  history.play(entry)
                } label: {
                  Image(systemName: history.playingEntryID == entry.id ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                ShareLink(item: entry.displayTranscript) {
                  Image(systemName: "square.and.arrow.up")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .swipeActions {
              Button("Delete", role: .destructive) { history.delete(entry) }
              Button("Copy") { UIPasteboard.general.string = entry.displayTranscript }
                .tint(.cyan)
            }
          }
        }
      }
    }
    .navigationTitle("History")
    .searchable(text: $searchText, prompt: "Search dictations")
    .refreshable { history.refresh() }
  }
}

private struct MobileSettingsView: View {
  @ObservedObject var controller: MobileDictationController
  @ObservedObject var history: DictationHistoryStore
  @StateObject private var polishModelManager = PolishModelManager.shared
  @AppStorage(TranscriptionLanguage.storageKey) private var language =
    TranscriptionLanguage.defaultLanguage.rawValue
  @AppStorage(DictationHistorySetting.storageKey) private var historyEnabled =
    DictationHistorySetting.defaultEnabled
  @AppStorage(SmartPolishSetting.storageKey) private var smartPolishEnabled =
    SmartPolishSetting.defaultEnabled
  @AppStorage(SmartPolishModel.storageKey) private var smartPolishModel =
    SmartPolishModel.defaultModel.rawValue

  var body: some View {
    Form {
      Section("Transcription") {
        Picker("Language", selection: $language) {
          ForEach(TranscriptionLanguage.allCases) { item in
            Text(item.title).tag(item.rawValue)
          }
        }
        LabeledContent("Speech model", value: "Apple Dictation")
      }

      Section("Smart Polish") {
        Toggle("Polish final transcripts", isOn: $smartPolishEnabled)
        if smartPolishEnabled {
          Picker("Model", selection: $smartPolishModel) {
            ForEach(SmartPolishModel.allCases) { model in
              Text(model.title).tag(model.rawValue)
            }
          }
          if smartPolishModel == SmartPolishModel.qwen3Compact.rawValue {
            qwenDownloadRow
          }
          Text("Polishing runs locally and is rejected if it changes any spoken word or number.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("History") {
        Toggle("Save recordings and transcripts", isOn: $historyEnabled)
        LabeledContent("Sync", value: history.isUsingICloud ? "iCloud" : "This iPhone")
        Text(history.isUsingICloud
          ? "History is stored in your private iCloud container and shared with SwiftWhisper on your Mac."
          : "Sign in to iCloud and enable iCloud Drive to sync history with your Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Permissions") {
        Button("Request Microphone and Speech Access") {
          Task { await controller.requestPermissions() }
        }
      }

      Section("Privacy") {
        Text("Transcription runs on device. Audio and transcripts are only saved when History is enabled.")
      }
    }
    .navigationTitle("Settings")
    .onChange(of: smartPolishEnabled) { _, _ in
      Task { await controller.preparePolish() }
    }
    .onChange(of: smartPolishModel) { _, _ in
      Task { await controller.preparePolish() }
    }
  }

  @ViewBuilder
  private var qwenDownloadRow: some View {
    switch polishModelManager.state {
    case .notDownloaded:
      Button("Download Qwen3 0.6B · About 350 MB") {
        polishModelManager.download()
      }
    case .downloading(let progress):
      HStack {
        if let progress {
          ProgressView(value: progress)
          Text(progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
        } else {
          ProgressView()
        }
        Button("Cancel") { polishModelManager.cancelDownload() }
      }
    case .installed:
      HStack {
        Label("Qwen3 is ready", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Spacer()
        Button("Remove", role: .destructive) { try? polishModelManager.remove() }
      }
    case .failed(let message):
      VStack(alignment: .leading) {
        Text(message).font(.caption).foregroundStyle(.red)
        Button("Retry") { polishModelManager.download() }
      }
    }
  }
}

private extension MobileDictationController.State {
  var title: String {
    switch self {
    case .idle: "Ready to Dictate"
    case .preparing: "Getting Ready"
    case .recording: "Listening"
    case .processing: "Transcribing"
    case .complete: "Dictation Ready"
    case .error: "Couldn’t Dictate"
    }
  }

  var detail: String {
    switch self {
    case .idle: "Your voice is transcribed on this device."
    case .preparing: "Preparing the offline speech model…"
    case .recording: "Speak naturally, then tap Stop."
    case .processing: "Finishing your transcript…"
    case .complete: "Copy, share, or find it later in History."
    case .error(let message): message
    }
  }

  var symbol: String {
    switch self {
    case .idle, .complete: "waveform"
    case .preparing, .processing: "ellipsis"
    case .recording: "waveform.circle.fill"
    case .error: "exclamationmark.triangle.fill"
    }
  }

  var isRecording: Bool { self == .recording }
  var isBusy: Bool { self == .preparing || self == .processing }
  var isError: Bool { if case .error = self { true } else { false } }
}

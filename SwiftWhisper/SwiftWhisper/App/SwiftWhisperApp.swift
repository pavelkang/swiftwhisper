import AppKit
import SwiftUI

@MainActor
private final class AppRuntime {
  static let shared = AppRuntime()

  let controller: DictationController
  private let overlay: NotchOverlayController

  private init() {
    let controller = DictationController()
    let overlay = NotchOverlayController()
    self.controller = controller
    self.overlay = overlay
    overlay.bind(to: controller)
    controller.startMonitoring()
  }
}

@main
struct SwiftWhisperApp: App {
  @NSApplicationDelegateAdaptor(DiagnosticsAppDelegate.self) private var appDelegate
  @StateObject private var controller: DictationController

  init() {
    _controller = StateObject(wrappedValue: AppRuntime.shared.controller)
  }

  var body: some Scene {
    MenuBarExtra {
      StatusMenu(controller: controller)
    } label: {
      AppMenuLabel()
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(controller: controller)
    }
    .defaultPosition(.center)
  }
}

private struct AppMenuLabel: View {
  @Environment(\.openSettings) private var openSettings
  @AppStorage("hasOpenedSettings") private var hasOpenedSettings = false

  var body: some View {
    Image(systemName: "waveform")
      .accessibilityLabel("SwiftWhisper")
      .task {
        guard !hasOpenedSettings || ProcessInfo.processInfo.arguments.contains("--show-settings") else { return }
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
        hasOpenedSettings = true
      }
  }
}

private struct StatusMenu: View {
  @ObservedObject var controller: DictationController
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button {
      openSettings()
      NSApplication.shared.activate(ignoringOtherApps: true)
    } label: {
      Label("Settings", systemImage: "gearshape")
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button {
      if let latest = controller.lastTranscript {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latest, forType: .string)
      }
    } label: {
      Label("Copy Last", systemImage: "doc.on.doc")
    }
    .keyboardShortcut("v", modifiers: [.control, .command])
    .disabled(controller.lastTranscript == nil)

    Divider()

    Button {
      NSApplication.shared.terminate(nil)
    } label: {
      Label("Quit", systemImage: "power")
    }
    .keyboardShortcut("q")
  }
}

private struct SettingsView: View {
  @StateObject private var diagnostics = DiagnosticsSupport()
  @State private var showDiagnostics = false
  @State private var operationError: String?
  @ObservedObject var controller: DictationController
  @StateObject private var modelManager = SpeechModelManager.shared
  @StateObject private var audioDeviceManager = AudioInputDeviceManager.shared
  @StateObject private var vocabulary = VocabularyStore.shared
  @StateObject private var history = DictationHistoryStore.shared
  @StateObject private var polishModelManager = PolishModelManager.shared
  @AppStorage(SettingsPage.storageKey) private var selectionRawValue =
    SettingsPage.control.rawValue
  @State private var vocabularyInput = ""
  @State private var showClearHistoryConfirmation = false
  @State private var correctionEntry: DictationHistoryEntry?
  @AppStorage(DictationActivationMode.storageKey) private var activationModeRawValue =
    DictationActivationMode.defaultMode.rawValue
  @AppStorage(NotchAnimationStyle.storageKey) private var animationStyleRawValue =
    NotchAnimationStyle.defaultStyle.rawValue
  @AppStorage(TranscriptionLanguage.storageKey) private var transcriptionLanguageRawValue =
    TranscriptionLanguage.defaultLanguage.rawValue
  @AppStorage(SpeechModel.storageKey) private var speechModelRawValue =
    SpeechModel.defaultModel.rawValue
  @AppStorage(SmartPolishSetting.storageKey) private var smartPolishEnabled =
    SmartPolishSetting.defaultEnabled
  @AppStorage(SmartPolishModel.storageKey) private var smartPolishModelRawValue =
    SmartPolishModel.defaultModel.rawValue
  @AppStorage(AudioInputSelection.storageKey) private var audioInputDeviceID =
    AudioInputSelection.systemDefaultID
  @AppStorage(DictationHistorySetting.storageKey) private var historyEnabled =
    DictationHistorySetting.defaultEnabled

  var body: some View {
    HStack(spacing: 0) {
      sidebar

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          pageHeader
          selectedPage
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(28)
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(width: 780, height: 520)
    .alert("Couldn’t Complete Action", isPresented: Binding(
      get: { operationError != nil },
      set: { if !$0 { operationError = nil } }
    )) {
      Button("OK", role: .cancel) { operationError = nil }
    } message: {
      Text(operationError ?? "Please try again.")
    }
    .sheet(isPresented: $showDiagnostics) {
      DiagnosticsReportView(support: diagnostics)
    }
    .onChange(of: diagnostics.report) { _, report in
      if report != nil { showDiagnostics = true }
    }
    .confirmationDialog(
      "Clear all dictation history?",
      isPresented: $showClearHistoryConfirmation
    ) {
      Button("Clear History", role: .destructive) {
        history.clear()
      }
    } message: {
      Text("This permanently removes every saved recording and transcript.")
    }
    .sheet(item: $correctionEntry) { entry in
      DictationCorrectionSheet(entry: entry, history: history)
    }
    .task {
      await controller.refreshPermissions()
      audioDeviceManager.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      Task {
        await controller.refreshPermissions()
        await controller.prepareSmartPolish()
        audioDeviceManager.refresh()
      }
    }
    .onChange(of: transcriptionLanguageRawValue) { _, _ in
      Task { await controller.prepareSelectedLanguageAssets() }
    }
    .onChange(of: speechModelRawValue) { _, _ in
      Task { await controller.prepareSelectedLanguageAssets() }
    }
    .onChange(of: smartPolishEnabled) { _, _ in
      Task { await controller.prepareSmartPolish() }
    }
    .onChange(of: smartPolishModelRawValue) { _, _ in
      Task { await controller.prepareSmartPolish() }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image("AppLogo")
          .interpolation(.high)
          .frame(width: 32, height: 32)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          .accessibilityHidden(true)

        Text("SwiftWhisper")
          .font(.headline)
      }
      .padding(.horizontal, 16)
      .padding(.top, 18)
      .padding(.bottom, 20)

      VStack(spacing: 4) {
        ForEach(SettingsPage.allCases) { page in
          SettingsSidebarRow(
            page: page,
            isSelected: selection == page,
            needsAttention: page == .permission && needsPermissionAttention
          ) {
            selectionRawValue = page.rawValue
          }
        }
      }
      .padding(.horizontal, 10)

      Spacer()

      Text(
        selectedActivationMode == .holdToSpeak
          ? "Hold Right Option to dictate"
          : "Press Right Option to dictate"
      )
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(16)
    }
    .frame(width: 190)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
  }

  @ViewBuilder
  private var selectedPage: some View {
    switch selection {
    case .control:
      controlPage
    case .languageAndModels:
      languageAndModelsPage
    case .vocabulary:
      vocabularyPage
    case .history:
      historyPage
    case .appearance:
      appearancePage
    case .permission:
      permissionPage
    case .support:
      supportPage
    }
  }

  private var selection: SettingsPage {
    SettingsPage(rawValue: selectionRawValue) ?? .control
  }

  private var supportPage: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsSection(title: "SwiftWhisper Beta") {
        VStack(alignment: .leading, spacing: 8) {
          Text(DiagnosticsSupport.versionLabel)
          Text("Found a problem? Send a diagnostic report and describe what you were doing.")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      SettingsSection(title: "Diagnostics") {
        VStack(alignment: .leading, spacing: 12) {
          Text("Recent app events and error codes are stored locally for troubleshooting. Logs are limited to 1 MB and inactive files expire after 7 days.")
          Text("Reports exclude transcripts, recordings, vocabulary, and account details. Nothing is uploaded automatically.")
            .foregroundStyle(.secondary)
          HStack {
            Button {
              diagnostics.report = nil
              diagnostics.prepareReport(permissions: controller.permissionSnapshot)
            } label: {
              Label(diagnostics.isPreparing ? "Preparing…" : "Send Diagnostics…", systemImage: "envelope")
            }
            .buttonStyle(.borderedProminent)
            .disabled(diagnostics.isPreparing)
            Button("Show Log Folder") {
              NSWorkspace.shared.open(DiagnosticsLog.shared.directory)
            }
          }
          Text("You’ll review the report before opening an email draft. You can also save a copy.")
            .font(.caption).foregroundStyle(.secondary)
          if let email = DiagnosticsSupport.supportEmail {
            Text("Send to \(email)").font(.caption).foregroundStyle(.secondary)
          }
          if let message = diagnostics.message, !showDiagnostics {
            Text(message).font(.callout).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func removeSpeechModel(_ model: SpeechModel) {
    do { try modelManager.remove(model) }
    catch {
      DiagnosticsLog.shared.record("speech_model.remove_failed", error: error)
      operationError = "Couldn’t remove the speech model. Check your disk permissions and try again."
    }
  }

  private func removePolishModel() {
    do { try polishModelManager.remove() }
    catch {
      DiagnosticsLog.shared.record("polish_model.remove_failed", error: error)
      operationError = "Couldn’t remove the polish model. Check your disk permissions and try again."
    }
  }

  private var needsPermissionAttention: Bool {
    controller.permissionSnapshot.map { !$0.hasRequiredPermissions } ?? false
  }

  private var pageHeader: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(selection.title)
        .font(.title2.weight(.semibold))
      Text(selection.subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var controlPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsSection(title: "Push to talk") {
        SettingsValueRow(
          systemImage: "option",
          title: "Activation key",
          value: "Right Option"
        )
        Divider()
        HStack(spacing: 12) {
          Image(systemName: "hand.raised")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          Text("Activation mode")
          Spacer()
          Picker("Activation mode", selection: $activationModeRawValue) {
            ForEach(DictationActivationMode.allCases) { mode in
              Text(mode.title).tag(mode.rawValue)
            }
          }
          .labelsHidden()
          .frame(width: 190)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        Divider()
        SettingsValueRow(
          systemImage: "stop.circle",
          title: "Stop and insert",
          value: selectedActivationMode.stopAction
        )
        Divider()
        SettingsValueRow(
          systemImage: "xmark.circle",
          title: "Cancel dictation",
          value: "Escape"
        )
      }

      SettingsSection(title: "Microphone") {
        HStack(spacing: 12) {
          Image(systemName: "mic")
            .foregroundStyle(.secondary)
            .frame(width: 22)

          Text("Input device")

          Spacer()

          Picker("Input device", selection: $audioInputDeviceID) {
            Text("System Default — \(audioDeviceManager.defaultDeviceName)")
              .tag(AudioInputSelection.systemDefaultID)

            ForEach(audioDeviceManager.devices) { device in
              Text(device.name).tag(device.id)
            }

            if audioInputDeviceID != AudioInputSelection.systemDefaultID,
              !audioDeviceManager.devices.contains(where: { $0.id == audioInputDeviceID })
            {
              Text("Unavailable device").tag(audioInputDeviceID)
            }
          }
          .labelsHidden()
          .frame(width: 260)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
      }

      Text(controlInstructions)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var selectedActivationMode: DictationActivationMode {
    DictationActivationMode(rawValue: activationModeRawValue) ?? .defaultMode
  }

  private var controlInstructions: String {
    switch selectedActivationMode {
    case .holdToSpeak:
      "Hold Right Option from any app, speak naturally, then release it to insert the transcription. Press Escape to cancel."
    case .pressToToggle:
      "Press Right Option once to start listening. Press it again to stop and insert the transcription, or Escape to cancel."
    }
  }

  private var languageAndModelsPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsSection(title: "Language") {
        HStack(spacing: 12) {
          Image(systemName: "globe")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          Text("Transcription language")
          Spacer()
          Picker("Language", selection: $transcriptionLanguageRawValue) {
            ForEach(TranscriptionLanguage.allCases) { language in
              Text(language.title).tag(language.rawValue)
            }
          }
          .labelsHidden()
          .frame(width: 190)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
      }

      SettingsSection(title: "Model") {
        VStack(spacing: 0) {
          ForEach(Array(SpeechModel.allCases.enumerated()), id: \.element.id) { index, model in
            if index > 0 { Divider() }
            SpeechModelRow(
              model: model,
              state: modelManager.state(for: model),
              isSelected: speechModelRawValue == model.rawValue,
              use: { speechModelRawValue = model.rawValue },
              download: { modelManager.download(model) },
              cancelDownload: { modelManager.cancelDownload(model) },
              remove: { removeSpeechModel(model) }
            )
          }
        }
      }

      SettingsSection(title: "Smart Polish") {
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Image(systemName: "wand.and.sparkles")
              .foregroundStyle(.secondary)
              .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
              Text("Polish before inserting")
              Text("Adds punctuation, capitalization, and paragraph breaks on device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Smart Polish", isOn: $smartPolishEnabled)
              .labelsHidden()
          }
          .padding(.vertical, 7)
          .padding(.horizontal, 4)

          if smartPolishEnabled {
            Divider()
            HStack(spacing: 12) {
              Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 22)
              Text("Polish model")
              Spacer()
              Picker("Polish model", selection: $smartPolishModelRawValue) {
                ForEach(SmartPolishModel.allCases) { model in
                  Text(model.title).tag(model.rawValue)
                }
              }
              .labelsHidden()
              .frame(width: 190)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)

            if selectedSmartPolishModel == .qwen3Compact {
              Divider()
              QwenPolishModelRow(
                state: polishModelManager.state,
                download: { polishModelManager.download() },
                cancel: { polishModelManager.cancelDownload() },
                remove: removePolishModel
              )
            } else if let notice = smartPolishNotice {
              Divider()
              SmartPolishNoticeRow(notice: notice)
            }
          }
        }
      }

      Text("Speech recognition and Smart Polish run locally. Audio never leaves your Mac.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var smartPolishNotice: SmartPolishNotice? {
    switch controller.smartPolishAvailability {
    case .available:
      nil
    case .appleIntelligenceDisabled:
      SmartPolishNotice(
        title: "Turn on Apple Intelligence",
        detail: "Smart Polish is currently passing through the original transcript.",
        actionTitle: "Open System Settings",
        action: openAppleIntelligenceSettings
      )
    case .modelPreparing:
      SmartPolishNotice(
        title: "Apple Intelligence is preparing",
        detail: "Smart Polish will activate automatically when the system model is ready."
      )
    case .deviceNotEligible:
      SmartPolishNotice(
        title: "Apple Intelligence is unavailable",
        detail: "This Mac does not support Smart Polish. Original transcripts will be inserted."
      )
    case .modelNotDownloaded:
      SmartPolishNotice(
        title: "Download Qwen3 to use Smart Polish",
        detail: "Until it is installed, the original transcript will be inserted."
      )
    case .modelLoadFailed:
      SmartPolishNotice(
        title: "Qwen3 could not be loaded",
        detail: "The original transcript will be inserted. Remove and download the model again."
      )
    }
  }

  private var selectedSmartPolishModel: SmartPolishModel {
    SmartPolishModel(rawValue: smartPolishModelRawValue) ?? .defaultModel
  }

  private var vocabularyPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsSection(title: "Add words or phrases") {
        HStack(spacing: 10) {
          Image(systemName: "text.badge.plus")
            .foregroundStyle(.secondary)
            .frame(width: 22)

          TextField("Kubernetes, SwiftWhisper, a person's name…", text: $vocabularyInput)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addVocabularyEntries)

          Button("Add", action: addVocabularyEntries)
            .buttonStyle(.borderedProminent)
            .disabled(
              vocabularyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || vocabulary.entries.count >= VocabularyStore.maximumEntryCount
            )
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
      }

      SettingsSection(title: "Your vocabulary") {
        if vocabulary.entries.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
              .font(.title2)
              .foregroundStyle(.tertiary)
            Text("No custom words yet")
              .foregroundStyle(.secondary)
            Text("Add names, product terms, and jargon that speech recognition often misses.")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 28)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(vocabulary.entries.enumerated()), id: \.element) { index, entry in
              if index > 0 { Divider() }
              HStack(spacing: 12) {
                Image(systemName: "textformat")
                  .foregroundStyle(.secondary)
                  .frame(width: 22)
                Text(entry)
                  .textSelection(.enabled)
                Spacer()
                Button {
                  vocabulary.remove(entry)
                } label: {
                  Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove \(entry)")
              }
              .padding(.vertical, 8)
              .padding(.horizontal, 4)
            }
          }
        }
      }

      HStack {
        Text("Applied locally to every speech model. Separate multiple entries with commas.")
        Spacer()
        Text("\(vocabulary.entries.count)/\(VocabularyStore.maximumEntryCount)")
          .monospacedDigit()
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }

  private func addVocabularyEntries() {
    guard vocabulary.add(from: vocabularyInput) > 0 else { return }
    vocabularyInput = ""
  }

  private var historyPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsSection(title: "Dictation history") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Save voice recordings and transcripts", isOn: $historyEnabled)
            .toggleStyle(.switch)

          Text(
            historyEnabled
              ? "New dictations are saved locally on this Mac. The newest 100 are kept."
              : "History is off. New dictations are not recorded or saved."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Text("Saved corrections stay paired with the original transcript and recording.")
            .font(.caption)
            .foregroundStyle(.secondary)

          if !historyEnabled, !history.entries.isEmpty {
            Text("Previously saved history remains available until you clear it.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
      }

      SettingsSection(title: "Recent dictations") {
        if history.entries.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
              .font(.title2)
              .foregroundStyle(.tertiary)
            Text("No saved dictations")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 28)
        } else {
          VStack(spacing: 0) {
            HStack {
              Text("\(history.entries.count) of \(DictationHistoryStore.maximumEntryCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Clear…", role: .destructive) {
                showClearHistoryConfirmation = true
              }
              .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            Divider()

            ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
              if index > 0 { Divider() }
              DictationHistoryRow(
                entry: entry,
                isPlaying: history.playingEntryID == entry.id,
                play: { history.play(entry) },
                correct: { correctionEntry = entry },
                copy: {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(entry.displayTranscript, forType: .string)
                },
                delete: { history.delete(entry) }
              )
            }
          }
        }
      }
    }
  }

  private func openAppleIntelligenceSettings() {
    let directURL = URL(
      string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"
    )!
    if !NSWorkspace.shared.open(directURL) {
      NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
        configuration: NSWorkspace.OpenConfiguration()
      )
    }
  }

  private var appearancePage: some View {
    VStack(alignment: .leading, spacing: 10) {
      SettingsSection(title: "Notch animation") {
        VStack(spacing: 0) {
          ForEach(Array(NotchAnimationStyle.allCases.enumerated()), id: \.element.id) {
            index, style in
            if index > 0 { Divider() }
            AnimationStyleRow(
              style: style,
              isSelected: animationStyleRawValue == style.rawValue
            ) {
              withAnimation(.snappy(duration: 0.2)) {
                animationStyleRawValue = style.rawValue
              }
            }
          }
        }
      }

      Text("The animation reacts to your microphone level while listening.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var permissionPage: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSection(title: "Access") {
        VStack(spacing: 0) {
          PermissionRow(
            title: "Microphone",
            detail: "Records only while Right Option is held.",
            state: state(for: controller.permissionSnapshot?.microphone)
          )
          Divider()
          PermissionRow(
            title: "Speech Recognition",
            detail: "Transcribes speech with Apple Dictation.",
            state: state(for: controller.permissionSnapshot?.speechRecognition)
          )
          Divider()
          PermissionRow(
            title: "Input Monitoring",
            detail: "Detects Right Option in other applications.",
            state: state(for: controller.permissionSnapshot?.inputMonitoring),
            actionTitle: inputMonitoringNeedsAccess ? "Request Access" : nil,
            action: inputMonitoringNeedsAccess
              ? { controller.requestInputMonitoring() }
              : nil
          )
          Divider()
          PermissionRow(
            title: "Accessibility",
            detail: "Types into the currently focused field.",
            state: state(for: controller.permissionSnapshot?.accessibility)
          )
        }
      }

      HStack {
        Button {
          controller.requestPermissions()
        } label: {
          if controller.isRequestingPermissions {
            ProgressView()
              .controlSize(.small)
          } else {
            Text("Request Permissions")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.isRequestingPermissions)

        Button("Open Input Monitoring Settings", action: openInputMonitoringSettings)

        Spacer()
      }
      .padding(.top, 8)
    }
  }

  private func state(for status: PermissionStatus?) -> SettingsPermissionState {
    guard let status else { return .checking }
    switch status {
    case .granted: return .granted
    case .notDetermined: return .notRequested
    case .denied, .restricted: return .required
    }
  }

  private var inputMonitoringNeedsAccess: Bool {
    guard let status = controller.permissionSnapshot?.inputMonitoring else { return false }
    if case .trusted = status { return false }
    return true
  }

  private func openInputMonitoringSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func state(for status: TrustStatus?) -> SettingsPermissionState {
    guard let status else { return .checking }
    switch status {
    case .trusted: return .granted
    case .notTrusted: return .required
    }
  }
}

private struct SpeechModelRow: View {
  let model: SpeechModel
  let state: SpeechModelManager.State
  let isSelected: Bool
  let use: () -> Void
  let download: () -> Void
  let cancelDownload: () -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: model.systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .frame(width: 30, height: 30)
        .background(
          isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(model.name)
        Text(model.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case .failed(let message) = state {
          Text(message)
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 12)
      controls
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private var controls: some View {
    switch state {
    case .available, .installed:
      if isSelected {
        Label("In Use", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
      } else {
        Button("Use", action: use)
        if model.requiresDownload {
          Button(action: remove) {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help("Remove downloaded model")
        }
      }
    case .notDownloaded:
      Button {
        download()
      } label: {
        Text(model.approximateSize.map { "Download · \($0)" } ?? "Download")
      }
    case .downloading(let progress):
      HStack(spacing: 8) {
        if let progress {
          ProgressView(value: progress)
            .frame(width: 72)
          Text(progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
        } else {
          ProgressView()
            .controlSize(.small)
          Text("Downloading…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button(action: cancelDownload) {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
      }
    case .failed:
      Button("Retry", action: download)
    }
  }
}

enum SettingsPage: String, CaseIterable, Identifiable {
  static let storageKey = "settingsPage"

  case control
  case languageAndModels
  case vocabulary
  case history
  case appearance
  case permission
  case support

  var id: String { rawValue }

  var title: String {
    switch self {
    case .control: "Control"
    case .languageAndModels: "Language and Models"
    case .vocabulary: "Vocabulary"
    case .history: "History"
    case .appearance: "Appearance"
    case .permission: "Permissions"
    case .support: "Support"
    }
  }

  var subtitle: String {
    switch self {
    case .control: "Choose how you start and finish dictation."
    case .languageAndModels: "Configure transcription language and speech processing."
    case .vocabulary: "Help every speech model recognize the words you use."
    case .history: "Review recent voice recordings and transcriptions."
    case .appearance: "Personalize how SwiftWhisper responds while listening."
    case .permission: "Manage the system access SwiftWhisper needs."
    case .support: "Get help and share a diagnostic report."
    }
  }

  var systemImage: String {
    switch self {
    case .control: "switch.2"
    case .languageAndModels: "globe"
    case .vocabulary: "character.book.closed"
    case .history: "clock.arrow.circlepath"
    case .appearance: "paintbrush"
    case .permission: "lock.shield"
    case .support: "lifepreserver"
    }
  }
}

private struct SettingsSidebarRow: View {
  let page: SettingsPage
  let isSelected: Bool
  let needsAttention: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: page.systemImage)
          .foregroundStyle(
            needsAttention ? Color.orange : isSelected ? Color.primary : Color.secondary
          )
          .frame(width: 18)
        Text(page.title)
        Spacer(minLength: 0)
        if needsAttention {
          Image(systemName: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Permissions required")
        }
      }
      .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      .padding(.horizontal, 10)
      .frame(height: 34)
      .contentShape(Rectangle())
      .background(
        isSelected
          ? Color.accentColor.opacity(0.14)
          : needsAttention ? Color.orange.opacity(0.12) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }
}

private struct DictationHistoryRow: View {
  let entry: DictationHistoryEntry
  let isPlaying: Bool
  let play: () -> Void
  let correct: () -> Void
  let copy: () -> Void
  let delete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      Button(action: play) {
        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 28, height: 28)
          .background(Color.cyan.opacity(0.12), in: Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.cyan)
      .help(isPlaying ? "Stop recording" : "Play recording")

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.displayTranscript)
          .foregroundStyle(.primary)
          .lineLimit(4)
          .textSelection(.enabled)

        HStack(spacing: 6) {
          Text("\(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(durationText)")
          if entry.hasCorrection {
            Text("Corrected")
              .foregroundStyle(.cyan)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Button(action: correct) {
        Image(systemName: entry.hasCorrection ? "pencil.circle.fill" : "pencil")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(entry.hasCorrection ? .cyan : .secondary)
      .help(entry.hasCorrection ? "Edit correction" : "Add correction")

      Button(action: copy) {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless)
      .help("Copy transcript")

      Button(action: delete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help("Delete")
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 10)
  }

  private var durationText: String {
    let totalSeconds = max(0, Int(entry.duration.rounded()))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}

private struct DictationCorrectionSheet: View {
  let entry: DictationHistoryEntry
  @ObservedObject var history: DictationHistoryStore

  @Environment(\.dismiss) private var dismiss
  @State private var correctedText: String

  init(entry: DictationHistoryEntry, history: DictationHistoryStore) {
    self.entry = entry
    self.history = history
    _correctedText = State(initialValue: entry.displayTranscript)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.hasCorrection ? "Edit Correction" : "Add a Correction")
            .font(.title2.weight(.semibold))
          Text("Your edit is saved with the original dictation to help improve recognition later.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          history.play(entry)
        } label: {
          Label(
            history.playingEntryID == entry.id ? "Stop" : "Play Recording",
            systemImage: history.playingEntryID == entry.id ? "stop.fill" : "play.fill"
          )
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("Live changes")
            .font(.headline)
          Spacer()
          HStack(spacing: 10) {
            Label("Removed", systemImage: "strikethrough")
            Label("Added", systemImage: "plus")
              .foregroundStyle(.green)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        liveDiffText
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .accessibilityLabel("Changes from original transcription")
          .accessibilityValue(correctedText)
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Corrected transcription")
          .font(.headline)
        TextEditor(text: $correctedText)
          .font(.body)
          .padding(6)
          .frame(minHeight: 130)
          .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
          }
      }

      HStack {
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save Correction") {
          history.saveCorrection(for: entry, correctedTranscript: correctedText)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 580, height: 440)
    .onDisappear {
      if history.playingEntryID == entry.id {
        history.play(entry)
      }
    }
  }

  private var liveDiffText: Text {
    var result = AttributedString()
    for segment in InlineTextDiff.segments(from: entry.transcript, to: correctedText) {
      var attributedSegment = AttributedString(segment.text)
      switch segment.change {
      case .unchanged:
        break
      case .removed:
        attributedSegment.foregroundColor = .secondary
        attributedSegment.strikethroughStyle = Text.LineStyle(
          pattern: .solid,
          color: .secondary
        )
      case .added:
        attributedSegment.foregroundColor = .green
      }
      result.append(attributedSegment)
    }
    return Text(result)
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)

      GroupBox {
        content
      }
    }
  }
}

private struct AnimationStyleRow: View {
  let style: NotchAnimationStyle
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 12) {
        Image(systemName: style.systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(isSelected ? .cyan : .secondary)
          .frame(width: 26, height: 26)
          .background(
            isSelected ? Color.cyan.opacity(0.13) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
          )

        VStack(alignment: .leading, spacing: 2) {
          Text(style.title)
            .foregroundStyle(.primary)
          Text(style.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.cyan : Color.secondary.opacity(0.5))
      }
      .contentShape(Rectangle())
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
    }
    .buttonStyle(.plain)
  }
}

private struct SettingsValueRow: View {
  let systemImage: String
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 4)
  }
}

private struct SmartPolishNotice {
  let title: String
  let detail: String
  var actionTitle: String?
  var action: (() -> Void)?

  init(
    title: String,
    detail: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.actionTitle = actionTitle
    self.action = action
  }
}

private struct QwenPolishModelRow: View {
  let state: PolishModelManager.State
  let download: () -> Void
  let cancel: () -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "sparkles.rectangle.stack")
        .foregroundStyle(.cyan)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text("Qwen3 0.6B · 4-bit")
        Text("Compact multilingual model · about 350 MB")
          .font(.caption)
          .foregroundStyle(.secondary)
        if case .failed(let message) = state {
          Text(message)
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
      Spacer()
      controls
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private var controls: some View {
    switch state {
    case .notDownloaded:
      Button("Download", action: download)
    case .downloading(let progress):
      HStack(spacing: 8) {
        if let progress {
          ProgressView(value: progress).frame(width: 72)
          Text(progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
        } else {
          ProgressView().controlSize(.small)
        }
        Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.borderless)
      }
    case .installed:
      Label("Ready", systemImage: "checkmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.green)
      Button(action: remove) { Image(systemName: "trash") }
        .buttonStyle(.borderless)
    case .failed:
      Button("Retry", action: download)
    }
  }
}

private struct SmartPolishNoticeRow: View {
  let notice: SmartPolishNotice

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(notice.title)
        Text(notice.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if let actionTitle = notice.actionTitle, let action = notice.action {
        Button(actionTitle, action: action)
      }
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 4)
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let state: SettingsPermissionState
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: state.systemImage)
        .foregroundStyle(state.color)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Text(state.label)
        .font(.callout)
        .foregroundStyle(state.color)

      if let actionTitle, let action {
        Button(actionTitle, action: action)
      }
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 4)
  }
}

private enum SettingsPermissionState {
  case checking
  case granted
  case notRequested
  case required

  var label: String {
    switch self {
    case .checking: "Checking…"
    case .granted: "Granted"
    case .notRequested: "Not requested"
    case .required: "Required"
    }
  }

  var systemImage: String {
    switch self {
    case .checking: "clock"
    case .granted: "checkmark.circle.fill"
    case .notRequested, .required: "exclamationmark.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .checking: .secondary
    case .granted: .green
    case .notRequested, .required: .orange
    }
  }
}

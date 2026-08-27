# SwiftWhisper — Product and Engineering Specification

Status: implementation-ready draft  
Date: 2026-08-26  
Target: macOS 26+, Apple silicon  
Product type: native menu-bar application  

## 1. Executive decision

SwiftWhisper is a private, offline-first, push-to-talk dictation utility for macOS. The application is written in Swift using SwiftUI and AppKit. It uses Apple's `SpeechAnalyzer` with `DictationTranscriber` by default and provides downloadable local model packages for Whisper, Moonshine, Qwen3-ASR, and NVIDIA Parakeet.

The application has no cloud transcription, accounts, telemetry, or server-side history. Audio and transcripts never leave the Mac. Explicit model downloads still disclose ordinary network metadata such as the user's IP address, request time, and selected artifact URL to the hosting provider; SwiftWhisper must say this plainly rather than describe downloads as private.

The central product promise is:

> Hold one key, speak, release, and the words appear where you were typing.

### Decisions made because the product owner requested no follow-up questions

- Distribution: direct, Developer ID-signed and notarized application; not Mac App Store for v1.
- Minimum OS: macOS 26 because the requested `SpeechAnalyzer` and `DictationTranscriber` APIs are macOS 26+.
- Hardware: Apple silicon is required for v1. Intel is explicitly unsupported.
- Activation: push-to-talk. Key-down begins capture; key-up finishes capture.
- Default wake key: right Option. First alternative: Fn/Globe.
- Default model: Apple Dictation, using the current system locale.
- Audio retention: never retained as history. Non-streaming engines may use an owner-only, backup-excluded temporary file that is deleted as soon as finalization or cancellation completes.
- History retention: local and indefinite until the user deletes it.
- Text delivery: direct Accessibility insertion first, Unicode key-event insertion second, reversible clipboard paste last.
- Custom-model runtime: one Sherpa-ONNX adapter shared by all four requested model families, avoiding four unrelated inference stacks.
- Release strategy: ship an Apple-only internal alpha, add Whisper and Moonshine for a public beta, then add experimental Qwen3-ASR and Parakeet packages. Call the product 1.0 only after every requested family passes its hardware and quality gates.

## 2. Product goals

### Target user and narrowest wedge

The first user is a privacy-sensitive Apple-silicon Mac owner who writes repeatedly across several apps—messages, documents, issue trackers, email, and terminals—and wants push-to-talk dictation without sending voice or text to a service. The narrowest valuable product is not “a marketplace of ASR models.” It is a dependable right-Option-to-text loop using Apple's local model, with searchable recovery when insertion is impossible. Downloadable models are the power-user expansion after that loop is trustworthy.

### Primary goals

1. Start listening within 150 ms of the wake key being pressed.
2. Produce useful text entirely on-device.
3. Insert the final text into the focused editable control without stealing focus.
4. Never lose a successful transcript: if insertion is impossible, save it to history.
5. Make model installation understandable, verifiable, resumable, and reversible.
6. Feel like a native part of macOS rather than a web application in a wrapper.

### Success criteria

- Median time from wake-key press to visible listening feedback: under 150 ms.
- Apple-model finalization after key release for the committed 10-second benchmark utterance: p50 under 1 second and p95 under 1.5 seconds across 20 warm runs on the reference M1 MacBook Air with 8 GB RAM.
- Every nonempty completed transcript is durably persisted before automatic delivery is attempted. If the filesystem is unavailable or full, automatic delivery is blocked and a non-dismissing, selectable recovery view remains until the user copies or saves the text.
- No audio or transcript data is transmitted by the application.
- Clipboard fallback never overwrites clipboard content created after SwiftWhisper's temporary write, and it is skipped unless the prior pasteboard can be materialized completely.
- Crash-free completion for 1,000 repeated record/transcribe/deliver cycles in an automated soak test.
- All state-machine transitions and failure paths have tests.

### Product premise challenge

The dangerous premise is that “native and offline” alone is enough. macOS already has system Dictation, and mature competitors already offer polished global dictation. SwiftWhisper earns its existence only if it is materially better for users who care about control:

- a visible and verifiable no-cloud boundary;
- interchangeable local models instead of one opaque engine;
- graceful recovery when cross-app insertion fails;
- searchable local history with clear retention controls;
- predictable, low-friction push-to-talk behavior.

If the Apple-only vertical slice is not noticeably more dependable or understandable than macOS Dictation, stop before building the model marketplace. Model choice cannot rescue a weak core loop.

## 3. Non-goals for 1.0

- Cloud ASR or cloud fallback.
- Generative rewriting, summarization, or prompt-based text cleanup.
- iPhone, iPad, Windows, or Linux clients.
- Team accounts, sync, shared dictionaries, or web dashboards.
- Arbitrary Hugging Face repositories. SwiftWhisper downloads only reviewed, manifest-defined model packages.
- A public third-party plug-in ABI. Runtime boundaries are internal Swift protocols in 1.0.
- Continuous meeting recording, speaker diarization, or system-audio capture.
- A literal modification of the Mac's hardware notch or Apple's private UI. SwiftWhisper renders its own top-center overlay.

## 4. Critical platform truths

### 4.1 Apple's modern speech APIs require macOS 26

The installed macOS 26 SDK declares `SpeechAnalyzer`, `DictationTranscriber`, `SpeechTranscriber`, `AssetInventory`, and `AssetInstallationRequest` as macOS 26+ APIs. SwiftWhisper should therefore use macOS 26 as its deployment target rather than maintain two speech architectures.

For dictation, prefer `DictationTranscriber` over the generic `SpeechTranscriber` because it exposes dictation-oriented presets and punctuation/emoji options. The recommended preset is `.progressiveLongDictation`, with punctuation enabled and volatile results enabled for live feedback.

### 4.2 There is no public API to extend the Mac notch

The feature should be named `Notch Capsule` internally. It is a borderless, non-activating `NSPanel` positioned at the top center of the active display. On a MacBook with a notch, it visually grows from beneath the notch. On other displays it becomes a floating top-center pill.

Do not use private APIs, draw inside system-owned menu-bar regions, or claim to be a real Dynamic Island.

### 4.3 Modifier-only global triggers are special

Right Option and Fn are detected through modifier flag changes rather than ordinary key-down events. The implementation must track physical key codes and modifier transitions, debounce duplicate events, recover if the event tap is disabled, and never treat left Option as right Option.

Fn/Globe behavior varies with keyboard hardware and System Settings. Onboarding must include a live trigger test and explain conflicts with Apple's built-in Dictation or Globe actions.

### 4.4 “Offline-only” still permits explicit model installation

Inference is always offline. Network access is permitted only for:

- user-initiated download of a third-party model package;
- user-initiated installation of an Apple speech asset through `AssetInventory`;
- future app-update checks, if added later and disclosed separately.

No audio, transcript, history, application name, or behavioral telemetry is sent with these requests. A download necessarily reveals normal network metadata and which artifact URL was requested; Apple-managed asset traffic is controlled by the operating system rather than observable or configurable by SwiftWhisper.

## 5. Product experience

### 5.1 First-run onboarding

Onboarding is a single window with a quiet, linear flow. It must remain accessible later through Settings > Run Setup Again.

### Step 1 — Privacy promise

Primary copy:

> Your voice stays on this Mac.

Supporting copy:

> SwiftWhisper records only while you hold your wake key. Transcription runs locally. Audio is discarded after the text is produced.

Primary action: `Continue`.

### Step 2 — Choose the wake key

Show two prominent physical-key choices:

1. `Right Option` — selected by default and labeled Recommended.
2. `Fn / Globe` — secondary choice.

Also show `Choose another shortcut…`, which accepts either a modifier-only physical key or a conventional chord. The UI must show left/right specificity.

After selection, require a live test:

- idle: “Hold Right Option to test”;
- pressed: capsule animates and reads “Listening”;
- released: “Shortcut works.”

If Fn is consumed by the system, show a link to the relevant Keyboard settings and offer Right Option immediately.

### Step 3 — Microphone and speech assets

Request microphone permission only after explaining why it is needed. Then inspect the Apple dictation model for the chosen locale:

- installed: continue;
- supported but missing: show size/progress if available and invoke `AssetInstallationRequest.downloadAndInstall()`;
- unsupported: offer another supported locale or continue to Model Manager.

Include `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.

### Step 4 — Global control and text insertion

Explain two separate capabilities:

- Input Monitoring lets SwiftWhisper notice the wake key in any application.
- Accessibility lets SwiftWhisper place text in the current editor.

Use `CGPreflightListenEventAccess`/`CGRequestListenEventAccess` for event monitoring and `AXIsProcessTrustedWithOptions` for Accessibility. Show live status and a `Open System Settings` action. Re-check when the app becomes active; do not assume the user returned from Settings immediately.

### Step 5 — End-to-end test

Show an editable test field. The user holds the configured key, speaks, releases, and sees the transcript inserted. The test passes only if capture, ASR, and insertion all succeed.

If insertion permission is missing but ASR succeeds, show the transcript and keep onboarding at this step with a clear recovery action.

### Step 6 — Finish

Show:

- current wake key;
- selected model and locale;
- `Launch at Login` toggle, default off;
- final action: `Start Using SwiftWhisper`.

After completion the app becomes an accessory/status-bar application with no Dock icon.

### 5.2 Everyday interaction

### Push-to-talk contract

1. User holds the wake key.
2. SwiftWhisper snapshots the current frontmost application and focused Accessibility element.
3. The Notch Capsule appears immediately.
4. Audio capture starts.
5. Partial text appears when the selected engine supports it.
6. User releases the key.
7. Capture stops, the engine finalizes, and the capsule enters Processing.
8. Final text is normalized and written to a durable `pendingDelivery` history/recovery record.
9. SwiftWhisper attempts insertion and updates the record with the delivery outcome.
10. The capsule briefly confirms `Inserted`, `Sent to App — saved in History`, or `Saved to History`, then disappears.

When Accessibility trust is available, pressing Escape while listening cancels the session and discards audio; the active event tap suppresses that Escape so the foreground application does not also consume it. If Accessibility is unavailable or revoked, SwiftWhisper uses a listen-only tap, disables Escape cancellation, and relies on wake-key release or the capsule's Cancel action. At all other times Escape passes through untouched. A second wake-key press while a session is finalizing is ignored with a subtle busy pulse; sessions never overlap.

### Short or accidental presses

- Under 120 ms: treat as an accidental press and cancel silently.
- At 120 ms or longer: let the recognizer decide whether speech exists; RMS is visual feedback, not voice detection.
- Empty final transcript: show `No speech detected`, do not inject, and create no history item unless an engine error occurred.

### Maximum duration

The 1.0 maximum is 10 minutes. At 9:30 the capsule shows remaining time. At 10:00 capture ends and transcription finalizes. This prevents unbounded temporary storage and pathological decoder memory use.

### 5.3 Status-bar menu

Menu hierarchy:

```text
SwiftWhisper
├── Start Dictation…                Right Option
├── Open History…
├── Model
│   ├── Apple Dictation             ✓
│   ├── Whisper …
│   ├── Moonshine …
│   ├── Qwen3-ASR …
│   └── NVIDIA Parakeet …
├── Microphone                      MacBook Microphone
├── Pause SwiftWhisper
├── Settings…
├── About SwiftWhisper
└── Quit SwiftWhisper
```

`Start Dictation…` enters click-to-start mode and changes to `Stop Dictation`; it exists for accessibility and discoverability rather than emulating hold-to-talk with a menu click. The icon is a monochrome template symbol. It changes subtly while recording and processing but must not animate continuously in the menu bar.

### 5.4 Main window information architecture

`Open History…` opens a normal resizable window. Settings is a separate native Settings scene.

```text
History window
┌─────────────────────────────────────────────────────────────┐
│ Search dictations…                              Clear…      │
├──────────────────────┬──────────────────────────────────────┤
│ Today                │ Transcript text                      │
│ 10:42  First words…  │                                      │
│ 09:15  Another…      │ Model, language, duration, app       │
│ Yesterday            │                                      │
│ …                    │ Copy   Insert Again   Delete         │
└──────────────────────┴──────────────────────────────────────┘

Settings
├── General: shortcut, microphone, launch at login, sounds
├── Models: installed/available models, locale, download state
├── Privacy: local-only explanation, history controls, permissions
└── About: versions, licenses, acknowledgements
```

History empty state:

> Your dictations will appear here when text cannot be inserted—or whenever you want to reuse something you said.

Primary action: `Try Dictation`.

Search is case- and diacritic-insensitive. Results update after a 150 ms debounce. Keyboard navigation and VoiceOver labels are required.

### 5.5 Notch Capsule visual specification

The capsule is an AppKit `NSPanel` hosting SwiftUI content.

- Window style: borderless, transparent, non-activating.
- Window level: high enough to appear above ordinary application windows, but below system alerts and menus.
- Collection behavior: join all Spaces, stationary, full-screen auxiliary.
- Position: choose the display in this order: focused element frame, focused window frame, mouse location, then main display. Convert Accessibility coordinates into AppKit screen coordinates and place the panel below that display's visible menu-bar/safe-area boundary. If displays change mid-session, keep the panel on its original display until the session ends.
- Listening size: approximately 232 × 42 pt.
- Processing size: approximately 156 × 36 pt.
- Confirmation size: content-driven, no wider than 220 pt.
- Fill: near-black material at roughly 92% opacity.
- Radius: half the panel height for a true capsule.
- Text: SF Pro, semibold status, regular partial transcript.
- Accent: one cool cyan/teal accent for live waveform and success; red only for destructive/error states.
- Shadow: one restrained ambient shadow; no stacked glows.

Motion:

- entry: 180 ms scale/fade from 0.94 to 1.0;
- horizontal expansion: 220 ms spring, low bounce;
- waveform: amplitude-driven bars at display refresh rate, smoothed from RMS samples;
- listening to processing: waveform compresses into three breathing dots;
- success: a single 120 ms checkmark draw, then fade after 500 ms;
- Reduce Motion: cross-fades only; no spring, waveform becomes a static level meter.

Only the current status and at most two lines of partial text may appear. The overlay never becomes a mini dashboard.

### 5.6 Interaction-state matrix

| Feature | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Onboarding permissions | Spinner only during OS request | N/A | Explain denied permission and link to Settings | Checkmark plus `Granted` | One permission may be granted while another is missing |
| Apple model asset | Progress if reported | No installed locale | Unsupported locale or download failure | `Ready offline` | Download paused/interrupted with Retry |
| Third-party model | Per-file progress and total bytes | No optional models installed | Checksum, disk, network, or compatibility error | Installed and selectable | Resume available after interruption |
| Dictation | `Preparing model…` if cold | No speech detected | Mic/engine/insertion error | Inserted or saved | Live transcript when engine supports it |
| History | Search progress should normally be imperceptible | Warm explanation and Try Dictation action | Non-destructive database recovery message | Results list | No matches includes Clear Search action |

## 6. Recommended architecture

### 6.1 Approaches considered

#### Approach A — Apple vertical slice, then one shared custom runtime (recommended)

Build the entire wake-key-to-insertion flow with Apple's engine first. Stabilize domain interfaces, then add one Sherpa-ONNX-backed engine capable of loading model-family-specific configurations.

Pros: earliest usable product, one third-party runtime, smallest architecture that still supports all requested models.  
Cons: downloadable models arrive after the core flow during development.  
Risk: low to medium.

#### Approach B — Four custom inference implementations

Use WhisperKit for Whisper, a custom Core ML pipeline for Moonshine, MLX Swift for Qwen3-ASR, and a separate Parakeet runtime.

Pros: each family can use its theoretically ideal backend.  
Cons: four dependency trees, four audio/tokenizer paths, inconsistent behavior, and a large maintenance burden.  
Risk: high. Rejected.

#### Approach C — Out-of-process inference service

Run all third-party inference in a bundled XPC service.

Pros: crash and memory isolation; easier runtime restarts.  
Cons: XPC protocol/versioning, model-file entitlements, audio transfer overhead, and materially more launch complexity.  
Risk: medium. Defer until third-party runtime instability is demonstrated.

### 6.2 System diagram

```text
                     ┌──────────────────────────┐
physical key events ─▶ GlobalHotKeyMonitor      │
                     └────────────┬─────────────┘
                                  │ HotKeyEvent
                                  ▼
                     ┌──────────────────────────┐
                     │ DictationCoordinator     │ @MainActor
                     │ single session owner     │
                     └───┬────────┬────────┬────┘
                         │        │        │
              UI state ──┘        │        └── delivery result
                         ▼        ▼
                ┌────────────┐  ┌─────────────────────┐
                │ Overlay UI │  │ FocusedTextDelivery │
                └────────────┘  └──────────┬──────────┘
                                           │
                  audio                    ├─ AX direct insertion
                    │                      ├─ Unicode CGEvent fallback
                    ▼                      └─ clipboard fallback
          ┌──────────────────┐
          │ AudioCapture     │ actor
          └────────┬─────────┘
                   │ AsyncStream<AudioFrame>
                   ▼
          ┌──────────────────┐      ┌─────────────────────┐
          │ ASREngine        │◀─────│ ASREngineFactory    │
          └───────┬──────────┘      └──────────┬──────────┘
                  │                            │
         ASREvent │                 ┌──────────┴──────────┐
                  ▼                 ▼                     ▼
          ┌──────────────┐  AppleSpeechEngine    SherpaONNXEngine
          │ PostProcessor│                       ├─ Whisper
          └──────┬───────┘                       ├─ Moonshine
                 │                               ├─ Qwen3-ASR
                 │                               └─ Parakeet
                  ▼
       ┌──────────────────────┐
       │ Recovery + History   │ durable pending record
       └──────────┬───────────┘
                  │
                  └──────────────▶ FocusedTextDelivery

ModelCatalog ─▶ ModelDownloadManager ─▶ Verified ModelStore ─▶ ASREngineFactory
Permissions ────────────────────────────────────────────────▶ Coordinator
```

### 6.3 Session state machine

```text
                         permission/model failure
                                  ┌──────────────┐
                                  ▼              │
idle ──keyDown──▶ arming ──ready──▶ listening ───┼──keyUp──▶ finalizing
 ▲                  │               │             │             │
 │                  └──failure──────┴─────────────┘             ▼
 │                                                           transcribing
 │                                                               │
 │                                                               ▼
 │                                                         postProcessing
 │                                                               │
 │                                                               ▼
 │                                                    persistPending
 │                                                               │
 │                                                               ▼
 │                                                           delivering
 │                                                         ┌─────┴─────┐
 │                                                         ▼           ▼
 └──────────── confirmation ◀────────────────────────── inserted   saved

Any active state ──Escape/cancel──▶ cancelling ──cleanup──▶ idle
Any illegal transition is ignored and logged locally in debug builds.
```

The state machine must be a pure reducer with exhaustively tested transitions. Side effects are emitted as commands and executed by the coordinator. UI must never infer state by inspecting several booleans.

## 7. Project structure

Use one Xcode project and avoid premature module proliferation.

```text
SwiftWhisper/
├── SwiftWhisper.xcodeproj
├── App/
│   ├── SwiftWhisperApp.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift
│   └── MenuBarController.swift
├── Domain/
│   ├── DictationState.swift
│   ├── DictationSession.swift
│   ├── ASRTypes.swift
│   ├── ModelTypes.swift
│   ├── PermissionTypes.swift
│   └── HistoryTypes.swift
├── Features/
│   ├── Onboarding/
│   ├── Overlay/
│   ├── History/
│   ├── Settings/
│   └── ModelManager/
├── Services/
│   ├── DictationCoordinator.swift
│   ├── GlobalHotKeyMonitor.swift
│   ├── AudioCaptureService.swift
│   ├── FocusedTextDeliveryService.swift
│   ├── PermissionService.swift
│   ├── HistoryRepository.swift
│   ├── ModelCatalogService.swift
│   ├── ModelDownloadManager.swift
│   └── TextPostProcessor.swift
├── Runtimes/
│   ├── AppleSpeech/
│   └── SherpaONNX/
├── Persistence/
│   ├── SwiftWhisper.xcdatamodeld
│   └── PersistenceController.swift
├── Resources/
│   ├── ModelCatalog.json
│   ├── PrivacyInfo.xcprivacy
│   └── Assets.xcassets
├── SwiftWhisperTests/
├── SwiftWhisperUITests/
└── TestSupport/InjectionHarness/
```

Files containing the state machine, ASR stream adapter, model installer, and delivery fallback chain should include compact ASCII diagrams in code comments. These flows are non-obvious enough that future changes could otherwise introduce silent data loss.

## 8. Typed domain interfaces

The following interfaces define the intended boundaries. Names may change during implementation, but responsibilities and semantics should not.

### 8.1 Wake-key types

```swift
import AppKit
import CoreGraphics

enum PhysicalModifierKey: String, Codable, Sendable, CaseIterable {
    case rightOption
    case leftOption
    case function
    case rightShift
    case leftShift
    case rightCommand
    case leftCommand
    case rightControl
    case leftControl
}

struct ModifierMask: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt64

    static let command  = Self(rawValue: 1 << 0)
    static let option   = Self(rawValue: 1 << 1)
    static let control  = Self(rawValue: 1 << 2)
    static let shift    = Self(rawValue: 1 << 3)
    static let function = Self(rawValue: 1 << 4)
}

enum WakeBinding: Codable, Sendable, Equatable {
    case modifierOnly(PhysicalModifierKey)
    case chord(keyCode: UInt16, modifiers: ModifierMask)

    static let defaultBinding: Self = .modifierOnly(.rightOption)
    static let secondaryBinding: Self = .modifierOnly(.function)
}

enum HotKeyEvent: Sendable, Equatable {
    case pressed(monotonicTime: ContinuousClock.Instant)
    case released(monotonicTime: ContinuousClock.Instant)
    case escapePressed(monotonicTime: ContinuousClock.Instant)
    case tapDisabled
    case physicalStateInvalidated
}

protocol GlobalHotKeyMonitoring: Sendable {
    func events(for binding: WakeBinding) async throws -> AsyncStream<HotKeyEvent>
    func stop() async
}
```

Implementation notes:

- Back with a dedicated thread that owns a `CFRunLoop` and `CFRunLoopSource`. The minimal C-compatible event-tap callback converts the event to an immutable value and forwards it into actor state; it must never perform ASR, UI, disk, or async work.
- Observe `flagsChanged`, `keyDown`, and `keyUp`.
- Use physical key codes so keyboard layout changes do not change the binding.
- Track each physical modifier key independently. Aggregate flags are advisory only: right Option release must still be recognized when left Option remains held.
- The adapter maps Carbon virtual key codes (`kVK_Option` 0x3A, `kVK_RightOption` 0x3D, `kVK_Function` 0x3F, plus the left/right Command, Control, and Shift constants). For each `flagsChanged`, derive the named key's current state with `CGEventSource.keyState(.combinedSessionState, key:)`; emit only rising/falling edges relative to the stored per-key state. Never infer right-key state from the aggregate Option flag.
- Re-enable the event tap after `.tapDisabledByTimeout` and `.tapDisabledByUserInput`, clear all remembered key state, and cancel an active session because the physical state is no longer trustworthy.
- Clear physical state on screen lock, sleep, keyboard removal, binding changes, and tap recreation.
- With Accessibility trust, use an active tap that passes all events through except Escape during active listening. Without Accessibility trust, use a listen-only tap and disable Escape cancellation rather than pretending it can be suppressed.
- Ignore keyboard auto-repeat.
- Modifier-only bindings may use one physical modifier. Chords require one non-modifier key plus one or more modifiers. Reject bare Command, bare Control, system-reserved shortcuts, the configured screenshot shortcuts, and any binding the onboarding test cannot observe reliably.
- A chord begins when its non-modifier key goes down while all required modifiers are held and ends when either the non-modifier key or any required modifier is released.

### 8.2 Permission types

```swift
enum PermissionKind: String, Codable, Sendable, CaseIterable {
    case microphone
    case speechRecognition
    case inputMonitoring
    case accessibility
}

enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum TrustStatus: Sendable, Equatable {
    case trusted
    case notTrusted(requestAttempted: Bool)
}

struct PermissionSnapshot: Sendable, Equatable {
    var microphone: PermissionStatus
    var speechRecognition: PermissionStatus
    var inputMonitoring: TrustStatus
    var accessibility: TrustStatus

    func canCapture(using family: ASRFamily) -> Bool {
        guard microphone == .granted else { return false }
        return family == .appleDictation ? speechRecognition == .granted : true
    }

    var canUseGlobalTrigger: Bool { inputMonitoring == .trusted }
    var canInjectText: Bool { accessibility == .trusted }
}

protocol PermissionServicing: Sendable {
    func currentSnapshot() async -> PermissionSnapshot
    func request(_ kind: PermissionKind) async
    func openSystemSettings(for kind: PermissionKind) async
}
```

Do not request all permissions at launch. Each request follows an explanatory screen. Permission polling is bounded and stops when onboarding closes.

### 8.3 Audio capture

```swift
import AVFoundation

struct AudioFormatRequirement: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat

    static let sherpaPCM16kMono = Self(
        sampleRate: 16_000,
        channelCount: 1,
        commonFormat: .pcmFormatFloat32
    )
}

struct AudioFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let sequenceNumber: UInt64
    let capturedAt: ContinuousClock.Instant
}

struct AudioLevel: Sendable, Equatable {
    let rms: Float
    let peak: Float
}

struct AudioCaptureSession: Sendable {
    let frames: AsyncThrowingStream<AudioFrame, Error>
    let levels: AsyncStream<AudioLevel>
}

protocol AudioCapturing: Sendable {
    func start(format: AudioFormatRequirement?) async throws -> AudioCaptureSession
    func stop() async throws
    func cancel() async
}
```

`AudioCaptureService` is an actor around `AVAudioEngine`. It converts from the hardware input format to the active engine's requested format with `AVAudioConverter`. Each emitted buffer is immutable and independently owned before crossing the actor boundary.

Capture starts immediately on wake press in the hardware-native format; it must not wait for model preparation. A two-second bounded pre-roll ring buffer holds frames while the selected engine reports its required format and prepares. Once ready, frames are converted and drained into the ASR session in sequence-number order. A sub-120 ms release discards this buffer. If engine preparation takes longer than the ring capacity, spill subsequent frames to the protected temporary session file rather than dropping the beginning of speech.

### 8.4 ASR engine abstraction

```swift
struct ASRModelID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

enum ASRFamily: String, Codable, Sendable {
    case appleDictation
    case whisper
    case moonshine
    case qwen3ASR
    case parakeet
}

struct ASRCapabilities: Codable, Sendable, Equatable {
    let supportsStreamingPartials: Bool
    let supportsWordTimestamps: Bool
    let supportsConfidence: Bool
    let supportsLanguageDetection: Bool
    let supportedLocales: Set<String>
    let maximumRecommendedDuration: Duration
}

struct RecognitionContext: Sendable, Equatable {
    let locale: Locale
    let vocabularyHints: [String]
    let punctuationEnabled: Bool
    let sourceApplicationBundleID: String?
}

struct TranscriptSegment: Sendable, Equatable {
    let id: UUID
    let text: String
    let start: Duration?
    let duration: Duration?
    let confidence: Double?
    let isFinal: Bool
}

enum ASREvent: Sendable, Equatable {
    case ready
    case partial([TranscriptSegment])
    case final([TranscriptSegment])
    case progress(Double)
    case warning(ASRWarning)
}

enum ASRWarning: Sendable, Equatable {
    case thermalPressure
    case lowConfidence
    case languageMismatch
    case durationApproachingLimit
}

protocol ASRSession: Sendable {
    var events: AsyncThrowingStream<ASREvent, Error> { get }
    func append(_ frame: AudioFrame) async throws
    func finish() async throws
    func cancel() async
}

protocol ASREngine: Sendable {
    var modelID: ASRModelID { get }
    var capabilities: ASRCapabilities { get async }
    func requiredAudioFormat() async throws -> AudioFormatRequirement?
    func prepare(context: RecognitionContext) async throws
    func makeSession(context: RecognitionContext) async throws -> any ASRSession
    func unload() async
}

enum ModelSelection: Codable, Sendable, Equatable {
    case apple(localeIdentifier: String)
    case downloaded(ModelPackageID)
}

protocol ASREngineFactory: Sendable {
    func makeEngine(for selection: ModelSelection) async throws -> any ASREngine
}
```

Rules:

- Every session produces exactly one final event or throws.
- `finish()` is idempotent.
- `cancel()` is safe in every lifecycle state.
- Partial segments replace prior volatile content rather than append blindly.
- Engines never perform network requests.

### 8.5 Apple engine

```swift
protocol AppleSpeechAssetManaging: Sendable {
    func status(locale: Locale) async -> AppleSpeechAssetStatus
    func install(locale: Locale) async
        -> AsyncThrowingStream<AppleAssetInstallState, Error>
    func reserve(locale: Locale) async throws -> AppleAssetReservationResult
    func release(locale: Locale) async -> Bool
}

enum AppleSpeechAssetStatus: Sendable, Equatable {
    case unsupported
    case supportedNotInstalled
    case downloading(progress: Double?)
    case installed
}

enum AppleAssetInstallState: Sendable, Equatable {
    case preparing
    case downloading(progress: Double)
    case installed
}

enum AppleAssetReservationResult: Sendable, Equatable {
    case reserved
    case alreadyReserved
    case limitReached(maximum: Int, currentlyReserved: [String])
    case unavailable
}
```

`AppleSpeechEngine` uses:

- `DictationTranscriber(locale:preset: .progressiveLongDictation)`;
- punctuation and etiquette replacement options;
- volatile results for overlay preview;
- audio time range and confidence result attributes;
- `SpeechAnalyzer.bestAvailableAudioFormat`;
- `SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)`;
- `AssetInventory` for supported, installed, reserved, and downloadable locale assets.

The selected locale should be reserved while it is the active default and released when another locale becomes active.

The installation stream is throwing because failures can occur after progress begins. Cancelling its consumer cancels the underlying installation task when the framework permits it. Before reserving, inspect `maximumReservedLocales` and `reservedLocales`; if the limit is reached, release only a locale previously reserved by SwiftWhisper, never an unrelated system reservation.

#### Exact `SpeechAnalyzer` session lifecycle

```text
create DictationTranscriber
        │
        ├─ verify/install/reserve locale asset
        ├─ obtain bestAvailableAudioFormat
        └─ create SpeechAnalyzer(modules: [transcriber])
                         │
                         ▼
              prepareToAnalyze(format)
                         │
             ┌───────────┴───────────┐
             ▼                       ▼
 consume transcriber.results   analyzer.start(inputSequence)
 and volatile-range updates    fed by owned continuation
             │                       │
             └───────────┬───────────┘
                         │ key release
                         ▼
              close input continuation
                         │
                         ▼
       finalizeAndFinishThroughEndOfInput()
                         │
                         ▼
       await analyzer task + result consumer task
                         │
                         ▼
       synthesize one adapter-level final result
```

The session actor owns the input continuation, analyzer task, result-consumer task, range accumulator, and cancellation token. On cancellation: finish the input continuation, call `cancelAndFinishNow()`, cancel the result task, await both tasks, clear continuations, and emit no final. No task may outlive its session actor.

`DictationTranscriber.Result` values are accumulated by audio time range. Volatile results replace overlapping volatile ranges; finalized ranges become immutable. Only after both analyzer and results streams finish does the adapter concatenate finalized ranges and emit exactly one `ASREvent.final`.

### 8.6 Downloadable model catalog

Users do not download arbitrary Python checkpoints. They download reviewed SwiftWhisper packages containing ONNX/ORT weights, tokenizers, and configuration known to work with the bundled runtime.

```swift
enum InferenceBackend: String, Codable, Sendable {
    case appleSpeech
    case sherpaONNX
}

struct ModelArtifact: Codable, Hashable, Sendable {
    let relativePath: String
    let remoteURL: URL
    let byteCount: Int64
    let sha256: String
}

struct ModelPackageID: Codable, Hashable, Sendable {
    let modelID: ASRModelID
    let version: String
    let runtimeABI: Int
}

struct InstalledModel: Identifiable, Codable, Sendable, Equatable {
    var id: ModelPackageID { packageID }
    let packageID: ModelPackageID
    let installDirectory: URL
    let installedAt: Date
    let verifiedAt: Date
    let descriptorDigest: String
    let isActive: Bool
}

struct HardwareRequirement: Codable, Sendable, Equatable {
    let minimumMemoryGB: Int
    let recommendedMemoryGB: Int
    let appleSiliconOnly: Bool
}

struct ModelDescriptor: Identifiable, Codable, Sendable, Equatable {
    var id: ModelPackageID { packageID }
    let packageID: ModelPackageID
    let family: ASRFamily
    let displayName: String
    let backend: InferenceBackend
    let languages: [String]
    let downloadBytes: Int64
    let installedBytes: Int64
    let artifacts: [ModelArtifact]
    let capabilities: ASRCapabilities
    let hardware: HardwareRequirement
    let licenseName: String
    let licenseURL: URL
    let sourceURL: URL
    let isExperimental: Bool
    let runtimeConfiguration: ModelRuntimeConfiguration
}

enum ModelRuntimeConfiguration: Codable, Sendable, Equatable {
    case whisper(WhisperPackageConfiguration)
    case moonshine(MoonshinePackageConfiguration)
    case qwen3ASR(Qwen3PackageConfiguration)
    case parakeet(ParakeetPackageConfiguration)
}

struct WhisperPackageConfiguration: Codable, Sendable, Equatable {
    let encoderPath: String
    let decoderPath: String
    let tokenPath: String
    let languageMode: String
}

struct MoonshinePackageConfiguration: Codable, Sendable, Equatable {
    let encoderPath: String
    let decoderPath: String
    let tokenPath: String
}

struct Qwen3PackageConfiguration: Codable, Sendable, Equatable {
    let convolutionFrontendPath: String
    let encoderPath: String
    let decoderPath: String
    let tokenizerDirectory: String
    let maximumInputTokens: Int
    let maximumOutputTokens: Int
}

struct ParakeetPackageConfiguration: Codable, Sendable, Equatable {
    let encoderPath: String
    let decoderPath: String
    let joinerPath: String
    let tokenPath: String
    let modelKind: String
}

enum ModelInstallState: Sendable, Equatable {
    case notInstalled
    case checkingDisk
    case downloading(completedBytes: Int64, totalBytes: Int64)
    case verifying
    case installing
    case installed(URL)
    case failed(ModelInstallError)
}

enum ModelInstallError: Error, Codable, Sendable, Equatable {
    case unsupportedHardware(reason: String)
    case insufficientDisk(requiredBytes: Int64, availableBytes: Int64)
    case networkUnavailable
    case redirectRejected(URL)
    case downloadFailed(path: String, reason: String)
    case checksumMismatch(path: String)
    case unsafePackage(path: String)
    case runtimeIncompatible(requiredABI: Int, availableABI: Int)
    case calibrationFailed(reason: String)
    case cancelled
}

protocol ModelCatalogProviding: Sendable {
    func availableModels() async throws -> [ModelDescriptor]
    func descriptor(for id: ModelPackageID) async throws -> ModelDescriptor
}

protocol ModelManaging: Sendable {
    func installedModels() async throws -> [InstalledModel]
    func activePackage(for modelID: ASRModelID) async -> ModelPackageID?
    func state(for id: ModelPackageID) async -> ModelInstallState
    func install(_ descriptor: ModelDescriptor) async
        -> AsyncThrowingStream<ModelInstallState, Error>
    func activate(_ id: ModelPackageID) async throws
    func rollback(modelID: ASRModelID) async throws
    func cancelInstallation(of id: ModelPackageID) async
    func remove(_ id: ModelPackageID) async throws
    func verify(_ id: ModelPackageID) async throws
}
```

Catalog requirements:

- Bundle a known-good catalog in the app.
- Catalog refresh is user-initiated in 1.0. Any remote catalog must have a monotonically increasing catalog version, an expiry time, and an Ed25519 signature verified with a pinned CryptoKit public key. Reject expired, replayed, or downgraded catalogs.
- Every artifact is downloaded to a staging directory, checked for expected byte length and SHA-256, then atomically moved into Application Support.
- Reject absolute paths, `..`, symlinks, unexpected files, and executable payloads.
- Compute peak disk use as current partials + new downloads + expanded/install bytes + the currently installed version retained for rollback + calibration scratch + `max(20%, 512 MB)`. Recheck before activation.
- Keep the prior verified package until the new version loads, passes calibration, activates, and completes one successful session; then it becomes rollback-eligible cleanup.
- Removing the active model is allowed only after another installed engine, or a permitted and installed Apple locale, has prepared successfully. Otherwise refuse removal and explain the required recovery step.

### 8.7 Initial supported catalog

The catalog should expose curated variants, not every upstream checkpoint.

| Family | Initial package | Positioning | Upstream license | Default status |
|---|---|---|---|---|
| Apple | System Dictation for selected locale | Best integration and lowest setup | Apple system asset | Default |
| Whisper | multilingual small package | Broad language support | MIT | Stable |
| Moonshine | tiny-en quantized package | Fast English dictation on lower-memory Macs | MIT | Stable |
| Qwen3-ASR | 0.6B int8 | Strong multilingual option, heavier than Moonshine | Apache-2.0 | Experimental until benchmark gate passes |
| Parakeet | TDT 0.6B v3 quantized | Fast, accurate supported-language dictation | CC-BY-4.0 | Experimental until benchmark gate passes |

The application must display download size, estimated memory, supported languages, license, and whether a model supports live partials before installation.

Use the Sherpa-ONNX Swift package and static macOS XCFramework as the single runtime for custom models. Current upstream Swift APIs cover Whisper, Moonshine, Qwen3-ASR, and transducer/NeMo configurations used by Parakeet. Wrap all upstream types inside `SherpaONNXEngine`; no feature code imports Sherpa-ONNX directly.

#### Reproducible package contract

Pin all three layers independently:

1. upstream checkpoint repository and immutable revision SHA;
2. conversion/export tool repository and immutable revision SHA;
3. Sherpa-ONNX release plus Swift wrapper runtime ABI.

The initial implementation baseline is Sherpa-ONNX `1.13.6`, ONNX Runtime `1.27.1`, and SwiftWhisper runtime ABI `1`. Upgrades require rebuilding and requalifying every package; do not allow the binary dependency to float.

Each package directory contains:

```text
<model-id>/<version>/
├── manifest.json              signed descriptor and runtime configuration
├── LICENSE
├── NOTICE                     attribution and conversion provenance
├── calibration/
│   ├── sample.wav
│   └── expected.json          required tokens + maximum token error
├── tokenizer/                 when required by the family
└── model files                exact names referenced by runtimeConfiguration
```

The repository must include a `ModelPackaging/` directory with one reproducible script and lock file per family. Each script downloads the pinned upstream revision, runs the pinned exporter, emits the documented ONNX opset and quantization, calculates file hashes, runs the calibration fixture through the pinned runtime, and produces the final manifest. CI rebuilds one reference package per family and compares tensor names, shapes, configuration, and golden output; byte-for-byte equality is preferred but not required when upstream tooling is nondeterministic.

Initial locked recipes:

| Family | Required runtime mapping | Required files |
|---|---|---|
| Whisper | Sherpa offline Whisper configuration | encoder ONNX, decoder ONNX, tokens, language/task metadata |
| Moonshine | Sherpa offline Moonshine configuration | preprocessor when required, encoder ORT/ONNX, cached or merged decoder, tokens |
| Qwen3-ASR | Sherpa offline Qwen3-ASR configuration | convolution frontend, encoder, decoder, tokenizer directory, generation limits |
| Parakeet | Sherpa offline transducer/NeMo configuration | encoder, decoder, joiner, tokens, decoding method |

Reference source bundles for runtime ABI 1:

| Family | Source bundle | Expected runtime files |
|---|---|---|
| Whisper | `sherpa-onnx-whisper-small.tar.bz2` from the Sherpa `asr-models` release; 639,387,718 bytes; SHA-256 `486a46afbb7ba798507190ffe02fea2dd726049af212e774537efac6afb210a6` | `small-encoder*.onnx`, `small-decoder*.onnx`, `small-tokens.txt` |
| Moonshine | `sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27.tar.bz2`; SHA-256 `9ec31b342d8fa3240c3b81b8f82e1cf7e3ac467c93ca5a999b741d5887164f8d` | `encoder_model.ort`, `decoder_model_merged.ort`, `tokens.txt` |
| Qwen3-ASR | `sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2`; SHA-256 `393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96` | `conv_frontend.onnx`, `encoder.int8.onnx`, `decoder.int8.onnx`, `tokenizer/` |
| Parakeet | `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2`; SHA-256 `5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf` | `encoder.int8.onnx`, `decoder.int8.onnx`, `joiner.int8.onnx`, `tokens.txt` |

The package build pipeline extracts these source bundles in CI, rejects undeclared paths, records exact extracted-file SHA-256 values, reads each ONNX graph to record opset/tensor names/shapes, and republishes individual immutable files to the SwiftWhisper allowlisted model origin. Runtime downloads never unpack upstream archives. A manifest with a missing digest cannot ship.

All initial custom packages run as non-streaming utterance decoders even if the upstream runtime offers simulated streaming. Apple Dictation alone supplies live partial text in 1.0; custom models show the waveform while recording and progress after release. This gives every family one identical, testable session contract.

The first implementing agent must preserve the generated manifest's exact filenames, tensor names, opset, quantization mode, and conversion/source command output. A family is not “supported” merely because its configuration type exists in Sherpa-ONNX.

### 8.8 Text processing and delivery

```swift
struct FinalTranscript: Sendable, Equatable {
    let text: String
    let segments: [TranscriptSegment]
    let modelID: ASRModelID
    let locale: Locale
    let audioDuration: Duration
}

protocol TextPostProcessing: Sendable {
    func process(_ transcript: FinalTranscript) async -> FinalTranscript
}

struct FocusSnapshot: @unchecked Sendable {
    let frontmostApplicationPID: pid_t?
    let bundleIdentifier: String?
    let focusedElement: AXUIElement?
    let capturedAt: ContinuousClock.Instant
}

enum DeliveryMethod: String, Codable, Sendable {
    case accessibilitySelectedText
    case unicodeKeyEvents
    case clipboardPaste
    case historyOnly
}

enum DeliveryVerification: String, Codable, Sendable {
    case verified
    case acceptedUnverified
    case failed
}

struct DeliveryResult: Sendable, Equatable {
    let method: DeliveryMethod
    let verification: DeliveryVerification
    let destinationBundleIdentifier: String?
    let userMessage: String?
}

protocol FocusedTextDelivering: Sendable {
    func snapshotFocus() async -> FocusSnapshot
    func deliver(_ text: String, preferredTarget: FocusSnapshot?) async -> DeliveryResult
}
```

Deterministic post-processing only:

1. Normalize Unicode to NFC.
2. Convert model-specific whitespace tokens to ordinary spaces/newlines.
3. Collapse unintended repeated spaces without collapsing intentional newlines.
4. Trim leading/trailing whitespace.
5. Do not invent words, rewrite style, or silently remove profanity.

Delivery fallback chain:

```text
final text
   │
   ├─ original focused element is still focused, editable, and positively nonsecure
   │      └─ set AX selected text ──success──▶ done
   │
   ├─ same positively identified nonsecure target accepts Unicode key events
   │      └─ emit bounded Unicode chunks ────▶ accepted, not generally verifiable
   │
   ├─ clipboard fallback explicitly enabled and snapshot is lossless
   │      └─ materialize and save every pasteboard item/type
   │         write text
   │         synthesize Command-V
   │         wait bounded compatibility delay
   │         restore snapshot only if changeCount is still ours
   │
   └─ otherwise ─────────────────────────────▶ historyOnly
```

Before every delivery attempt, reacquire the focused element and require all of the following: the original process is still frontmost, the focused element is equivalent to the original target, its role/subrole is editable and not secure, the intended attribute/action is supported, and system secure-input state does not make the operation unsafe. If any condition is unknown or false, save to history. Never “try and see” with an unidentified target.

If focus changed, show `Saved to History — focus changed` with an explicit `Insert Here` action. That action takes a fresh snapshot and performs the same nonsecure-target checks. Automatic insertion into a different application is not allowed in 1.0.

Clipboard restoration is best-effort, not lossless by definition. It is disabled by default. Before using it, materialize all pasteboard representations; if any promised or unsupported item cannot be copied, skip this method. If another process changes the clipboard after SwiftWhisper writes to it, never overwrite the newer content.

### 8.9 History

Use Core Data with its default SQLite persistent store. It is native, migration-capable, and adequate for tens of thousands of short text records.

```swift
enum DeliveryOutcome: String, Codable, Sendable {
    case pendingDelivery
    case verifiedInserted
    case acceptedUnverified
    case savedNoFocusedField
    case savedInjectionFailed
}

enum HistoryCapturePolicy: String, Codable, Sendable {
    case allSuccessful
    case fallbackOnly
}

enum HistoryRetention: Codable, Sendable, Equatable {
    case days(Int)
    case forever
}

struct HistoryRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
    let normalizedSearchText: String
    let modelID: ASRModelID
    let localeIdentifier: String
    let audioDuration: Duration
    let processingDuration: Duration
    let sourceApplicationBundleID: String?
    let sourceApplicationName: String?
    let deliveryOutcome: DeliveryOutcome
}

protocol HistoryRepository: Sendable {
    func save(_ record: HistoryRecord) async throws
    func updateDeliveryOutcome(id: UUID, outcome: DeliveryOutcome) async throws
    func search(query: String, limit: Int, offset: Int) async throws -> [HistoryRecord]
    func record(id: UUID) async throws -> HistoryRecord?
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func count() async throws -> Int
}

protocol TranscriptRecoveryStoring: Sendable {
    func persistPending(_ transcript: FinalTranscript, recordID: UUID) async throws
    func markRecovered(recordID: UUID) async throws
    func pendingRecoveries() async throws -> [(UUID, FinalTranscript)]
}
```

Persist metadata and transcript text, never raw audio. Search uses a folded, lowercased `normalizedSearchText` column and indexed date/model/application columns. Limit result pages to 100 records. The default policy stores every nonempty successful transcript forever; users may switch to fallback-only and choose a 7-, 30-, or 90-day retention period.

Before insertion, atomically write a compact pending recovery file with restrictive permissions and exclude it from backups. Then create the Core Data row with `.pendingDelivery`, attempt delivery, update the row, and delete the recovery file. At startup, import any pending recovery files into History before accepting a new session.

Under `.fallbackOnly`, delete the Core Data row only after a verified AX insertion. Retain accepted-but-unverified deliveries because the application cannot prove the target consumed the text. Under `.allSuccessful`, retain every nonempty final transcript.

Run retention pruning at launch and once per local calendar day while the app remains open. Never prune `.pendingDelivery`, unresolved recovery files, or records whose delivery is unverified until they exceed the user's explicit retention period.

If Core Data is unavailable, keep the recovery file. If delivery also fails, show a persistent confirmation sheet containing selectable text plus `Copy` and `Save As…`; do not auto-dismiss it. A successful transcript therefore survives process termination even when both ordinary delivery and Core Data fail.

### 8.10 Coordinator and reducer

```swift
enum DictationState: Sendable, Equatable {
    case idle
    case arming(ArmingSession)
    case listening(SessionSnapshot)
    case finalizing(SessionSnapshot)
    case transcribing(SessionSnapshot, progress: Double?)
    case postProcessing(SessionSnapshot)
    case persisting(SessionSnapshot, FinalTranscript)
    case delivering(session: SessionSnapshot, recordID: UUID?, transcript: FinalTranscript)
    case confirmation(ConfirmationState)
    case cancelling(SessionID)
    case failed(FailureState)
}

struct SessionID: RawRepresentable, Hashable, Sendable, Codable {
    let rawValue: UUID
}

struct SessionSnapshot: Sendable, Equatable {
    let id: SessionID
    let startedAt: ContinuousClock.Instant
    let modelID: ASRModelID
    let localeIdentifier: String
    let sourceApplicationBundleID: String?
    let partialText: String
}

struct ArmingSession: Sendable, Equatable {
    let snapshot: SessionSnapshot
    var captureStarted: Bool
    var captureStopped: Bool
    var engineReady: Bool
    var releasedAt: ContinuousClock.Instant?
}

struct ConfirmationState: Sendable, Equatable {
    let sessionID: SessionID
    let recordID: UUID?
    let transcript: FinalTranscript
    let delivery: DeliveryResult
    let mayAutoDismiss: Bool
}

struct FailureState: Sendable, Equatable {
    let sessionID: SessionID?
    let failure: DictationFailure
    let recoverableTranscript: FinalTranscript?
}

enum DictationAction: Sendable, Equatable {
    case wakePressed(at: ContinuousClock.Instant)
    case wakeReleased(at: ContinuousClock.Instant)
    case engineReady(SessionID)
    case captureStarted(SessionID)
    case captureStopped(SessionID)
    case recognitionFinalizationStarted(SessionID, progressSupported: Bool)
    case audioLevel(SessionID, AudioLevel)
    case partialTranscript(SessionID, String)
    case transcriptionProgress(SessionID, Double)
    case finalTranscript(SessionID, FinalTranscript)
    case postProcessingCompleted(SessionID, FinalTranscript)
    case recoveryPersisted(SessionID, recordID: UUID)
    case recoveryPersistenceFailed(SessionID, transcript: FinalTranscript)
    case pendingRecordPersisted(SessionID, recordID: UUID)
    case historyPersistenceFailed(SessionID, transcript: FinalTranscript)
    case deliveryCompleted(SessionID, DeliveryResult)
    case historyOutcomeUpdated(SessionID)
    case historyOutcomeUpdateFailed(SessionID)
    case cancelRequested(at: ContinuousClock.Instant)
    case maximumDurationElapsed(SessionID)
    case failed(SessionID?, DictationFailure)
    case confirmationExpired(SessionID)
    case recoveryRequested
    case cleanupCompleted(SessionID)
}

enum DictationEffect: Sendable, Equatable {
    case prepareSession(SessionSnapshot)
    case startCapture(SessionID)
    case finishCapture(SessionID)
    case finalizeRecognition(SessionID)
    case postProcess(SessionID, FinalTranscript)
    case persistPending(SessionID, FinalTranscript)
    case cancelSession(SessionID)
    case deliver(SessionID, recordID: UUID?, transcript: FinalTranscript)
    case updateHistory(SessionID, recordID: UUID, DeliveryResult)
    case scheduleMaximumDuration(SessionID, after: Duration)
    case showPersistentRecovery(SessionID, FinalTranscript)
    case cleanup(SessionID)
    case showOverlay
    case hideOverlay(after: Duration)
}

protocol DictationReducing {
    static func reduce(
        state: inout DictationState,
        action: DictationAction
    ) -> [DictationEffect]
}

@MainActor
protocol DictationCoordinating: AnyObject {
    var state: DictationState { get }
    func send(_ action: DictationAction)
}
```

All callbacks carry `SessionID`. Late results from cancelled or superseded sessions are ignored. This prevents a slow model from injecting stale text.

Required reducer behavior:

| Current state | Action | Next state / effect |
|---|---|---|
| idle | wakePressed(t) | snapshot settings/focus/model/device; arming; start native-format capture and prepare engine concurrently |
| arming | captureStarted | mark capture ready and buffer frames immediately; leave arming only after engine readiness is also known |
| arming | wakeReleased(t) before 120 ms | cancelling; cancel and cleanup |
| arming | wakeReleased(t) after 120 ms | remember release and stop capture; retain buffered audio until the engine is ready |
| arming | engineReady | mark engine ready; leave arming only when capture has started, then convert/drain buffered frames; enter listening if key remains down, otherwise wait for capture stop and finalize |
| arming | captureStopped with release recorded | mark capture stopped; wait for engine if needed, otherwise drain buffered audio, close ASR input, and finalize |
| arming/listening | audioLevel | update waveform only; never use level as speech truth |
| listening | wakeReleased | finalizing; stop capture; close ASR input; finalize recognition |
| listening | captureStopped | close ASR input and finalize recognition |
| listening | maximumDurationElapsed | finalizing with warning; same successful forced-finish path as key release |
| listening | cancelRequested | cancelling; stop audio, cancel ASR, remove temporary audio |
| finalizing | recognitionFinalizationStarted(progressSupported) | enter transcribing when the engine begins post-capture decode; otherwise remain finalizing |
| listening/finalizing/transcribing | partialTranscript | replace the session's volatile partial text for display |
| finalizing/transcribing | audioLevel | ignore after the capture-stop acknowledgement |
| finalizing/transcribing | transcriptionProgress | enter/remain in transcribing and update progress |
| finalizing/transcribing | finalTranscript | postProcessing; run deterministic processor |
| postProcessing | postProcessingCompleted | persisting; write pending recovery file before any other side effect |
| persisting | recoveryPersisted | create `.pendingDelivery` Core Data record |
| persisting | recoveryPersistenceFailed | do not auto-deliver; show persistent selectable transcript with Copy and Save As |
| persisting | pendingRecordPersisted | delivering; attempt delivery |
| persisting | historyPersistenceFailed | delivery may proceed because recovery is durable; retain recovery until history succeeds later |
| delivering | deliveryCompleted | update history if possible; confirmation contains the full transcript |
| delivering/confirmation | historyOutcomeUpdated | delete recovery file; apply history policy |
| delivering/confirmation | historyOutcomeUpdateFailed | retain recovery file and show non-auto-dismissing warning |
| confirmation | confirmationExpired | cleanup; idle only when `mayAutoDismiss` is true |
| confirmation/failed | recoveryRequested | retry recovery/history or perform explicit Insert Here using the retained transcript |
| cancelling/confirmation/failed | cleanupCompleted | idle only when no recoverable text still requires user action |
| failed | recoveryRequested | retry persistence/delivery from `recoverableTranscript` without re-running ASR |
| cancelling | cleanupCompleted | idle |
| any active state | failed/cancelRequested | retain recoverable final text when present; cancel all owned tasks; cleanup; then confirmation or idle |

`maximumDurationElapsed` is a successful forced finish, not a transcription failure. `wakeReleased` timestamps are compared with the original press timestamp, so the 120 ms rule remains deterministic under delayed callbacks.

Any state/action pair not listed above is deliberately ignored after checking its `SessionID`. Reducer tests must contain a generated matrix proving that every declared action in every state either performs the documented transition or is explicitly ignored.

## 9. Concurrency and resource ownership

- `DictationCoordinator`: `@MainActor`; owns UI-visible state and effect orchestration.
- `AudioCaptureService`: actor; sole owner of `AVAudioEngine`.
- Each engine/session: actor-backed; serializes decoder access.
- `ModelDownloadManager`: actor; maximum two downloads, maximum one installation/verification operation.
- `HistoryRepository`: actor or private Core Data queue; never exposes managed objects.
- `GlobalHotKeyMonitor`: actor controlling the event-tap run-loop source.
- `FocusedTextDeliveryService`: actor because pasteboard and synthesized event sequences must not overlap.

Cancellation must propagate from coordinator to audio, ASR, overlay, and temporary-file cleanup. Detached tasks are prohibited for session work.

### Active-session mutation policy

Snapshot the selected model package, locale, microphone device, wake binding, history policy, and delivery settings at `wakePressed`. Changes made in Settings apply only to the next session.

- Model download completion during a session: install in the background, never switch the active session.
- Model selection during a session: queue for next session.
- Microphone selection during a session: queue for next session; physical device loss fails the current session.
- Pause: reject new sessions; an active listening session finalizes on key release.
- Quit: if listening, ask once whether to finish or discard; if already finalizing with a nonempty transcript, finish persistence before termination.
- Sleep/logout: cancel capture, close and remove temporary audio, persist any already-final transcript, and reset physical-key state.
- Memory pressure: never unload the active session's model; unload inactive/prewarmed models immediately.

### Backpressure

There are two different buffers and they must not be conflated:

1. The real-time callback queue holds at most 250 ms of copied audio while an async consumer transfers frames. Overflow means the process cannot keep up: record a diagnostic, fail visibly, and never return silently corrupted text.
2. The arming/pre-roll store belongs to the async consumer. It keeps up to two seconds in memory while the engine prepares, then appends further frames to the protected temporary session file. It may grow until the ten-minute session limit, subject to disk-space checks.

Tests independently force callback-queue overflow and pre-roll spill-to-disk so neither path is accidentally implemented as the other.

## 10. Persistence and file locations

```text
~/Library/Application Support/SwiftWhisper/
├── History.sqlite
├── Models/
│   └── <model-id>/<version>/abi-<runtime-abi>/<verified artifacts>
└── Diagnostics/
    └── local rotating logs without transcript/audio content

~/Library/Caches/SwiftWhisper/
├── Downloads/<model-id>/<version>/abi-<runtime-abi>/*.partial
└── Sessions/<session-id>.caf
```

Session audio may be spooled to a temporary PCM/C AF file for non-streaming engines. It is removed immediately after finalization or cancellation. On startup, delete orphan session files older than one hour and stale partial downloads older than seven days, except resumable downloads with valid metadata.

Create temporary session files with owner-only permissions and exclude them from Time Machine and metadata indexing. They benefit from FileVault when the user has enabled it, but the app must not claim independent encryption. Close and unlink them on success, failure, cancellation, sleep, logout, and orderly termination. Onboarding Privacy copy must say that some downloaded models temporarily buffer audio on local disk while processing; “not retained” must not be presented as “never written.”

UserDefaults stores non-sensitive settings such as wake binding, selected model ID, locale, sounds, and onboarding completion. Do not store transcripts in UserDefaults.

## 11. Model lifecycle

### Installation

```text
select model
   │
   ▼
compatibility check ──fail──▶ explain RAM/OS/language constraint
   │
   ▼
disk-space reservation ─fail▶ offer model-location cleanup
   │
   ▼
download files ──cancel/interruption──▶ keep resumable partials
   │
   ▼
SHA-256 verification ─fail──▶ delete staged file + retry
   │
   ▼
runtime smoke test ─fail────▶ quarantine package + keep prior model
   │
   ▼
atomic activation ──────────▶ installed
```

Runtime calibration test: verify all declared files and runtime metadata, load the model, decode a licensed package-specific multi-second clip, require its expected tokens or bounded token-error score, unload, reload, and decode again. A newly installed model is not selectable until both passes succeed.

### Loading and eviction

- Keep only the selected custom model loaded.
- Prewarm after selection and optionally at app launch if memory allows.
- Unload after 10 idle minutes or immediately on memory pressure.
- Apple engine uses `.lingering` retention.
- On serious thermal pressure, stop prewarming and warn before starting the largest models.

### Compatibility tiers

- 8 GB: Apple, Moonshine Tiny, small Whisper models.
- 16 GB: all above plus Qwen3-ASR 0.6B and quantized Parakeet 0.6B.
- 24+ GB: large-v3-turbo and higher-quality variants.

These are catalog policy defaults, not hardcoded engine assumptions. Benchmark data may tighten them.

## 12. Privacy, security, and distribution

### Privacy guarantees

- No analytics SDK.
- No crash-reporting SDK in 1.0.
- No cloud ASR.
- No transcript-bearing logs.
- No raw audio history.
- No network request from ASR engines.
- Model and catalog downloads are user-initiated and disclose normal HTTP metadata plus the selected artifact to the hosting provider; audio and transcripts are never included.

Settings > Privacy must show the exact guarantees and a live list of installed models and disk use.

### Model supply-chain controls

- HTTPS only.
- Pinned signed catalog.
- SHA-256 per file.
- Atomic install directories.
- No executable model-package content.
- Preserve third-party licenses and attribution.
- Include a machine-readable software bill of materials in release artifacts.

All network access goes through a single `DownloadTransport` built from an ephemeral `URLSessionConfiguration`: no cookies, credential storage, shared cache, analytics headers, or background catalog refresh. The transport allowlists HTTPS hosts from the signed bundled catalog, rejects redirects to non-allowlisted hosts, and is not injected into any ASR engine. Pause model downloads while dictation is active so privacy tests can assert that no SwiftWhisper-owned network request occurs during capture or transcription.

### Distribution

Ship outside the Mac App Store for v1. Sign with Developer ID, enable hardened runtime, notarize, and staple the ticket. Keep App Sandbox disabled because robust global input observation and cross-application Accessibility insertion are core features. Request only microphone/audio-input entitlements actually required by the final signing configuration.

`LSUIElement = true` hides the Dock icon. Settings and History still open as ordinary windows.

## 13. Error model

```swift
enum DictationFailure: Error, Sendable, Equatable {
    case permissionMissing(PermissionKind)
    case microphoneUnavailable
    case audioDeviceChanged
    case audioBufferOverrun
    case noSpeechDetected
    case modelNotInstalled(ASRModelID)
    case modelIncompatible(ASRModelID, reason: String)
    case modelLoadFailed(ASRModelID, reason: String)
    case transcriptionFailed(reason: String)
    case transcriptEmpty
    case insertionUnavailable
    case insertionFailed(reason: String)
    case historyWriteFailed
    case cancelled
}
```

User-facing copy should be concrete and recoverable:

- `Microphone access is off — Open System Settings`
- `Right Option isn't visible to SwiftWhisper — Enable Input Monitoring`
- `Text couldn't be inserted. It was saved to History.`
- `This model needs about 16 GB of memory — Choose a smaller model`
- `The model download was damaged and was removed — Retry`

Do not surface raw framework error descriptions as primary UI copy. Preserve them in privacy-safe local diagnostics.

## 14. Failure-mode audit

| Code path | Real failure | Required handling | Required test | User experience |
|---|---|---|---|---|
| Event tap | macOS disables a slow tap | Re-enable and rebuild source | Unit adapter + integration soak | Brief unavailable indicator only if recovery fails |
| Modifier state | App misses key-up or loses physical state | Cancel immediately when tap/sleep/device events make state unknowable; ten-minute cap remains a final backstop | Exhaustive event-sequence tests | Clear cancellation, never a hidden ten-minute recording |
| Microphone | Device unplugged mid-session | Stop capture and cancel engine safely | Fake-device integration test | Clear device-changed error |
| Audio conversion | Unsupported format | Query engine requirement and fail before listening | Unit conversion matrix | Choose another device/model |
| Audio buffering | Decoder cannot drain | Bounded buffer, explicit overrun failure | Stress test | No silently corrupted transcript |
| Apple asset | Locale asset missing | Install through `AssetInventory` | Mocked asset manager | Progress and retry |
| Model download | Network interruption | Resume from valid partial metadata | URLProtocol integration test | Paused/retry state |
| Model verification | SHA mismatch | Delete staged artifact, preserve installed version | Corrupt fixture test | “Download damaged” |
| Model switch | Old decoder returns late | Session-ID gate; unload only after cancellation | Race test | No stale insertion |
| Transcription | Empty/invalid output | Treat as recoverable failure | Golden empty-audio test | “No speech detected” |
| Focus | Target closes or changes during decode | Require original PID/element equivalence; never restore or use a new target automatically | AX harness test | Save to History with Insert Here action |
| Secure input | Password field focused | Refuse insertion | AX harness secure-field test | Save to History with explanation |
| Clipboard fallback | Lazy data cannot be snapshotted or user copies concurrently | Skip unless snapshot is materialized; restore after bounded delay only if changeCount remains ours | Pasteboard race/asynchronous-paste tests | Preserve newer clipboard; history remains canonical |
| History | Persistent store unavailable | Continue insertion; expose history warning | Repository failure test | Text inserted, warning shown |
| App termination | Crash leaves temp audio | Startup scavenger deletes stale files | File cleanup test | Silent safe cleanup |

No row may ship with a silent failure and without both error handling and a test.

## 15. Test strategy

Use Swift Testing for domain and service tests, XCTest for UI/Accessibility harness tests, and `XCTMetric` performance tests.

Split test execution into three explicit tiers:

1. Ordinary CI: pure reducer, service fakes, model-manifest security, audio fixtures, repository, and URLProtocol tests. No real TCC prompts.
2. Signed integration runner: a stable signing identity on a dedicated Mac whose microphone, Input Monitoring, and Accessibility grants are pre-provisioned for the exact app and harness bundle IDs.
3. Manual clean-account release check: exercises real first-run TCC prompts, System Settings round-trips, Fn hardware behavior, notarization, sleep/wake, and clean uninstall/reinstall. These OS-owned flows are explicitly exempt from ordinary automated CI.

### 15.1 Coverage diagram

```text
Wake-key flow
├── right Option down/up                              [unit + integration]
├── Fn down/up                                        [unit + hardware manual]
├── left + right Option overlap                       [unit]
├── chord main-key-first/release-order rejection      [unit]
├── duplicate flagsChanged                           [unit]
├── tap disable/sleep/device-loss state reset         [unit + integration]
├── Escape cancellation                              [unit + UI]
└── event tap disabled/re-enabled                     [integration]

Permission flow
├── each permission notDetermined → granted          [unit adapter]
├── denied → Settings → granted                      [UI/manual]
├── partial permission combinations                  [table-driven unit]
└── revocation while running                         [integration]

Audio flow
├── hardware format → required format                [unit fixtures]
├── device change                                    [integration]
├── buffer overrun                                   [stress]
├── no speech                                        [golden audio]
└── 10-minute limit                                  [clock-controlled unit]

ASR flow, for every engine
├── prepare/load                                     [integration]
├── short speech → final text                        [golden audio]
├── partial updates where supported                  [integration]
├── empty audio                                      [integration]
├── cancellation                                     [race test]
├── punctuation and Unicode                         [golden audio]
├── supported-language sample                        [WER threshold]
└── unload/reload                                    [soak]

Delivery flow
├── native text field selected text                  [AX harness]
├── native text view insertion                       [AX harness]
├── browser-like contenteditable                     [AX/WebKit harness]
├── non-editable focused element                     [AX harness]
├── secure field                                     [AX harness]
├── focus changes during transcription               [AX harness]
├── Unicode event fallback                           [integration]
└── clipboard race and restoration                   [integration]

History flow
├── save inserted and fallback records               [unit/integration]
├── folded search                                    [unit]
├── pagination                                       [unit]
├── delete one/all                                   [unit]
├── migration                                        [integration]
└── store failure does not block insertion           [coordinator test]

Model flow
├── catalog signature                                [unit]
├── disk-space rejection                             [unit]
├── resume download                                  [URLProtocol integration]
├── checksum mismatch                                [integration]
├── path traversal/symlink rejection                 [security unit]
├── smoke-test failure preserves previous model      [integration]
└── removal of active model falls back to Apple      [coordinator test]
```

### 15.2 ASR golden corpus

Commit a small, redistributable test corpus with:

- silence;
- short English phrase;
- punctuation-heavy phrase;
- numbers and dates;
- accented proper nouns;
- one sample per claimed non-English language tier;
- background-noise sample;
- clipped microphone sample.

Do not assert exact text across Apple OS updates. Use normalized token error thresholds and required-keyword assertions. Pin exact expected output only for versioned downloadable models.

### 15.3 Performance gates

The release reference machine is an M1 MacBook Air with 8 GB RAM on the minimum supported macOS 26.x release, connected to power, Low Power Mode off, thermal state nominal, and no model downloads running. Use the same committed 30-second English fixture for model comparisons. Report cold and warm runs separately after 3 warm-ups and 20 measured runs, with p50 and p95 rather than an unspecified median.

Measure:

- hotkey-to-overlay latency;
- hotkey-to-audio-first-frame latency;
- real-time factor for each model;
- peak resident memory while loaded and while transcribing;
- cold and warm model-load time;
- insertion latency for 10, 1,000, and 10,000 characters;
- a fast 1,000-session synthetic-engine soak in ordinary CI;
- a nightly 100-session real-engine soak for every stable model and 25-session soak for experimental models.

A catalog model cannot graduate from Experimental unless its recommended hardware achieves real-time factor below 1.0 for 30-second speech and completes the soak without unbounded memory growth.

## 16. Implementation sequence

Each milestone ends with green tests and a runnable application. Do not build all infrastructure before proving the user loop.

### Milestone 0 — Foundation

- Create macOS 26 SwiftUI/AppKit project.
- Configure accessory app behavior, signing, privacy manifest, usage strings, and test targets.
- Implement domain types, reducer, dependency container, and fake services.
- Implement the static overlay with all states in previews.

Exit: reducer tests cover every legal and illegal transition.

### Milestone 1 — Apple end-to-end vertical slice

- Permission onboarding.
- Right Option and Fn event monitoring.
- AVAudioEngine capture.
- Apple speech asset manager.
- `AppleSpeechEngine` with progressive dictation.
- Direct AX insertion and history fallback.
- Core Data history window.
- Notch Capsule animation.

Exit: on a clean macOS account, onboarding leads to successful dictation into TextEdit and history fallback when Finder is focused.

### Milestone 2 — Harden text delivery

- Unicode event and clipboard fallback chain.
- Focus-change handling.
- Secure-field detection.
- Injection Harness application and automated AX scenarios.
- Failure copy and retry actions.

Exit: supported target matrix passes and clipboard race tests never clobber newer user content.

### Milestone 3 — Model manager

- Bundled signed catalog format.
- Download, resume, verification, atomic install, removal, disk checks.
- Model UI and license views.
- Engine selection and fallback behavior.

Exit: corrupt and interrupted downloads cannot become selectable.

### Milestone 4 — Shared Sherpa-ONNX engine and public beta

- Add pinned Sherpa-ONNX package/XCFramework.
- Implement one wrapper and configuration builders per family.
- Add Whisper packages and golden tests.
- Add Moonshine packages and golden tests.
- Add Qwen3-ASR 0.6B int8 package and tests.
- Add Parakeet TDT 0.6B v3 quantized package and tests.

Exit: every requested model family installs, passes smoke test, transcribes the golden corpus, and can be removed without destabilizing the Apple default.

### Milestone 5 — Reliability and release

- Performance gates and thermal/memory behavior.
- Permission revocation tests.
- Synthetic 1,000-session CI soak plus the nightly real-engine soak defined in section 15.3.
- VoiceOver, keyboard navigation, Reduce Motion, contrast checks.
- Notarized clean-machine installation test.
- Third-party notices and SBOM.

Exit: all acceptance criteria in section 17 pass. The product may be called 1.0 only here; earlier builds carrying experimental Qwen3-ASR or Parakeet packages are beta releases.

## 17. Release acceptance criteria

### Core behavior

- Right Option is the fresh-install default and distinguishes left from right.
- Fn can be selected and passes the onboarding test on supported keyboards.
- Press starts capture and release finalizes in every permission mode.
- With Accessibility trust, Escape cancels and is suppressed only during active listening; without it, Escape cancellation is disabled and all Escape events pass through.
- The app never activates or steals focus during ordinary dictation.
- Apple Dictation is selected by default and functions without internet after its locale asset is installed.
- Whisper, Moonshine, Qwen3-ASR, and Parakeet each have at least one downloadable, verified package.
- Successful final text is inserted or saved locally; it is never silently discarded.

### UX

- The Notch Capsule works on notched, non-notched, external, full-screen, and multi-display configurations.
- Every loading, empty, error, success, and partial state in section 5.6 exists.
- Reduce Motion and VoiceOver are supported.
- Status-bar, History, Settings, and onboarding are fully keyboard navigable.

### Privacy and safety

- With download transport placed in deny/fail mode and all downloads paused, instrumentation shows no SwiftWhisper-originated network request during capture or transcription; OS-owned asset services are reported separately by process.
- Temporary audio is removed after success, failure, cancellation, crash recovery, and reboot recovery.
- Model files cannot escape their staging/install directories.
- Clipboard fallback passes concurrent-change tests.
- Secure fields never receive generated text.

### Quality

- 100% branch coverage for the reducer and model-install state machine.
- Every failure-mode row has a test in the documented CI, signed-integration, or manual clean-account tier.
- No critical Swift concurrency warnings under strict concurrency checking.
- No unbounded memory growth in the soak test.

## 18. What already exists and should be reused

- Apple Speech framework: `SpeechAnalyzer`, `DictationTranscriber`, `AssetInventory`, progressive/final results, timing, confidence, and asset installation.
- AVFoundation: microphone capture and format conversion.
- ApplicationServices Accessibility API: focused-element discovery and direct text manipulation.
- Core Graphics event taps: global physical-key observation and fallback input events.
- ServiceManagement: optional launch at login.
- Core Data: local history persistence and migration.
- CryptoKit: SHA-256 and signed catalog verification.
- Sherpa-ONNX: one Swift-callable offline inference runtime covering the four requested non-Apple model families.

Do not build custom audio drivers, a custom database, a bespoke archive format, four unrelated inference runtimes, or a private-API notch integration.

## 19. Explicitly not in scope

- App Store submission: direct distribution is chosen for reliable global-control behavior.
- Arbitrary model import: reviewed packages are required for security and compatibility.
- XPC inference isolation: defer until crash data demonstrates a need.
- Cloud sync or iCloud history: conflicts with the simple local-only promise.
- AI rewriting: a separate future feature with a separate privacy decision.
- Continuous dictation: v1 is push-to-talk with a ten-minute ceiling.
- Audio history: transcripts only.
- Pixel-perfect imitation of another product's proprietary overlay.

## 20. Risks and mitigations

### Highest risk: text insertion across arbitrary applications

Accessibility implementations differ across AppKit, Electron, browsers, Java, terminals, and custom editors. Mitigate with a delivery strategy chain, a dedicated harness, an application compatibility matrix, and guaranteed history fallback.

### High risk: Fn reliability

Fn/Globe can be intercepted by system behavior and varies by keyboard. Keep Right Option as default, test during onboarding, and make a conventional chord available.

### High risk: downloadable model packaging

Upstream Python checkpoints are not drop-in macOS assets. SwiftWhisper must own versioned converted packages, checksums, runtime compatibility, and licenses. The UI must never imply any random model repository will work.

### Medium risk: custom runtime size and notarization

ONNX Runtime and model assets increase download size and signing complexity. Keep the app binary separate from optional models, pin dependencies, and validate notarization early.

### Medium risk: Apple speech output changes by OS release

Avoid exact-string Apple tests. Use behavioral thresholds, and keep Apple behind the same engine contract as pinned models.

### Medium risk: apparent “Dynamic Island” promise

Market it as a notch-aware capsule, not an OS-integrated Dynamic Island. Always support a top-center fallback.

## 21. Recommended first implementation task

Build a throwaway but production-shaped vertical spike containing only:

1. the reducer;
2. right Option down/up monitoring;
3. microphone capture;
4. Apple `DictationTranscriber` for one installed locale;
5. a plain top-center `NSPanel`;
6. insertion into TextEdit through Accessibility;
7. history fallback in memory.

The spike succeeds only when the same captured session can be proven to insert into TextEdit and save instead when Finder is focused. Then replace the in-memory history with Core Data and continue through the milestones. This validates the three hardest platform boundaries before visual polish or model downloads.

### Product assignment before committing to the full roadmap

Use macOS Dictation, Whisper Flow, and Superwhisper for the same 20 real dictations across five target applications. Record activation friction, first-feedback latency, finalization latency, insertion failures, recovery behavior, and privacy/model controls. The implementation should proceed only if SwiftWhisper's proposed wedge can beat at least two of those products on a behavior the target user notices every day.

## 22. Research notes and provenance

Verified locally on macOS 26.6.1 with the macOS 26 SDK and Swift 6.3.3:

- `SpeechAnalyzer`, `DictationTranscriber`, `SpeechTranscriber`, `AssetInventory`, and `AssetInstallationRequest` are declared macOS 26+.
- `DictationTranscriber` exposes progressive long-dictation presets, punctuation, emoji, etiquette replacement, volatile results, alternatives, timing, and confidence.
- `AssetInventory` exposes supported/installing/installed status, installation requests, and locale reservation.
- All Swift interface blocks in this document were concatenated and passed through `swiftc -typecheck` successfully with Swift 6.3.3.

Model metadata checked on 2026-08-26:

- OpenAI Whisper large-v3-turbo revision `41f01f3fe87f28c78e2fbf8b568835947dd65ed9`: MIT; upstream FP16 checkpoint approximately 1.62 GB.
- Moonshine Tiny revision `390624ed33d594443aa4aa221f5b9f283b545b5a` and Base revision `7a73d8d55ac0ba2ef3ae761593f6784b51f96dcf`: MIT; upstream weights approximately 108 MB/246 MB; English-focused upstream packages.
- Qwen3-ASR 0.6B revision `5eb144179a02acc5e5ba31e748d22b0cf3e303b0`: Apache-2.0; upstream BF16 weights approximately 1.88 GB. The 1.7B family exists but is not an initial package.
- NVIDIA Parakeet TDT 0.6B v3 revision `541d1f99c6b0c3cd0b11a95167540bb8edefd82b`: CC-BY-4.0; upstream FP32 weights approximately 2.51 GB, with a roughly 714 MB Q8 GGUF artifact also published upstream.

Sherpa-ONNX repository revision inspected: `34eba5a27220026b5981b633981c53205515067d` (2026-08-25). Its Swift package supports macOS, and its current Swift/C API contains configurations or examples for Whisper, Moonshine, Qwen3-ASR, and Parakeet-compatible transducer/NeMo models. Pin a reviewed release rather than tracking the repository head.

## 23. Handoff instructions for the implementing agent

1. Treat this document as the product source of truth.
2. Start with Milestone 0 and do not scaffold all later adapters prematurely.
3. Preserve the typed interfaces unless a compile-time limitation requires a documented change.
4. Add tests with each state and service; do not defer the test matrix.
5. Use only public macOS APIs.
6. Keep all content processing local and deterministic.
7. When an integration is uncertain, build the smallest executable spike and record the result in an Architecture Decision Record before changing this design.
8. Never allow a transcript to disappear silently: insert it, save it, or show an explicit failure with recoverable text.

## 24. Review record

This specification went through three independent adversarial passes. The review initially found compile-time interface gaps, an incomplete reducer, underspecified Apple Speech lifecycle, unsafe focus/secure-field behavior, non-durable delivery ordering, model-version ambiguity, and unrealistic TCC testing assumptions. Those findings were incorporated into this revision.

- Swift interface type-check: passed with Swift 6.3.3.
- Information architecture: 9/10.
- Interaction-state coverage: 9/10.
- User journey and recovery: 9/10.
- Accessibility and privacy specification: 9/10.
- Engineering completeness: 8/10; exact generated per-file model manifests remain build artifacts produced by the pinned packaging pipeline.
- Known blocker/high-severity review findings remaining: none after the final corrections.

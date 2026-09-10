# SwiftWhisper

Native, offline-first dictation for Mac, iPhone, and iPad, built with Swift and SwiftUI.

SwiftWhisper turns your voice into text using on-device speech recognition. On Mac, it lives in the menu bar: hold **Right Option**, speak, and release to insert the transcript into the text field you're using. On iPhone and iPad, tap to record, then copy or share the result.

Choose a speech model, optionally clean up punctuation with local AI, and revisit your recordings and transcripts in history. No cloud transcription service or API key is required. Language assets and optional models need an initial download; saved history can sync through your iCloud Drive.

**Status:** Early development. The source includes macOS and iOS apps. Optional models, iCloud sync, and distribution builds still need further device testing.

## Features

### Dictation on Mac

- **Push to talk:** Hold Right Option to record and release to transcribe and insert.
- **Toggle mode:** Press Right Option once to start and again to stop.
- **Cancel with Escape:** Cancel an active dictation without inserting it.
- **Cross-app insertion:** Deliver the finished transcript to the focused editable field, with focus checks to reduce insertion into the wrong target.
- **Copy Last:** Copy the most recent transcript from the menu bar. The menu action has a Control-Command-V shortcut.
- **Microphone selection:** Use the system default input or choose a specific microphone.
- **Recording overlay:** A floating status capsule shows listening and processing states, with microphone-reactive Voice Wave, Glowing Sphere, and Aurora Pulse animations.
- **Permission controls:** Review microphone, speech recognition, Input Monitoring, and Accessibility access in Settings.

### On-device speech recognition

The Mac app offers three transcription engines:

| Engine | Current language options | Setup |
| --- | --- | --- |
| Apple Dictation — default | System locale, English (US), Simplified Chinese, Traditional Chinese, subject to available Apple language support | Downloads Apple's language assets when needed |
| Moonshine Medium Streaming | English | Optional download, approximately 500 MB |
| Qwen3-ASR 0.6B | English and Chinese, including automatic language detection | Optional download, approximately 715 MB |

Download, select, and remove optional models in Mac Settings, with progress, cancellation, and retry controls. Moonshine and Qwen transcription integrations are experimental. The iPhone/iPad app currently uses Apple Dictation only.

For Apple Dictation, **Automatic** follows the device's current locale; it does not automatically detect the spoken language.

### Smart Polish

Optional Smart Polish adds punctuation, capitalization, and paragraph breaks before presenting or inserting a transcript. It runs locally on both platforms using either:

- **Apple Intelligence**, when available and enabled on the device.
- **Qwen3 0.6B, 4-bit**, an optional download of approximately 350 MB that can be removed from Settings.

The app checks the result against the original transcript and falls back to the original if the check fails or polishing is unavailable. The check compares letters and numbers while ignoring case, punctuation, and spacing; it is a formatting safeguard, not a guarantee of transcription accuracy.

### Custom vocabulary

Add names, product terms, and specialized phrases in Mac Settings. Up to 200 entries are stored locally and supplied as recognition hints to each Mac speech engine. Vocabulary hints can improve recognition but do not guarantee an exact match.

### History and corrections

- Save transcripts alongside their original voice recordings, with dates and durations.
- Replay audio, copy text, and delete individual entries on Mac and mobile.
- Save corrections on Mac, with a live view of added and removed text while retaining the original transcript and recording.
- Search history and share transcripts on iPhone/iPad.
- Keep up to 100 recent entries; older entries and their recordings are removed as new ones are added.
- Sync history through the user's iCloud Drive when available, with local storage as a fallback.

History saving is **enabled by default** and can be switched off in Settings. Switching it off stops saving new dictations; existing history remains until deleted. Saved corrections do not currently train or fine-tune a model.

### iPhone and iPad

The companion app provides a tap-to-start/stop recording workflow, transcript display, copy and sharing, searchable history, audio playback, language settings, and Smart Polish. It records within the app; system-wide Right Option activation and automatic insertion into other apps are Mac features.

### Diagnostics on Mac

Settings → Support provides local diagnostic logs, a report preview, an email draft with an attachment, and a save-to-file option. Reports exclude dictated text, recordings, custom vocabulary, and account identifiers. Nothing is uploaded automatically, and no remote analytics or third-party crash-reporting SDK is installed.

## Build and run

### Requirements

- An Apple silicon Mac for the current Mac development and beta workflow; Intel support is not validated.
- macOS 26 or later for the Mac app, or iOS/iPadOS 26 or later for the mobile app.
- Xcode with the required platform SDKs and Swift 6 support. The current development environment uses **Xcode 26.6**.
- Internet access to resolve Swift packages and download required language/model assets.
- Signing configured for your own Apple Developer team, including iCloud provisioning for history sync.

### Open the project

1. Clone this repository and open `SwiftWhisper/SwiftWhisper.xcodeproj` in Xcode.
2. Allow Xcode to resolve Swift package dependencies. The repository includes a `Package.resolved` lockfile.
3. Under **Signing & Capabilities**, select your development team and configure identifiers and iCloud as described below. The checked-in signing settings belong to the original development setup.
4. Choose the **SwiftWhisper** scheme for Mac or **SwiftWhisperMobile** for iPhone/iPad.
5. Select a destination, build, and run. Validate microphone and model behavior on a physical device.

The Xcode project is the app's build entry point; there is no root Swift package to run with `swift run`.

### Configure iCloud for your build

The checked-in app identifiers are `com.swiftwhisper.app` and `com.swiftwhisper.app.ios`. Both use the `iCloud.com.swiftwhisper.app` container.

For a fork, configure bundle identifiers and a shared iCloud container owned by your team. Update both targets' entitlements, the container identifier in `DictationHistoryStore.swift`, and the shared key-value-store identifier consistently. Both apps need access to that container. Sync requires the same iCloud account on both devices with iCloud Drive enabled.

When the container is unavailable at launch, history uses local storage. Concurrent history edits across devices are a known limitation and still need conflict-resolution work.

### First launch on Mac

Open Settings from the menu-bar icon and grant the permissions needed for your workflow:

| Permission | Purpose |
| --- | --- |
| Microphone | Record your voice |
| Speech Recognition | Authorize Apple speech recognition |
| Input Monitoring | Detect the global Right Option activation key |
| Accessibility | Inspect the focused text field and insert text into another app |

Then focus a text field, hold Right Option, speak, and release. Keep that field focused until insertion finishes. If insertion is unavailable, use **Copy Last** and paste manually.

If macOS retains a denied permission entry from an older development build, remove that entry in System Settings and grant access again.

## Privacy and storage

Speech recognition and Smart Polish run on the device. The app does not send recordings or transcripts to a hosted inference service. Network access is used for model/language downloads and, when available, iCloud history sync.

Saved history includes **both text and audio**. With iCloud Drive available, those files can leave the device through the user's iCloud account. Without it, history is stored locally under the app's Application Support directory. Disabling history does not delete previously saved data.

Mac diagnostics are stored separately from history and shared only when the user chooses to export or send a report. See the [beta release guide](docs/BETA_RELEASE.md) for diagnostic contents and retention details.

## Current limitations

- The Mac activation key is fixed to Right Option in the current UI; hold and toggle modes are configurable.
- Cross-app insertion depends on Accessibility access and a compatible editable field remaining focused. Some apps may require manual paste.
- Offline use requires the relevant language assets or model files to be installed first.
- Apple Intelligence polishing depends on device eligibility and system model availability.
- Optional transcription models and multi-device history sync need further real-device testing.
- The Mac target currently runs without App Sandbox. A Mac App Store build would require additional compatibility work.
- Automatic updates and automatic native crash-stack collection are not implemented.

## Development and contributions

Bug reports, reproducible test cases, and focused pull requests are welcome. For a dictation issue, include the platform and OS version, app version or commit, selected speech/polish models, language, and steps to reproduce. Review diagnostic attachments before sharing them, and avoid posting private recordings or transcripts.

| Location | Contents |
| --- | --- |
| `SwiftWhisper/SwiftWhisper/App/` | Mac app, settings, dictation coordination, overlay, and support UI |
| `SwiftWhisper/SwiftWhisper/Core/` | Shared types, settings, vocabulary, and transcript comparison |
| `SwiftWhisper/SwiftWhisper/Platform/` | Audio, recognition engines, model downloads, polish, history, and platform services |
| `SwiftWhisper/SwiftWhisperMobile/` | iPhone/iPad app and recording workflow |
| `Scripts/` and `Verification/` | Release preparation and diagnostics smoke checks |

Run the local diagnostics smoke checks from the repository root:

```sh
Scripts/check-diagnostics.sh
```

These checks cover diagnostics behavior, not the full dictation workflow. The [beta release guide](docs/BETA_RELEASE.md) includes manual device checks and signing/notarization instructions. Set `SWIFTWHISPER_SUPPORT_EMAIL` when preparing a beta to configure the public support address.

The [implementation specification](IMPLEMENTATION_SPEC.md) contains broader product and architecture plans; planned behavior there may go beyond the current features described in this README.

## License

A project license has not yet been added. Third-party dependencies and downloaded models have their own licenses and attribution requirements.

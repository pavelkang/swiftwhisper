# SwiftWhisper

Native, offline-first dictation for macOS 26.

The current implementation is the first vertical slice:

- menu-bar SwiftUI application;
- right Option global push-to-talk monitor;
- microphone capture at 16 kHz mono;
- Apple `SpeechAnalyzer` + `DictationTranscriber` adapter;
- notch-aware floating status capsule;
- direct Accessibility text insertion;
- in-memory history fallback;
- pure, tested dictation state reducer.

The full product and architecture specification is in [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md).

## Build

Full Xcode is recommended for development, permissions, XCTest, signing, and debugging.

This repository also includes a command-line build path for environments that only have Apple Command Line Tools:

```sh
./Scripts/build-app.sh
```

The resulting bundle is:

```text
.build/manual-app/SwiftWhisper.app
```

The script performs a Swift 6 strict-concurrency build and ad-hoc signs the bundle. A distributable build still requires a Developer ID certificate and notarization.

## Verification

Run the reducer verification through the Swift interpreter:

```sh
for SOURCE_FILE in Sources/SwiftWhisperCore/*.swift Verification/ReducerSmoke.swift; do
  cat "$SOURCE_FILE"
done | swift -
```

The normal command is `swift test`, but the installed SwiftPM toolchain on the current development machine cannot execute even a newly generated empty package manifest (`Missing or empty JSON output from manifest compilation`). The XCTest sources are included and should run once the project is opened with full Xcode or SwiftPM is repaired.

## First-run requirements

SwiftWhisper needs:

- Microphone access;
- Speech Recognition access for Apple Dictation;
- Input Monitoring for the global wake key;
- Accessibility for cross-application text insertion.

The prototype displays permission controls but does not yet include the final onboarding flow or Apple speech-asset installer.

## Current limitations

- History is in memory and resets when the process exits.
- Only Apple Dictation is wired; downloadable models come after the core loop is stable.
- Clipboard and Unicode-event insertion fallbacks are intentionally not implemented yet.
- Escape cancellation is not enabled while the event tap is listen-only.
- The command-line build script is a development convenience, not the final release pipeline.

# SwiftWhisper website beta

This is a direct-download Mac beta. Start with **Apple silicon and macOS 26 or later**. The packaging script deliberately builds arm64; do not advertise Intel support. iPhone/iPad distribution is a separate TestFlight/App Store workflow.

## Current release blockers

- Install a **Developer ID Application** certificate with its private key. Only Apple Development identities were available when this guide was prepared; a development-signed app is not the website download.
- Confirm the Apple Developer team `TYS32Z4DEC`, bundle identifier `com.swiftwhisper.app`, and Developer ID provisioning support the existing `iCloud.com.swiftwhisper.app` container. Do not remove entitlements just to make signing pass; verify iCloud on the distribution build.
- Supply an author/support email address. `SWIFTWHISPER_SUPPORT_EMAIL` is injected into `SwiftWhisperSupportEmail` in the app Info.plist. It is a public support address, not a secret. The release script requires it and verifies it in the export. The development build can still save reports when the address is not configured.
- Confirm your download URL and prepare release notes, support instructions, and a privacy page reflecting the app’s actual history and iCloud behavior.
- Complete the real-device checks below, third-party attribution review, signing, notarization, and stapling. A successful development build alone is not release approval.

## What is implemented

Settings → Support shows the version/build and offers **Send Diagnostics…**. It produces a preview, then lets the tester open an email draft with a text attachment, or save the same report. A compatible configured email app is needed for the draft; webmail users can save and attach the file. Nothing is uploaded automatically. Opening a draft does not prove that the author received a report.

Local logs live at `~/Library/Application Support/SwiftWhisper/Diagnostics/`. They are JSON Lines, serialized on a background queue, with four files capped at 256 KB each. Files that have not been modified for seven days are removed on the next write or report preparation. Directory permissions are 0700 and log files 0600; the diagnostic directory is excluded from backup. Activity can keep a rotating file alive for longer than seven days; this is a size cap plus inactive-file expiry, not strict per-event seven-day retention. Email draft attachments are separate files under `Reports/`, with at most five drafts retained; older attachments expire on the next email export. Save a copy if a draft needs to be kept longer. User-saved copies are managed by the user.

Logs cover startup/shutdown, unexpected previous termination, dictation failures and outcomes, text insertion rejection, model preparation/download/removal, polish fallback, history I/O, and report/export failures. Reports include version/build, macOS, architecture, memory, selected model settings, and permission status. They exclude audio, transcripts, vocabulary, account identifiers, paths, arbitrary error descriptions/userInfo, and native crash reports. No remote analytics or third-party crash SDK is installed.

These logs capture handled Swift errors and breadcrumbs. They do **not** intercept fatal signals, Swift traps, or every native exception. An unexpected-termination marker is a hint, not a confirmed crash (force quit and power loss also trigger it). If a native crash needs investigation, request the tester’s macOS crash report separately and have them review it before sharing. Preserve the exact release archive and dSYMs to symbolicate it.

## Prepare and verify a release

1. In Xcode → Settings → Accounts → Manage Certificates, obtain a Developer ID Application identity for the correct team. Confirm the associated Developer ID provisioning profile and iCloud capabilities.
2. Choose a numeric version and a new increasing build number, for example `0.1.0` / `2`.
3. Run the local diagnostics checks and prepare a Release archive/export:

   ```sh
   Scripts/check-diagnostics.sh
   Scripts/release-beta.sh prepare 0.1.0 2 YOUR_SUPPORT_EMAIL
   ```

   The script uses the committed package lockfile, validates the support email, checks Developer ID signing/hardened runtime and absence of debug entitlements, and creates `build/beta/0.1.0-2/`. It can update provisioning through Xcode during export. It does not upload the app for notarization or publish a website.

4. Store notarytool credentials in Keychain using Apple’s documented `xcrun notarytool store-credentials` flow. Never put passwords or private keys in this repository.
5. Submit to Apple, wait for acceptance, staple, and check Gatekeeper:

   ```sh
   Scripts/release-beta.sh notarize build/beta/0.1.0-2 YOUR_KEYCHAIN_PROFILE
   ```

   Publish only the resulting **SwiftWhisper-Beta.zip** and its `.sha256` checksum. The intermediate `notarization-upload.zip` contains an unstapled app. Keep `.xcarchive`, `.dSYM`, signing/provisioning details, and logs private. A notarization error requires inspection of the submission log, not disabling Gatekeeper.

6. Download that exact final ZIP through the website in a browser and test its quarantined app on a clean Mac/user account. Move the app to Applications before granting permissions. Replacing builds at inconsistent paths can complicate permission behavior.

The script’s syntax and local preflight are verified. Actual Developer ID export and notarization remain unverified until the missing identity and credentials are supplied.

## Manual beta acceptance checks

- First launch opens Settings and shows the supplied icon. The menu bar Settings action and Command-comma work.
- Deny and then grant microphone, speech recognition, Input Monitoring, and Accessibility independently. The app explains what is missing and recovers after returning from System Settings.
- Hold/release Right Option and toggle mode both work; accidental presses, no speech, Escape cancellation, repeated dictations, and focus changes do not insert duplicate/wrong-target text.
- Dictate into TextEdit and a browser text field; verify the copy fallback. Confirm audio stops after failure/cancellation and after microphone unplug/sleep-wake.
- Apple Dictation works with downloaded language assets offline. Download, cancel, retry, remove, and reload each optional model; test Apple Intelligence unavailable and disabled. Confirm polish fallback preserves the original words.
- Review and play history with iCloud on/off, temporarily unavailable audio, and two devices. Concurrent edits to the shared history index are still a limitation; validate before promising reliable multi-device conflict resolution.
- Trigger an expected permission/model failure and inspect Support → Send Diagnostics. Confirm version/build/error codes and lack of dictated content. Save a report, compose to the real support address, and check attachment/recipient. Have a human send a test email and verify receipt.
- Verify a force quit produces an unexpected-termination marker on the next launch; an ordinary quit does not. Verify logs cannot grow beyond their limit.
- Test the notarized download on another Apple silicon Mac running the minimum supported macOS, without Xcode installed. Keep one older beta for upgrade testing.

## Website and maintenance

Display “Beta”, version/build, release date, Apple silicon/macOS 26 requirements, download size, installation instructions, known issues, support address, and release notes. Tell users the app lives in the menu bar and why its permissions are needed. Explain that history currently retains transcripts and recordings and uses the user’s iCloud Drive when available; diagnostics are separate and exclude that content.

Audit dependency and model licenses and include required notices in the app/download. The package lockfile records exact dependency versions but does not replace a license audit. Optional models download separately and have their own terms.

There is no automatic updater yet. For the first beta, publish a versioned download and tell testers to quit the app and replace it in Applications. Keep signing identity and bundle ID stable across updates. Track each report against its version/build, reproduction steps, error event/code, and resolution. Email diagnostics provide an initial feedback channel, not fleet-wide crash counts or automatic reliability metrics.

Apple references:
- [Developer ID distribution](https://developer.apple.com/developer-id/)
- [Distribute outside the Mac App Store](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

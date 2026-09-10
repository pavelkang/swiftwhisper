---
title: 'SwiftWhisper: local voice-to-text for the Mac'
date: '2026-09-09'
tags: ['swift', 'macos', 'ai', 'voice', 'privacy']
draft: true
summary: 'Building a native dictation app that turns speech into text, with on-device recognition, optional local polishing, and a simple keyboard shortcut.'
images: ['/static/images/swiftwhisper/icon.png']
requireAuthentication: false
locale: en-US
---

![SwiftWhisper: a soft blue waveform flowing into a feather {0.3}](/static/images/swiftwhisper/icon.png)

SwiftWhisper is a native dictation app I’m building for the Mac, with a companion app for iPhone and iPad. Its core interaction is small: hold **Right Option**, say what you want to write, and release. SwiftWhisper transcribes your speech and inserts the result into the text field you’re using.

The goal is to make speaking a convenient part of writing. A quick note, a rough paragraph, or a longer message should be easy to capture without first opening a separate editor.

## A shortcut that stays out of the way

On the Mac, SwiftWhisper lives in the menu bar. Hold Right Option to record, or choose toggle mode to start and stop with a press. A floating overlay responds to your voice, and Escape cancels the recording.

When the transcript is ready, the app tries to insert it into the focused editable field. If the destination cannot accept it, there is a copy fallback. You can also copy the most recent transcript from the menu bar.

This workflow needs microphone and speech-recognition permissions, plus Input Monitoring for the shortcut and Accessibility for text insertion. Those permissions can be reviewed in Settings.

## Recognition on your device

SwiftWhisper uses on-device speech recognition. Apple Dictation is the default engine. On the Mac, there are also experimental integrations for Moonshine Medium Streaming and Qwen3-ASR, with models you can download and remove in Settings.

There is no cloud transcription account to create and no API key to supply. Language assets and optional models need an initial download; offline use depends on having those assets installed. Language support varies by engine, and the optional integrations still need more device testing.

For names and specialized terms, the Mac app supports a custom vocabulary. These entries give the recognizer hints, although they cannot guarantee the right spelling every time.

## A little polish after speaking

Spoken drafts often need punctuation and paragraph breaks. Optional **Smart Polish** handles that formatting locally using Apple Intelligence, when available, or a downloadable Qwen3 model.

The app checks the polished result against the original transcript and falls back if the check fails. This is a formatting safeguard rather than a guarantee of accuracy: I still recommend reading a transcript before using it for something important.

## History, with the recording attached

History keeps recent transcripts alongside their original audio, so you can replay a phrase and check what was said. On the Mac, you can save corrections and compare the edits while keeping the original recording and transcript.

History saving is enabled by default and retains up to 100 recent entries. You can turn it off in Settings; doing so stops new saves without deleting earlier entries.

Speech recognition and polishing run locally, but saved history can sync through your own iCloud Drive. That means recordings and transcripts may leave the device through iCloud. When iCloud is unavailable, the app uses local storage. Concurrent edits across devices remain an area that needs further work.

The iPhone and iPad companion uses tap-to-record, with copying, sharing, search, and playback. System-wide keyboard activation and insertion into other apps are Mac features.

## A quieter visual identity

The new icon follows the same idea as the app: a sound wave flowing into a feather, suggesting speech becoming writing. Muted blue and a bright ivory background give it a simpler, calmer appearance.

## Getting the beta ready

The first direct-download Mac beta targets **Apple silicon and macOS 26 or later**. Public distribution is still being prepared: the app needs Developer ID signing, Apple notarization, and testing of the final download on another Mac.

Once that verification is complete, the plan is to host the download on a public GitHub Releases page and link it here. This post is a preview, not an announcement that a verified download is already available. The iPhone and iPad version will need a separate distribution workflow.

There is no automatic updater yet. The initial Mac beta will use manual updates: quit the app and replace the copy in Applications. Optional model support and multi-device history are still experimental.

For beta questions and feedback, contact [eeveearchie@gmail.com](mailto:eeveearchie@gmail.com).

SwiftWhisper also includes a Support section for reviewing and saving diagnostic reports. Reports exclude dictated text and recordings, and nothing is sent automatically. That should make it easier to investigate problems without treating someone’s words as debugging data.

The next milestone is a small, dependable beta: record, transcribe, insert, and recover clearly when something goes wrong.

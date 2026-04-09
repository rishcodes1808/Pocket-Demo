# Pocket Keyboard

A full-replacement iOS custom keyboard with on-device voice dictation, live partial-text insertion, and a Live Activity. Works in any app that allows custom keyboards.

## Features

### Keyboard
- Full QWERTY letters, numbers page, symbols page
- Shift + double-tap caps lock
- Backspace and return with auto-repeat (0.5s delay, 0.1s interval)
- Double-space → period shortcut + auto-capitalize after `.?!`, newlines, empty context
- Spacebar trackpad: long-press the spacebar to enter cursor-drag mode
- iOS-native key callout bubbles on letter keys
- Haptic feedback on every keystroke
- System keyboard click sounds (requires Full Access)
- Dark/light mode aware

### Dictation
- On-device speech recognition via `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true`)
- **Live partial-text insertion** — as you speak, partial transcripts are inserted directly into the active text field and replaced in-place on each recognizer update
- **3-second silence auto-finalize** — stop speaking and the current burst is finalized automatically
- Final result replaces the last partial with the recognizer's end-of-utterance version (fixes casing/punctuation)
- Waveform visualization driven by live RMS audio levels
- Audio session uses `.mixWithOthers` so it coexists with other apps playing audio
- Auto-restart after interruptions (phone calls, Siri)
- 20-minute recording timeout

### Live Activity
- Lock Screen banner with mic icon, status label, waveform, and Stop button
- Dynamic Island expanded, compact, and minimal presentations
- Pulsing symbol effect during active transcription
- Stop button works from the background via an `AppIntent` that posts a Darwin notification
- Audio level updates throttled to 2s (ActivityKit rate limit)
- `staleDate` refresh so the activity shows "idle" if the app is killed
- Auto-dismiss 5 minutes after the engine stops

### Main App
- Setup guide with a one-tap "Open Settings" button
- Permission status for microphone + speech recognition
- **Embedded keyboard preview** — the "Try it out" field embeds the actual keyboard view directly (via `UITextView.inputView`), so you can test dictation without adding the keyboard in Settings first
- Handles the `pocketdemo://dictate` URL scheme for keyboard-initiated dictation

## Requirements

- Xcode 16 or later
- iOS 26.4 SDK (deployment target 26.4)
- A real device for on-device dictation (the Simulator can type but cannot do speech recognition)
- Apple Developer account for code signing (default team is `6J7Z474QUR` — change in project settings)

## How to Run / Install

1. Open `Pocket Demo.xcodeproj` in Xcode
2. Select the **Pocket Demo** scheme
3. Pick your device (or an iOS 26.4 simulator for typing-only testing)
4. Build & run (⌘R)
5. On first launch the app asks for **Microphone** and **Speech Recognition** permissions — grant both
6. Tap the **"Try it out"** text field at the bottom of the app — the Pocket Keyboard opens automatically. You can test typing and dictation here before installing the keyboard system-wide.

### Enabling the keyboard system-wide

1. Open **Settings → General → Keyboard → Keyboards → Add New Keyboard…**
2. Select **Pocket Keyboard**
3. Tap **Pocket Keyboard** in the list → enable **Allow Full Access**
   *(Full Access is required because dictation needs to open the containing app via the `pocketdemo://dictate` URL scheme.)*
4. In any text field, long-press the globe key and select **Pocket Keyboard**
5. Tap **Activate Dictation** to start your first burst

## Architecture

### Cross-process dictation

iOS keyboard extensions run in a heavily-sandboxed process with strict memory limits (~50 MB) and unreliable audio access. Running `AVAudioEngine` + `SFSpeechRecognizer` directly inside the extension is fragile. Instead, Pocket Keyboard uses the same pattern as production keyboards like Wispr Flow: **the main app owns the audio engine**, the keyboard extension owns the UI, and the two processes talk over an App Group.

```
┌──────────────────────┐                     ┌──────────────────────┐
│  Pocket Keyboard     │   Darwin notifs     │  Pocket Demo (app)   │
│  (extension)         │ ◄─────────────────► │                      │
│                      │                     │  LiveTranscription-  │
│  KeyboardTranscrip-  │   App Group         │  Manager             │
│  tionBridge          │ ◄─────────────────► │  (AVAudioEngine +    │
│  (state machine)     │  UserDefaults       │   SFSpeechRecognizer)│
└──────────────────────┘                     └──────────────────────┘
        ▲                                              │
        │ UIHostingController                          │ posts engineStarted,
        │                                              │ transcriptionComplete,
        │                                              │ partialTranscriptUpdated,
        │                                              │ burstSilent
        ▼                                              ▼
┌──────────────────────┐                     ┌──────────────────────┐
│  KeyboardContainer-  │                     │  LiveActivity widget │
│  View (SwiftUI)      │                     │  (Lock Screen / DI)  │
└──────────────────────┘                     └──────────────────────┘
```

**Darwin notifications** (via `CFNotificationCenterGetDarwinNotifyCenter`) give instant cross-process signalling without requiring either process to be in the foreground. They carry no payload — the payload lives in **shared `UserDefaults`** backed by the `group.com.sample.Pocket-Demo` App Group.

### End-to-end flow

1. **User is in any app** (Notes, Messages, etc.) with Pocket Keyboard active.
2. **Tap "Activate Dictation"** → `KeyboardTranscriptionBridge.startDictation()` sets state to `.waitingForApp`, writes textbox context to shared defaults, opens `pocketdemo://dictate`.
3. **Main app launches** (or foregrounds), `.onOpenURL` presents `SwitchBackView` which calls `LiveTranscriptionManager.shared.startRecording()`.
4. **`LiveTranscriptionManager`** configures `AVAudioSession`, starts `AVAudioEngine`, installs a tap, creates an `SFSpeechAudioBufferRecognitionRequest` (on-device), and starts the recognition task. It sets `dictationInProgress = true`, `engineStartedAt = Date()`, and posts the `engineStarted` Darwin notification.
5. **Bridge receives `engineStarted`** → transitions to `.transcribing`, the keyboard shows the waveform banner.
6. **User speaks** → recognizer fires partial callbacks → each one writes `partialTranscript` to shared defaults, posts `partialTranscriptUpdated`, updates `lastPartialAt`.
7. **Bridge receives `partialTranscriptUpdated`** → reads the new partial, computes the diff vs. the previously-inserted text, calls `proxy.deleteBackward()` N times, then `proxy.insertText(newPartial)`. The text field updates live.
8. **Silence detection**: if no new partial arrives for 3 seconds (tracked by `lastPartialAt`), `LiveTranscriptionManager` auto-calls `stopTranscribing()`.
9. **Finalization**: `finalizeBurst(text:)` writes the final text to `pendingDictationText`, clears the partial, posts `transcriptionComplete`. State returns to `.recording` (engine stays alive).
10. **Bridge receives `transcriptionComplete`** → reads `pendingDictationText`, replaces the last inserted partial with the final text (same delete-N + insert pattern), returns to `.recording`.
11. **Next burst**: the user taps "Speak" — the bridge posts `startTranscribing` (no URL-scheme round-trip), the main app begins a new burst immediately. The engine stays alive for up to 20 minutes of idle.

### State machine (`KeyboardTranscriptionBridge`)

```
                         ┌──────────┐
                         │  .idle   │◄─────────────────┐
                         └────┬─────┘                  │
                 tap Activate │                        │ stopEngine / timeout
                              ▼                        │
                   ┌────────────────────┐               │
                   │  .waitingForApp    │               │
                   └────────┬───────────┘               │
                            │ engineStarted             │
                            ▼                           │
                   ┌────────────────────┐               │
            ┌─────►│    .recording      │───────────────┤
            │      └────────┬───────────┘               │
            │               │ tap Speak /               │
            │               │ startTranscribing         │
            │               ▼                           │
            │      ┌────────────────────┐               │
            │      │   .transcribing    │               │
            │      └────────┬───────────┘               │
            │               │ tap Done /                │
            │               │ 3s silence /              │
            │               │ recognizer isFinal        │
            │               ▼                           │
            │      ┌────────────────────┐               │
            │      │   .processing      │               │
            │      └────────┬───────────┘               │
            │               │ transcriptionComplete     │
            │               ▼                           │
            │      ┌────────────────────┐               │
            └──────┤    .completed      │               │
                   └────────────────────┘               │
                                                        │
                   (error path leads to .error) ────────┘
```

### Engine liveness

The main app can be suspended by iOS at any time. The bridge keeps itself in sync with reality via three mechanisms:

- **Persistent Darwin observers** — `engineStarted`, `engineStopped`, `engineAliveResponse`, `burstSilent`, `partialTranscriptUpdated`, `transcriptionComplete` all have always-on listeners set up when the keyboard view appears.
- **Active verification** — the bridge sends `engineAliveRequest` and starts a 1 s timeout task. If the main app answers with `engineAliveResponse`, the engine is confirmed alive. After 3 consecutive failures, the bridge declares the engine dead and transitions to `.idle`.
- **Heartbeat** — every 1.5 s the bridge polls shared defaults for stranded pending text and re-verifies engine liveness from `.recording`/`.transcribing`.

A 10 s **grace period** after any confirmed-alive contact skips verify attempts entirely — iOS deprioritizes Darwin notifications for backgrounded apps, so verify often fails even when the engine is fine. After text delivery or `engineAliveResponse`, we know the engine was alive <10 s ago and don't need to re-check.

A 15 s **declared-dead cooldown** prevents thrashing: once the bridge declares the engine dead, it won't re-verify until either (a) 15 s pass or (b) an `engineStarted` notification arrives.

### Embedded mode (main app preview)

The same `KeyboardContainerView` is reused verbatim inside the main app via `PocketKeyboardTextView` — a `UIViewRepresentable` that wraps a `UITextView` and sets its `inputView` to a `UIHostingController` hosting the keyboard. A `KeyboardProxy(textView:)` init variant routes key taps into the text view directly instead of going through `UITextDocumentProxy`.

When the user taps "Activate Dictation" in embedded mode, the `openURL` callback short-circuits the URL-scheme handoff and calls `LiveTranscriptionManager.shared.startRecording()` directly. Because `LiveTranscriptionManager` posts `engineStarted` from the same process, the bridge still transitions normally via its Darwin observer — no special-casing needed.

### Live Activity

`TranscriptionActivityAttributes` is duplicated between the main app and the widget extension (they're separate Swift modules). The `activityAttributesName` static is overridden to a stable string so ActivityKit matches the type across modules.

`LiveActivityManager.updateForEngineState(_:)` is called from `LiveTranscriptionManager.state`'s `didSet`, mapping engine states to `TranscriptionState` cases and starting/updating/ending the activity. Audio level updates from the audio tap are forwarded to `LiveActivityManager.updateAudioLevel(_:)`, which throttles to 2 s (ActivityKit rate limit) and refreshes the `staleDate` so the widget shows `idle` if the app is killed.

The Stop button in the widget uses `StopEngineIntent: LiveActivityIntent` with `openAppWhenRun = false`, posting the `stopEngine` Darwin notification. Both `LiveTranscriptionManager` and `LiveActivityManager` observe this — the former shuts down the audio engine, the latter dismisses the activity.

## File Structure

```
Pocket Demo/
├── README.md                          ← this file
├── Pocket Demo.xcodeproj/
│
├── Pocket Demo/                       ← main app target
│   ├── Pocket_DemoApp.swift             app entry, URL scheme handler
│   ├── ContentView.swift                setup guide + embedded keyboard preview
│   ├── PocketKeyboardTextView.swift     UITextView wrapper that embeds the keyboard
│   ├── SwitchBackView.swift             starts the engine when the URL scheme fires
│   ├── LiveTranscriptionManager.swift   AVAudioEngine + SFSpeechRecognizer +
│   │                                    silence detection + Darwin observers
│   ├── LiveActivityManager.swift        Live Activity lifecycle
│   ├── TranscriptionActivityAttributes.swift   ActivityKit data model (main app copy)
│   ├── Info.plist                       URL scheme, mic/speech descriptions,
│   │                                    NSSupportsLiveActivities, audio background mode
│   ├── Pocket Demo.entitlements         App Group + audio-input
│   └── Assets.xcassets
│
├── Pocket Keyboard/                   ← keyboard extension target
│   ├── KeyboardViewController.swift     UIInputViewController + openApp()
│   ├── Info.plist                       RequestsOpenAccess = true, usage descriptions
│   └── Pocket Keyboard.entitlements     App Group
│
├── Shared/                            ← shared between main app + keyboard extension
│   ├── SharedConstants.swift            PKConstants (app group ID, URL scheme,
│   │                                    Darwin notification names, shared default keys)
│   ├── AppGroupManager.swift            shared UserDefaults wrapper
│   ├── DarwinNotificationCenter.swift   CFNotificationCenter wrapper
│   ├── KeyboardProxy.swift              dual-mode proxy (UITextDocumentProxy | UITextView)
│   ├── KeyboardTranscriptionBridge.swift   state machine + partial text replacement
│   ├── KeyboardContainerView.swift      main SwiftUI container, banner routing,
│   │                                    shift logic, auto-capitalization
│   ├── KeyboardLayout.swift             KeyModel, KeyboardPage, layout data
│   ├── KeyButton.swift                  QFKeyView, callout shape, autorepeat,
│   │                                    spacebar trackpad
│   ├── KeyRow.swift                     row layout with hit padding distribution
│   ├── HapticManager.swift              haptic feedback wrappers
│   ├── ActivateBanner.swift             "Activate Dictation" button (outside engine)
│   ├── ReadyBanner.swift                "Speak" button (engine alive)
│   ├── WaitingBanner.swift              "Starting engine…" spinner
│   ├── SilenceBanner.swift              "No speech detected" toast
│   └── TranscribingBanner.swift         cancel + waveform + done
│
└── Pocket Live Activity/              ← widget extension target
    ├── Pocket_Live_ActivityBundle.swift   @main widget bundle
    ├── Pocket_Live_ActivityLiveActivity.swift   Lock Screen + Dynamic Island views
    ├── AppIntent.swift                    StopEngineIntent (LiveActivityIntent)
    ├── TranscriptionActivityAttributes.swift   ActivityKit data model (widget copy)
    ├── SharedConstants.swift              PKConstants (widget copy)
    ├── DarwinNotificationCenter.swift     CF wrapper (widget copy, used by intent)
    ├── Info.plist                         widgetkit-extension point
    └── Assets.xcassets
```

### Code sharing strategy

The project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup` for target membership. The `Shared/` folder is referenced by both the **Pocket Demo** target and the **Pocket Keyboard** target in their `fileSystemSynchronizedGroups` list, so every file in `Shared/` compiles into both modules automatically — no duplicate file references to maintain.

Three files are duplicated into the **Pocket Live Activity** target because the widget extension has a different dependency footprint (no keyboard UI, but it needs `PKConstants`, `DarwinNotificationCenter`, and the `TranscriptionActivityAttributes` data model). Swift modules are isolated, so the duplicated types don't conflict — and `TranscriptionActivityAttributes.activityAttributesName` is overridden to a stable string (`"TranscriptionActivityAttributes"`) so `ActivityKit` matches the type across the two modules.

## Key Decisions & Tradeoffs

### Why the main app runs the audio engine instead of the keyboard extension

Keyboard extensions have hard limits: ~50 MB memory, no reliable background audio, and `AVAudioSession` access that iOS revokes aggressively when the containing app isn't running. Running `AVAudioEngine` + `SFSpeechRecognizer` inside the extension works in testing but fails in production for longer sessions, after interruptions, and when memory pressure is high. Putting audio in the main app gives us:

- The full 512+ MB memory budget (on-device `SFSpeechRecognizer` loads ~200 MB of model weights)
- A background audio session (`UIBackgroundModes = audio`) that survives app suspension
- Standard `AVAudioSession` interruption handling (phone calls, Siri, ducking)
- A 20-minute continuous recording window instead of the ~30 s the extension can reliably sustain

The tradeoff is the URL-scheme handoff on the first dictation of a session. Subsequent bursts use `startTranscribing` Darwin notifications without any app switch, so the "switch back" dance only happens once.

### Why Darwin notifications instead of a Mach port / XPC service

Darwin notifications are the simplest cross-process signalling primitive iOS offers that works between a main app and its extension without requiring either to be in the foreground. They carry no payload (so all shared state lives in App Group `UserDefaults`) and they're coalesced by iOS, but they deliver **immediately** when the receiving process is alive. XPC and Mach ports require more plumbing, and neither is available to keyboard extensions in the way audio-unit extensions can use them.

Tradeoff: we can't do backpressure or reliable ordering. Mitigated with deduplication (`lastDeliveredText` + 3 s window), heartbeat polling (1.5 s fallback), and atomic `consumePendingDictationText()` reads.

### Why `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`

- **Privacy**: no audio leaves the device.
- **Latency**: partial results land in ~200–500 ms vs. 1–2 s for server-based.
- **Offline**: works without a network.
- **Good enough quality** for general English dictation at the demo level.

Tradeoff: English-only in this demo (the recognizer is pinned to `en-US`). For multilingual, you'd pipe the user's preferred locale into `SFSpeechRecognizer(locale:)` and duplicate the permission messaging. Accuracy is a notch below Whisper-cloud for proper nouns and mumbled speech, but the on-device latency and privacy win matters more for a keyboard.

### Why silence is detected via partial-result gaps instead of audio RMS

Audio-level thresholding is fiddly: background noise, breath noise, and mic calibration all shift the baseline. `SFSpeechRecognizer` already makes this distinction internally — it only emits partial results while it's confident the audio contains speech. Tracking `lastPartialAt` and comparing to a 3-second window is more reliable than rolling an RMS window, and it reuses work the recognizer is already doing.

Tradeoff: if the recognizer drops a partial mid-speech (rare), we could mis-fire. Mitigated by only starting the silence check after `hasDetectedFirstSpeech = true` and by being conservative (3 s, not 1 s).

### Why partial text is inserted live into the field instead of previewed in the banner

The screenshot-driven requirement is that dictated text should appear inline as you speak — matching iOS's own dictation and what users already expect. Previewing in a banner is easier to implement (no delete-and-reinsert dance) but feels sluggish because the text "jumps" into the field only when you tap Done.

The tradeoff is that every partial update does `N × proxy.deleteBackward()` followed by `proxy.insertText(newPartial)`. For English, grapheme count matches the number of `deleteBackward` calls needed, so this is safe. Each delete+insert cycle is fast enough (~1 ms) that it's imperceptible, even for long partials.

For text with combining characters, emoji sequences, or complex scripts, grapheme counting could drift. The demo is English-only so this doesn't bite, but a production version would track a snapshot of the cursor position via `documentContextBeforeInput` and replace by byte range instead.

### Why the main app display name is "Pocket Keyboard"

iOS's keyboard switcher shows `<KeyboardExtensionName> — <MainAppName>` when the two differ, and collapses to just `<Name>` when they match. Setting `CFBundleDisplayName` on the main app to `Pocket Keyboard` (matching the extension's `INFOPLIST_KEY_CFBundleDisplayName`) avoids the ugly "Pocket Keyboard — Pocket Demo" suffix in the system switcher.

Tradeoff: the home-screen icon also reads "Pocket Keyboard" now, which is arguably fine for this demo — the main app is a setup/preview shell for the keyboard, not a standalone product.

### Why `TranscriptionActivityAttributes` is duplicated instead of shared via a framework

Xcode 16's file-system-sync groups can include the same folder in multiple targets (which is how `Shared/` works for the main app + keyboard extension), but the widget extension has a genuinely different dependency footprint — it doesn't need the ~15 keyboard UI files. Creating a separate `SharedWidget/` synced group for 3 files is more overhead than just duplicating them.

The `activityAttributesName` static override ensures `ActivityKit` matches the duplicated types across modules. This is a well-known trick used by apps that don't want to spin up a Swift package just for a 50-line data model.

## Known Limitations / Next Steps

### Current limitations

- **English only** — `SFSpeechRecognizer` is hardcoded to `en-US`. The shared `partialTranscript` path doesn't handle language switching.
- **First-dictation app switch** — the initial `pocketdemo://dictate` handoff takes 1–2 s before the engine is ready. After that, subsequent bursts don't require a switch.
- **No automatic switch-back** — after launching the main app via the URL scheme, the user has to manually switch back to the host app. A production version would save the host bundle ID (via XPC `PKService` walk on iOS < 26.4) and open a known URL scheme for the host app to auto-return.
- **No emoji picker** — out of scope for this demo. The keyboard layout enum has `.emoji` removed and the bottom row uses a globe key instead.
- **Limited auto-capitalization** — handles start-of-input, after `.?!`, and after newlines. Doesn't do per-language rules or proper-noun detection.
- **Grapheme-cluster delete** — live partial replacement uses `String.count` to count deletes, which works for English but can drift for combining marks, emoji ZWJ sequences, or complex scripts.
- **No secure-field handling** — the keyboard doesn't check `proxy.isSecureTextEntry` before starting dictation. A production version would refuse dictation in password fields.
- **Simulator can't dictate** — `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` requires real-device hardware. The Simulator will show the keyboard UI but dictation will error out.
- **Single development team** — `project.pbxproj` hardcodes `DEVELOPMENT_TEAM = 6J7Z474QUR`. You'll need to change it to your own team in all four targets (main app, keyboard, Live Activity widget, and config lists).

### Next steps

- **Auto-switch-back** via host bundle ID capture (see QuillFlow's `AppSchemes.swift` approach with a hand-curated map of bundle ID → URL scheme)
- **Multi-language support** — read preferred languages from `AppGroupManager`, pass to `SFSpeechRecognizer(locale:)`, let the widget show the active locale
- **Richer Live Activity** — show the current partial transcript on the Lock Screen, add a "Pause" button in addition to Stop
- **LLM post-processing** — pipe the final transcript through a small on-device model (Foundation Models framework on iOS 26+) for punctuation cleanup, formal/casual tone based on the host app type
- **Field-type detection** — mirror QuillFlow's `FieldType` enum to adjust dictation behavior (shorter bursts in messaging, signature detection in email body, etc.)
- **Emoji picker page** — add back the `.emoji` keyboard page with a frequency-tracked grid
- **Accessibility** — VoiceOver labels on every key, Dynamic Type support on the banners
- **Unit tests** — `KeyboardTranscriptionBridge` state transitions, `AppGroupManager` shared-defaults round-trip, silence-detection timing

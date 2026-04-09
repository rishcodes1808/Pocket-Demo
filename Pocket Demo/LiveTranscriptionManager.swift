import Foundation
import AVFoundation
import Speech

/// Runs the audio engine and speech recognizer in the main app.
/// Listens for Darwin notifications from the keyboard extension, writes partial
/// transcripts and audio levels to shared UserDefaults, and posts Darwin
/// notifications back when transcription bursts complete.
@Observable
@MainActor
final class LiveTranscriptionManager {

    /// Singleton — must survive view dismissals so background recording continues.
    static let shared = LiveTranscriptionManager()

    enum State: Equatable {
        case idle
        case recording       // Audio engine alive, NOT transcribing (between bursts)
        case transcribing    // Audio engine alive + speech recognizer active
        case finalizing      // Stopping current transcription burst
        case completed(String)
        case error(String)
    }

    private(set) var state: State = .idle {
        didSet {
            // Mirror state changes to the Live Activity
            let stateString: String
            switch state {
            case .idle:             stateString = "idle"
            case .recording:        stateString = "recording"
            case .transcribing:     stateString = "transcribing"
            case .finalizing:       stateString = "finalizing"
            case .completed:        stateString = "completed"
            case .error:            stateString = "error"
            }
            LiveActivityManager.shared.updateForEngineState(stateString)
        }
    }
    private(set) var audioLevel: Float = 0.0
    private(set) var currentText: String = ""

    // MARK: - Audio Engine & Speech Recognizer

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recordingTimeoutTask: Task<Void, Never>?
    private var interruptionStartDate: Date?

    /// `true` when the current burst was stopped by the user tapping the Done
    /// button in the keyboard (via the `stopRecording` Darwin notification),
    /// `false` when it was stopped by the recognizer itself. Used to decide
    /// whether to post the `burstSilent` notification when finalizing with
    /// empty text — the silence banner should only appear if the user
    /// explicitly asked to stop and nothing was captured.
    private var wasManuallyStopped = false

    private init() {}

    // MARK: - Start Recording (engine + first burst)

    /// Starts the audio engine and begins a transcription burst immediately.
    func startRecording() {
        switch state {
        case .recording, .transcribing, .finalizing:
            return
        default:
            break
        }

        currentText = ""
        audioLevel = 0.0
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognizer unavailable")
            AppGroupManager.shared.writeTranscriptionError("Speech recognizer unavailable")
            DarwinNotificationCenter.shared.post(PKConstants.Notification.transcriptionComplete)
            return
        }

        do {
            // Configure audio session. .mixWithOthers is critical to survive other apps playing audio.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Prefer the built-in mic for consistent quality
            if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMic)
            }

            // Observe audio interruptions (phone calls, Siri, etc.)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: session
            )

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                state = .error("Microphone not available")
                return
            }

            // We'll install the recognition request and tap together when we actually begin a burst
            self.audioEngine = engine

            engine.prepare()
            try engine.start()

            AppGroupManager.shared.dictationInProgress = true
            AppGroupManager.shared.engineStartedAt = Date()
            AppGroupManager.shared.isTranscribing = false

            state = .recording

            // Tell the keyboard the engine is alive
            DarwinNotificationCenter.shared.post(PKConstants.Notification.engineStarted)

            // Begin the first transcription burst
            beginTranscriptionBurst()

            // Listen for Darwin notifications from the keyboard
            setupDarwinObservers()

            // Auto-stop after 20 minutes to prevent runaway recordings
            recordingTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(PKConstants.Audio.recordingTimeoutSeconds))
                guard let self else { return }
                guard self.state == .recording || self.state == .transcribing else { return }
                self.stopRecordingEntirely()
            }

        } catch {
            state = .error(error.localizedDescription)
            AppGroupManager.shared.writeTranscriptionError(error.localizedDescription)
            AppGroupManager.shared.dictationInProgress = false
            DarwinNotificationCenter.shared.post(PKConstants.Notification.transcriptionComplete)
        }
    }

    // MARK: - Start Transcribing (new burst on running engine)

    /// Begins a new transcription burst on the already-running audio engine.
    func startTranscribing() {
        switch state {
        case .recording, .completed:
            break
        default:
            return
        }

        currentText = ""
        beginTranscriptionBurst()
    }

    // MARK: - Stop Transcribing (end current burst, keep engine alive)

    /// Ends the current transcription burst. The audio engine stays alive so
    /// the user can start another burst with minimal latency.
    func stopTranscribing() {
        guard state == .transcribing else { return }
        state = .finalizing

        // End the recognition request — this triggers a final result callback
        recognitionRequest?.endAudio()

        // Give the recognizer a moment to finalize, then deliver the result
        Task { @MainActor [weak self] in
            // Wait up to 2s for the final result
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if self?.state != .finalizing {
                    return
                }
            }
            // Timeout — deliver whatever we have
            guard let self, self.state == .finalizing else { return }
            self.finalizeBurst(text: self.currentText)
        }
    }

    // MARK: - Stop Recording Entirely (full shutdown)

    /// Stops the audio engine, speech recognizer, and clears all flags.
    func stopRecordingEntirely() {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil

        // If transcribing, deliver any current text first
        if state == .transcribing || state == .finalizing {
            if !currentText.isEmpty {
                AppGroupManager.shared.pendingDictationText = currentText
                DarwinNotificationCenter.shared.post(PKConstants.Notification.transcriptionComplete)
            }
        }

        removeAllObservers()
        cleanup()
        AppGroupManager.shared.dictationInProgress = false
        AppGroupManager.shared.engineStartedAt = nil
        AppGroupManager.shared.isTranscribing = false
        AppGroupManager.shared.audioLevel = 0.0
        AppGroupManager.shared.clearPartialTranscript()
        state = .idle
        currentText = ""
        audioLevel = 0.0

        // Notify keyboard that the engine is dead
        DarwinNotificationCenter.shared.post(PKConstants.Notification.engineStopped)
    }

    // MARK: - Cancel

    func cancel() {
        stopRecordingEntirely()
    }

    // MARK: - Private Helpers

    private func setupDarwinObservers() {
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.stopRecording
        ) { [weak self] in
            Task { @MainActor [weak self] in
                // Mark this as a manual stop so finalizeBurst knows to show
                // the silence banner if no speech was captured.
                self?.wasManuallyStopped = true
                self?.stopTranscribing()
            }
        }

        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.startTranscribing
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.startTranscribing()
            }
        }

        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.stopEngine
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.stopRecordingEntirely()
            }
        }

        // Respond to keyboard liveness checks
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.engineAliveRequest
        ) {
            DarwinNotificationCenter.shared.post(
                PKConstants.Notification.engineAliveResponse
            )
        }
    }

    /// Starts a new transcription burst by installing the audio tap and recognition task.
    private func beginTranscriptionBurst() {
        guard let engine = audioEngine else {
            state = .error("No audio engine")
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognizer unavailable")
            return
        }

        // Reset manual-stop tracking for this burst
        wasManuallyStopped = false
        AppGroupManager.shared.clearPartialTranscript()

        // Create a fresh recognition request for this burst
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove any existing tap before installing a new one
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Compute audio level for waveform (only during active transcription)
            guard let self else { return }
            let level = Self.calculateLevel(buffer: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.state == .transcribing else { return }
                self.audioLevel = level
                AppGroupManager.shared.audioLevel = level
                LiveActivityManager.shared.updateAudioLevel(level)
            }
        }

        // Start the recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.currentText = text

                    // Write partial transcript to shared defaults so keyboard can display it.
                    // Skip empty text — the recognizer occasionally emits an empty
                    // formattedString at segment boundaries, and forwarding that would
                    // cause the keyboard bridge to delete already-inserted partial text.
                    if !text.isEmpty {
                        AppGroupManager.shared.partialTranscript = text
                        AppGroupManager.shared.sharedDefaults.synchronize()
                        DarwinNotificationCenter.shared.post(
                            PKConstants.Notification.partialTranscriptUpdated
                        )
                    }

                    if result.isFinal {
                        self.finalizeBurst(text: text)
                    }
                }

                if let error {
                    let nsError = error as NSError
                    // Ignore cancellation errors
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 203) {
                        return
                    }
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // No speech detected (recognizer error).
                        //
                        // Race fix: the recognizer sometimes emits 1110 at the
                        // tail of a successful burst right next to the final
                        // result. If we already captured text from partials,
                        // deliver that instead of declaring silence — otherwise
                        // the user sees a spurious silence banner after a
                        // successful dictation.
                        if self.state == .transcribing || self.state == .finalizing {
                            self.finalizeBurst(text: self.currentText)
                        }
                        return
                    }
                    if self.state == .transcribing || self.state == .finalizing {
                        self.state = .error(error.localizedDescription)
                        AppGroupManager.shared.writeTranscriptionError(error.localizedDescription)
                        DarwinNotificationCenter.shared.post(PKConstants.Notification.transcriptionComplete)
                    }
                }
            }
        }

        state = .transcribing
        AppGroupManager.shared.isTranscribing = true
    }

    /// Finalizes the current burst — writes the text for the keyboard to pick up
    /// and transitions back to `.recording` (engine stays alive).
    private func finalizeBurst(text: String) {
        // Guard against double-finalization
        guard state == .transcribing || state == .finalizing else { return }

        // Cancel the recognition task and remove the tap
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)

        AppGroupManager.shared.isTranscribing = false
        AppGroupManager.shared.audioLevel = 0
        // Intentionally do NOT clear partialTranscript here. Clearing it races
        // with the final partialTranscriptUpdated notification crossing
        // processes — the bridge can read the cleared value and interpret it
        // as "delete everything I've inserted". The next burst clears it in
        // beginTranscriptionBurst (and startTranscribingOnly clears it on the
        // keyboard side), so leaving it stale between bursts is harmless.
        audioLevel = 0

        guard !text.isEmpty else {
            // No speech captured — return to .recording state.
            //
            // Only post `burstSilent` (which shows the keyboard's silence
            // banner) if the user manually ended the burst. Recognizer 1110
            // errors should never show it — the user only cares when *they*
            // asked to stop and nothing was heard.
            state = .recording
            if wasManuallyStopped {
                DarwinNotificationCenter.shared.post(PKConstants.Notification.burstSilent)
            }
            wasManuallyStopped = false
            return
        }

        // Clear the manual-stop flag for the next burst
        wasManuallyStopped = false

        // Write result for keyboard to pick up
        AppGroupManager.shared.pendingDictationText = text

        // Notify keyboard
        DarwinNotificationCenter.shared.post(PKConstants.Notification.transcriptionComplete)

        state = .completed(text)

        // Auto-transition back to .recording after a brief moment
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if case .completed = self?.state {
                self?.state = .recording
            }
        }
    }

    // MARK: - Audio Interruption

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            interruptionStartDate = Date()

        case .ended:
            let interruptionDuration = interruptionStartDate.map { -$0.timeIntervalSinceNow } ?? 0
            interruptionStartDate = nil

            guard audioEngine != nil, state == .recording || state == .transcribing else {
                return
            }

            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)

            if shouldResume || interruptionDuration < 300 {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    try audioEngine?.start()
                } catch {
                    stopRecordingEntirely()
                }
            } else {
                stopRecordingEntirely()
            }

        @unknown default:
            break
        }
    }

    private func cleanup() {
        NotificationCenter.default.removeObserver(
            self, name: AVAudioSession.interruptionNotification, object: nil
        )

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    private func removeAllObservers() {
        DarwinNotificationCenter.shared.removeObserver(PKConstants.Notification.stopRecording)
        DarwinNotificationCenter.shared.removeObserver(PKConstants.Notification.startTranscribing)
        DarwinNotificationCenter.shared.removeObserver(PKConstants.Notification.stopEngine)
        DarwinNotificationCenter.shared.removeObserver(PKConstants.Notification.engineAliveRequest)
    }

    /// Calculates normalized RMS audio level (0.0 – 1.0) from a PCM buffer.
    private nonisolated static func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for i in 0..<count {
            let sample = channelData[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(count))

        // Scale so conversational speech (RMS ~0.02-0.08) maps to ~0.4-0.8
        let scaled = powf(rms * 25.0, 0.8)
        return min(scaled, 1.0)
    }
}

import Foundation

enum BridgeState: Equatable {
    case idle
    case waitingForApp   // URL opened, switching to main app
    case recording       // Engine alive, NOT transcribing — ready for new burst
    case transcribing    // Engine alive + actively transcribing
    case processing      // Waiting for transcription result
    case completed
    case error
}

@Observable
@MainActor
final class KeyboardTranscriptionBridge {

    var state: BridgeState = .idle
    var result: String?
    var errorMessage: String?
    var showSilenceMessage: Bool = false

    /// Set by KeyboardContainerView to open URLs via the responder chain
    var onOpenURL: ((URL) -> Void)?

    /// Direct callback for inserting text into the text field.
    var onInsertText: ((String) -> Void)?

    /// Callback that replaces a previously-inserted partial transcript with a
    /// new one. The container view wires this up to delete the old characters
    /// from the proxy and insert the new text.
    var onReplacePartialText: ((_ oldText: String, _ newText: String) -> Void)?

    /// Callback that returns the text immediately before the cursor.
    /// Used to decide whether to prepend a space when starting a new burst
    /// so consecutive bursts don't run together (e.g. "todayHello" → "today Hello").
    var onGetContextBefore: (() -> String?)?

    /// The partial transcript text we've already inserted into the active text
    /// field, including any leading separator space we added at burst start.
    /// When a new partial arrives, we delete this and insert the new one.
    /// Cleared when a burst finalizes, is cancelled, or a new burst begins.
    private var insertedPartialText: String = ""

    /// Tracks the last delivered text to prevent duplicate delivery.
    private var lastDeliveredText: String?
    private var lastDeliveredAt: Date = .distantPast

    private var timeoutTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var verifyTask: Task<Void, Never>?

    // MARK: - Engine Liveness Tracking

    private var consecutiveVerifyFailures = 0
    private var lastConfirmedAliveAt: Date = .distantPast
    private var lastDeclaredDeadAt: Date = .distantPast

    private static let verifyGracePeriod: TimeInterval = 10.0
    private static let maxVerifyFailures = 3
    private static let declaredDeadCooldown: TimeInterval = 15.0

    // MARK: - Persistent Observers

    /// Call once when the keyboard appears. Sets up always-on Darwin observers.
    func startPersistentObservers() {
        // Listen for engine started
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.engineStarted
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.lastDeclaredDeadAt = .distantPast
                self.consecutiveVerifyFailures = 0
                self.lastConfirmedAliveAt = Date()

                switch self.state {
                case .idle, .error, .waitingForApp:
                    self.state = .transcribing
                    self.listenForCompletion()
                default:
                    break
                }
            }
        }

        // Listen for engine stopped
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.engineStopped
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.state != .processing && self.state != .completed {
                    self.state = .idle
                }
            }
        }

        // Listen for engine alive response
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.engineAliveResponse
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleAliveResponse()
            }
        }

        // Listen for partial transcript updates — replace the previously
        // inserted partial with the new text for live in-field preview.
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.partialTranscriptUpdated
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handlePartialUpdate()
            }
        }

        // Listen for silence (burst had no speech)
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.burstSilent
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.timeoutTask?.cancel()
                self.timeoutTask = nil

                self.consecutiveVerifyFailures = 0
                self.lastConfirmedAliveAt = Date()
                self.lastDeclaredDeadAt = .distantPast

                self.showSilenceMessage = true
                self.state = .recording

                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    self.showSilenceMessage = false
                }
            }
        }

        startHeartbeat()
    }

    // MARK: - Partial Transcript Handling

    /// Reads the latest partial transcript from shared defaults and replaces
    /// the previously-inserted partial in the text field with it.
    ///
    /// At the start of a burst (when `insertedPartialText` is empty) we peek
    /// at the existing context before the cursor and prepend a single space
    /// if it doesn't already end with whitespace or a newline — this keeps
    /// back-to-back bursts from running together (e.g. "todayHello").
    private func handlePartialUpdate() {
        AppGroupManager.shared.sharedDefaults.synchronize()
        let rawPartial = AppGroupManager.shared.partialTranscript

        // Only update while we're actively transcribing
        guard state == .transcribing else { return }

        // Never delete already-inserted partial text based on an empty partial.
        // Empty values can arrive from a race with clearPartialTranscript() in
        // finalizeBurst, or from the recognizer emitting an empty formattedString.
        // In both cases the authoritative final text arrives via
        // transcriptionComplete — wait for that instead of wiping the field.
        guard !rawPartial.isEmpty else { return }

        let effectiveNew = applyBurstSeparator(to: rawPartial)

        // Skip if nothing changed
        guard effectiveNew != insertedPartialText else { return }

        onReplacePartialText?(insertedPartialText, effectiveNew)
        insertedPartialText = effectiveNew

        // Receiving a partial update is a reliable liveness signal from the engine
        lastConfirmedAliveAt = Date()
        consecutiveVerifyFailures = 0
        lastDeclaredDeadAt = .distantPast
    }

    /// Returns the text we should actually insert for a given raw partial,
    /// applying a leading space if this burst needs a separator from the
    /// preceding content. Once set, the separator is preserved for the rest
    /// of the burst so subsequent partial diffs don't drop it.
    private func applyBurstSeparator(to rawPartial: String) -> String {
        guard !rawPartial.isEmpty else { return rawPartial }

        if insertedPartialText.isEmpty {
            // First partial of the burst — check if we need a leading space
            if needsLeadingSeparator() {
                return " " + rawPartial
            }
            return rawPartial
        }

        // Mid-burst: if we previously added a leading space, keep it
        if insertedPartialText.hasPrefix(" ") && !rawPartial.hasPrefix(" ") {
            return " " + rawPartial
        }
        return rawPartial
    }

    /// Returns `true` if the text immediately before the cursor doesn't end
    /// with whitespace or a newline, meaning a new burst should prepend a space.
    private func needsLeadingSeparator() -> Bool {
        guard let context = onGetContextBefore?() else { return false }
        guard let last = context.last else { return false }
        return !last.isWhitespace && !last.isNewline
    }

    // MARK: - Verify Engine Alive

    func verifyEngineAlive() {
        guard state == .recording || state == .transcribing || state == .idle || state == .error else {
            return
        }

        // Skip verify during grace period after confirmed-alive contact
        let timeSinceConfirmed = Date().timeIntervalSince(lastConfirmedAliveAt)
        if timeSinceConfirmed < Self.verifyGracePeriod && (state == .recording || state == .transcribing) {
            return
        }

        // Skip verify during cooldown after declaring dead
        let timeSinceDead = Date().timeIntervalSince(lastDeclaredDeadAt)
        if timeSinceDead < Self.declaredDeadCooldown {
            return
        }

        DarwinNotificationCenter.shared.post(PKConstants.Notification.engineAliveRequest)

        verifyTask?.cancel()
        verifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard let self, !Task.isCancelled else { return }

            self.consecutiveVerifyFailures += 1

            if self.consecutiveVerifyFailures >= Self.maxVerifyFailures {
                if self.state == .recording || self.state == .transcribing {
                    self.state = .idle
                }
                self.lastDeclaredDeadAt = Date()
                self.consecutiveVerifyFailures = 0
            }
        }
    }

    private func handleAliveResponse() {
        verifyTask?.cancel()
        verifyTask = nil
        consecutiveVerifyFailures = 0
        lastConfirmedAliveAt = Date()
        lastDeclaredDeadAt = .distantPast

        AppGroupManager.shared.sharedDefaults.synchronize()

        switch state {
        case .idle, .error:
            if AppGroupManager.shared.isTranscribing {
                state = .transcribing
                listenForCompletion()
            } else if AppGroupManager.shared.dictationInProgress {
                state = .recording
                listenForCompletion()
            }
        case .recording:
            if AppGroupManager.shared.isTranscribing {
                state = .transcribing
                listenForCompletion()
            }
        case .transcribing:
            break
        case .waitingForApp:
            if AppGroupManager.shared.isTranscribing {
                state = .transcribing
                listenForCompletion()
            } else {
                state = .recording
            }
        case .processing, .completed:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }

                AppGroupManager.shared.sharedDefaults.synchronize()

                switch self.state {
                case .idle, .error:
                    if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
                        self.deliverResult(text)
                        break
                    }
                    let engineMightBeAlive = AppGroupManager.shared.dictationInProgress
                        && AppGroupManager.shared.isEngineLikelyAlive
                    if engineMightBeAlive {
                        self.verifyEngineAlive()
                    }
                case .recording, .transcribing:
                    if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
                        self.deliverResult(text)
                    } else {
                        self.verifyEngineAlive()
                    }
                case .processing:
                    if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
                        self.deliverResult(text)
                    }
                case .completed, .waitingForApp:
                    break
                }
            }
        }
    }

    // MARK: - Start Dictation

    /// Start a transcription burst when the engine is KNOWN to be alive.
    /// Skips app switching — just sends the Darwin notification.
    func startTranscribingOnly() {
        showSilenceMessage = false
        lastDeliveredText = nil
        insertedPartialText = ""
        AppGroupManager.shared.clearPartialTranscript()
        DarwinNotificationCenter.shared.post(PKConstants.Notification.startTranscribing)
        state = .transcribing
        listenForCompletion()
    }

    /// Open the main app via URL scheme to start the audio engine for the first time.
    func startDictation() {
        AppGroupManager.shared.sharedDefaults.synchronize()

        showSilenceMessage = false
        lastDeliveredText = nil
        insertedPartialText = ""
        AppGroupManager.shared.clearPartialTranscript()

        // If the engine is already confirmed alive, skip the app switch
        let recentlyConfirmedAlive = Date().timeIntervalSince(lastConfirmedAliveAt) < Self.verifyGracePeriod
        if recentlyConfirmedAlive
            && AppGroupManager.shared.dictationInProgress
            && AppGroupManager.shared.isEngineLikelyAlive {
            DarwinNotificationCenter.shared.post(PKConstants.Notification.startTranscribing)
            state = .transcribing
            listenForCompletion()
            return
        }

        // Engine not alive — clear stale result state
        AppGroupManager.shared.isTranscribing = false
        AppGroupManager.shared.pendingDictationText = nil
        AppGroupManager.shared.clearTranscriptionResult()

        result = nil
        errorMessage = nil

        AppGroupManager.shared.dictationInProgress = true

        // Open main app
        onOpenURL?(PKConstants.URLScheme.dictateURL)
        state = .waitingForApp
    }

    // MARK: - Stop Dictation

    /// Tells the main app to stop the current transcription burst.
    /// The audio engine stays alive for the next burst.
    func stopDictation() {
        state = .processing

        DarwinNotificationCenter.shared.post(PKConstants.Notification.stopRecording)

        listenForCompletion()

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PKConstants.Audio.fallbackTimeoutSeconds))
            guard let self, self.state == .processing else { return }
            self.errorMessage = "Transcription timed out. Try again."
            self.state = .error
        }
    }

    // MARK: - Cancel (current burst only, keep engine alive)

    func cancelTranscription() {
        timeoutTask?.cancel()
        timeoutTask = nil
        verifyTask?.cancel()
        verifyTask = nil

        // Delete any partial text we've already inserted into the text field
        if !insertedPartialText.isEmpty {
            onReplacePartialText?(insertedPartialText, "")
            insertedPartialText = ""
        }

        // Tell main app to stop the current burst without shutting down the engine
        DarwinNotificationCenter.shared.post(PKConstants.Notification.stopRecording)
        AppGroupManager.shared.isTranscribing = false
        AppGroupManager.shared.clearPartialTranscript()
        AppGroupManager.shared.pendingDictationText = nil

        state = .recording
        result = nil
        errorMessage = nil
    }

    /// Full cancel — stops the audio engine and resets everything.
    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        verifyTask?.cancel()
        verifyTask = nil

        DarwinNotificationCenter.shared.post(PKConstants.Notification.stopEngine)
        AppGroupManager.shared.clearPendingDictation()

        state = .idle
        result = nil
        errorMessage = nil
    }

    // MARK: - Check on Keyboard Reappear

    func checkForPendingResult() {
        AppGroupManager.shared.sharedDefaults.synchronize()

        if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
            deliverResult(text)
            return
        }

        if let error = AppGroupManager.shared.readTranscriptionError() {
            errorMessage = error
            AppGroupManager.shared.clearTranscriptionResult()
            state = .error
            return
        }

        if AppGroupManager.shared.dictationInProgress
            && AppGroupManager.shared.isEngineLikelyAlive {
            consecutiveVerifyFailures = 0
            lastDeclaredDeadAt = .distantPast
            listenForCompletion()
            verifyEngineAlive()
        } else if AppGroupManager.shared.dictationInProgress {
            // Stale flag — clean up
            AppGroupManager.shared.dictationInProgress = false
            AppGroupManager.shared.engineStartedAt = nil
            AppGroupManager.shared.isTranscribing = false
        }
    }

    // MARK: - Completion Listener

    private func listenForCompletion() {
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.transcriptionComplete
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleTranscriptionComplete()
            }
        }
    }

    private func handleTranscriptionComplete() {
        timeoutTask?.cancel()
        timeoutTask = nil

        AppGroupManager.shared.sharedDefaults.synchronize()

        if let error = AppGroupManager.shared.readTranscriptionError() {
            errorMessage = error
            state = .error
            AppGroupManager.shared.clearTranscriptionResult()
            return
        }

        if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
            deliverResult(text)
        } else {
            // Retry a few times — cross-process writes can be slightly delayed
            Task { @MainActor [weak self] in
                for _ in 1...5 {
                    try? await Task.sleep(for: .milliseconds(100))
                    AppGroupManager.shared.sharedDefaults.synchronize()
                    if let text = AppGroupManager.shared.consumePendingDictationText(), !text.isEmpty {
                        self?.deliverResult(text)
                        return
                    }
                }
                if self?.state == .processing {
                    self?.errorMessage = "No transcription result received."
                    self?.state = .error
                }
            }
        }
    }

    /// Delivers the transcribed text to the text field. If partial text has
    /// already been inserted live during the burst, the partial is replaced
    /// with the final (possibly re-punctuated) result. If we added a leading
    /// separator space at burst start, it's preserved in the final text so
    /// consecutive bursts stay readable.
    private func deliverResult(_ text: String) {
        // Deduplication: skip if we just delivered this exact text recently
        if text == lastDeliveredText && Date().timeIntervalSince(lastDeliveredAt) < 3.0 {
            return
        }
        lastDeliveredText = text
        lastDeliveredAt = Date()

        // Preserve the burst-start leading space (if any) in the final result
        var finalText = text
        if insertedPartialText.hasPrefix(" ") && !text.hasPrefix(" ") {
            finalText = " " + text
        }

        // If a partial was already inserted live, replace it with the final text.
        // Otherwise, insert the text fresh — and still check whether a
        // separator is needed in the empty-partial case.
        if !insertedPartialText.isEmpty {
            onReplacePartialText?(insertedPartialText, finalText)
            insertedPartialText = ""
            result = nil
        } else if let onInsertText {
            var textToInsert = text
            if needsLeadingSeparator() && !text.hasPrefix(" ") {
                textToInsert = " " + text
            }
            onInsertText(textToInsert)
            result = nil
        } else {
            result = text
        }

        AppGroupManager.shared.clearPartialTranscript()

        consecutiveVerifyFailures = 0
        lastConfirmedAliveAt = Date()
        lastDeclaredDeadAt = .distantPast

        state = .completed
        AppGroupManager.shared.pendingDictationText = nil
    }
}

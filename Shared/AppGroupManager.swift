import Foundation

final class AppGroupManager: @unchecked Sendable {

    static let shared = AppGroupManager()

    let sharedDefaults: UserDefaults

    private init() {
        guard let defaults = UserDefaults(suiteName: PKConstants.appGroupID) else {
            fatalError("Failed to create shared UserDefaults for App Group: \(PKConstants.appGroupID)")
        }
        self.sharedDefaults = defaults
    }

    // MARK: - Transcription Result

    func writeTranscriptionError(_ error: String) {
        sharedDefaults.set("", forKey: PKConstants.SharedDefaults.pendingDictationText)
        sharedDefaults.set(error, forKey: PKConstants.SharedDefaults.transcriptionError)
        sharedDefaults.synchronize()
    }

    func readTranscriptionError() -> String? {
        let error = sharedDefaults.string(forKey: PKConstants.SharedDefaults.transcriptionError)
        return (error?.isEmpty == false) ? error : nil
    }

    func clearTranscriptionResult() {
        sharedDefaults.removeObject(forKey: PKConstants.SharedDefaults.pendingDictationText)
        sharedDefaults.removeObject(forKey: PKConstants.SharedDefaults.transcriptionError)
        sharedDefaults.synchronize()
    }

    // MARK: - Pending Dictation (main app → keyboard handoff)

    var pendingDictationText: String? {
        get { sharedDefaults.string(forKey: PKConstants.SharedDefaults.pendingDictationText) }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.pendingDictationText)
            sharedDefaults.synchronize()
        }
    }

    /// Atomically reads and clears the pending dictation text. Prevents duplicate delivery.
    func consumePendingDictationText() -> String? {
        sharedDefaults.synchronize()
        let text = sharedDefaults.string(forKey: PKConstants.SharedDefaults.pendingDictationText)
        if text != nil && !(text?.isEmpty ?? true) {
            sharedDefaults.removeObject(forKey: PKConstants.SharedDefaults.pendingDictationText)
            sharedDefaults.synchronize()
        }
        return text
    }

    func clearPendingDictation() {
        sharedDefaults.removeObject(forKey: PKConstants.SharedDefaults.pendingDictationText)
        sharedDefaults.synchronize()
    }

    // MARK: - Partial Transcript (live preview during recording)

    var partialTranscript: String {
        get { sharedDefaults.string(forKey: PKConstants.SharedDefaults.partialTranscript) ?? "" }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.partialTranscript)
            // No synchronize — high-frequency write, eventual consistency is fine
        }
    }

    func clearPartialTranscript() {
        sharedDefaults.removeObject(forKey: PKConstants.SharedDefaults.partialTranscript)
        sharedDefaults.synchronize()
    }

    // MARK: - Engine State

    var dictationInProgress: Bool {
        get { sharedDefaults.bool(forKey: PKConstants.SharedDefaults.dictationInProgress) }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.dictationInProgress)
            sharedDefaults.synchronize()
        }
    }

    var isTranscribing: Bool {
        get { sharedDefaults.bool(forKey: PKConstants.SharedDefaults.isTranscribing) }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.isTranscribing)
            sharedDefaults.synchronize()
        }
    }

    var engineStartedAt: Date? {
        get { sharedDefaults.object(forKey: PKConstants.SharedDefaults.engineStartedAt) as? Date }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.engineStartedAt)
            sharedDefaults.synchronize()
        }
    }

    /// Returns true if engine was started within the recording timeout window.
    var isEngineLikelyAlive: Bool {
        guard let started = engineStartedAt else { return false }
        let elapsed = Date().timeIntervalSince(started)
        return elapsed < (PKConstants.Audio.recordingTimeoutSeconds + 30)
    }

    // MARK: - Audio Level (main app → keyboard for waveform)

    var audioLevel: Float {
        get { sharedDefaults.float(forKey: PKConstants.SharedDefaults.audioLevel) }
        set {
            sharedDefaults.set(newValue, forKey: PKConstants.SharedDefaults.audioLevel)
            // No synchronize — high frequency
        }
    }
}

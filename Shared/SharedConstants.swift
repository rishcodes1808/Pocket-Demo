import Foundation

enum PKConstants {

    // MARK: - App Group

    static let appGroupID = "group.com.sample.Pocket-Demo"

    // MARK: - Bundle IDs

    static let mainAppBundleID = "com.sample.Pocket-Demo"
    static let keyboardBundleID = "com.sample.Pocket-Demo.Pocket-Keyboard"

    // MARK: - URL Scheme

    enum URLScheme {
        static let scheme = "pocketdemo"
        static let dictateHost = "dictate"
        static let dictateURL = URL(string: "pocketdemo://dictate")!
    }

    // MARK: - Darwin Notification Names

    enum Notification {
        /// Main app → keyboard: transcription result is ready (read pendingDictationText)
        static let transcriptionComplete = "com.sample.PocketDemo.transcriptionResult"
        /// Main app → keyboard: audio engine started and ready for transcription bursts
        static let engineStarted = "com.sample.PocketDemo.engineStarted"
        /// Main app → keyboard: audio engine stopped entirely
        static let engineStopped = "com.sample.PocketDemo.engineStopped"
        /// Keyboard → main app: stop current transcription burst (keep engine alive)
        static let stopRecording = "com.sample.PocketDemo.stopRecording"
        /// Keyboard → main app: start a new transcription burst on running engine
        static let startTranscribing = "com.sample.PocketDemo.startTranscribing"
        /// Keyboard → main app: stop audio engine entirely
        static let stopEngine = "com.sample.PocketDemo.stopEngine"
        /// Keyboard → main app: "are you alive?" liveness check
        static let engineAliveRequest = "com.sample.PocketDemo.engineAliveRequest"
        /// Main app → keyboard: "yes, I'm alive" response to liveness check
        static let engineAliveResponse = "com.sample.PocketDemo.engineAliveResponse"
        /// Main app → keyboard: transcription burst had no speech
        static let burstSilent = "com.sample.PocketDemo.burstSilent"
        /// Main app → keyboard: partial transcript updated (frequent, during burst)
        static let partialTranscriptUpdated = "com.sample.PocketDemo.partialTranscriptUpdated"
    }

    // MARK: - Shared UserDefaults Keys

    enum SharedDefaults {
        static let pendingDictationText = "pk_pendingDictationText"
        static let partialTranscript = "pk_partialTranscript"
        static let transcriptionError = "pk_transcriptionError"
        static let dictationInProgress = "pk_dictationInProgress"
        static let isTranscribing = "pk_isTranscribing"
        static let engineStartedAt = "pk_engineStartedAt"
        static let audioLevel = "pk_audioLevel"
    }

    // MARK: - Audio

    enum Audio {
        static let fallbackTimeoutSeconds: TimeInterval = 10
        static let recordingTimeoutSeconds: TimeInterval = 1200 // 20 minutes
    }
}

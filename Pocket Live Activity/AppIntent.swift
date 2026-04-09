import AppIntents
import Foundation

/// Intent fired when the user taps the Stop button on the dictation Live Activity.
/// Runs in the widget extension process and posts a Darwin notification that the
/// main app's LiveTranscriptionManager observes to actually stop the audio engine.
struct StopEngineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop Dictation" }
    static var description: IntentDescription { "Stops the Pocket Demo audio engine." }

    /// Stopping the engine does not require foregrounding the app.
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        DarwinNotificationCenter.shared.post(PKConstants.Notification.stopEngine)
        return .result()
    }
}

#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Manages the Live Activity lifecycle for the dictation engine.
///
/// - Starts a Live Activity when the audio engine starts
/// - Updates it on every state transition (recording/transcribing/processing)
/// - Runs a 5-minute auto-dismiss timer when the engine stops
/// - Listens for the Stop button tap from the Live Activity's App Intent
@Observable
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<TranscriptionActivityAttributes>?
    private var autoDismissTask: Task<Void, Never>?
    private var lastAudioLevelUpdate: Date = .distantPast

    /// Auto-dismiss delay after engine stops (5 minutes).
    private static let autoDismissDelay: TimeInterval = 300

    /// Minimum interval between audio level updates (ActivityKit rate limit).
    /// Must be shorter than staleDateInterval so we refresh the stale date
    /// before it expires while actively recording.
    private static let audioLevelThrottle: TimeInterval = 2.0

    /// How far in the future to set staleDate on activity updates.
    /// If the app is killed and can't send updates, the system will mark the
    /// activity as stale after this duration, showing idle state in the widget.
    private static let staleDateInterval: TimeInterval = 5.0

    /// The last known state string from updateForEngineState().
    /// Used by updateAudioLevel() to construct new ContentStates without
    /// re-reading shared UserDefaults.
    private var lastKnownState: String = "idle"

    private init() {
        // Listen for stop engine notifications from the Live Activity's
        // StopEngineIntent (tapped from lock screen / Dynamic Island).
        // LiveTranscriptionManager also observes stopEngine, so we don't
        // need to call it directly here — just cleanup our activity.
        DarwinNotificationCenter.shared.observe(
            PKConstants.Notification.stopEngine
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endActivity()
            }
        }

        // Clean up any stale activities from a previous crash
        cleanupStaleActivities()
    }

    // MARK: - State Updates (called by LiveTranscriptionManager)

    /// Called at every engine state transition. Maps the engine state to the
    /// Live Activity content state and starts/updates/ends the activity.
    func updateForEngineState(_ managerState: String) {
        lastKnownState = managerState
        switch managerState {
        case "recording":
            startOrUpdate(transcriptionState: .recording, isRunning: true)
            cancelAutoDismiss()
        case "transcribing":
            startOrUpdate(transcriptionState: .transcribing, isRunning: true)
            cancelAutoDismiss()
        case "finalizing":
            startOrUpdate(transcriptionState: .processing, isRunning: true)
        case "completed":
            // After completion, engine is still alive — return to recording state
            startOrUpdate(transcriptionState: .recording, isRunning: true)
        case "idle":
            startOrUpdate(transcriptionState: .idle, isRunning: false)
            beginAutoDismissCountdown()
        case "error":
            startOrUpdate(transcriptionState: .idle, isRunning: false)
            beginAutoDismissCountdown()
        default:
            break
        }
    }

    /// Throttled audio level update — at most once every 2 seconds due to
    /// ActivityKit's internal rate limit.
    func updateAudioLevel(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelUpdate) >= Self.audioLevelThrottle else { return }
        lastAudioLevelUpdate = now

        guard let activity = currentActivity else { return }

        let transcriptionState: TranscriptionActivityAttributes.ContentState.TranscriptionState
        let isRunning: Bool

        switch lastKnownState {
        case "recording":    transcriptionState = .recording;    isRunning = true
        case "transcribing": transcriptionState = .transcribing; isRunning = true
        case "finalizing":   transcriptionState = .processing;   isRunning = true
        case "completed":    transcriptionState = .recording;    isRunning = true
        default:             transcriptionState = .idle;         isRunning = false
        }

        let contentState = TranscriptionActivityAttributes.ContentState(
            transcriptionState: transcriptionState,
            audioLevel: level,
            isEngineRunning: isRunning
        )

        let staleDate = isRunning ? Date().addingTimeInterval(Self.staleDateInterval) : nil

        Task {
            await activity.update(
                ActivityContent(state: contentState, staleDate: staleDate)
            )
        }
    }

    // MARK: - Activity Lifecycle

    private func startOrUpdate(
        transcriptionState: TranscriptionActivityAttributes.ContentState.TranscriptionState,
        isRunning: Bool
    ) {
        let contentState = TranscriptionActivityAttributes.ContentState(
            transcriptionState: transcriptionState,
            audioLevel: 0,
            isEngineRunning: isRunning
        )

        let staleDate = isRunning ? Date().addingTimeInterval(Self.staleDateInterval) : nil

        if let activity = currentActivity {
            Task {
                await activity.update(
                    ActivityContent(state: contentState, staleDate: staleDate)
                )
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return
            }

            do {
                let attributes = TranscriptionActivityAttributes()
                let content = ActivityContent(state: contentState, staleDate: staleDate)
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                // Could not start Live Activity — silently ignore
            }
        }
    }

    /// Immediately dismisses the Live Activity.
    func endActivity() {
        guard let activity = currentActivity else { return }

        let finalState = TranscriptionActivityAttributes.ContentState(
            transcriptionState: .idle,
            audioLevel: 0,
            isEngineRunning: false
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
        cancelAutoDismiss()
    }

    // MARK: - Auto-Dismiss Timer

    private func beginAutoDismissCountdown() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoDismissDelay))
            guard let self, !Task.isCancelled else { return }

            if !AppGroupManager.shared.dictationInProgress {
                self.endActivity()
            }
        }
    }

    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }

    // MARK: - Stale Activity Cleanup

    /// Ends any activities that survived an app crash.
    private func cleanupStaleActivities() {
        let staleActivities = Activity<TranscriptionActivityAttributes>.activities
        guard !staleActivities.isEmpty else { return }

        let finalState = TranscriptionActivityAttributes.ContentState(
            transcriptionState: .idle,
            audioLevel: 0,
            isEngineRunning: false
        )

        for activity in staleActivities {
            Task {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
        currentActivity = nil
    }
}
#endif

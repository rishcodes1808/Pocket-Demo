#if canImport(ActivityKit)
import ActivityKit
import SwiftUI

/// Data model for the Pocket Demo dictation Live Activity.
///
/// This file is duplicated between the main app and the Pocket Live Activity
/// widget extension. The `activityAttributesName` is overridden to a stable
/// string so ActivityKit can match the type across the two separate Swift modules.
struct TranscriptionActivityAttributes: ActivityAttributes {

    /// Stable identifier used by ActivityKit to match this type across the
    /// main app and widget extension modules.
    static var activityAttributesName: String { "TranscriptionActivityAttributes" }

    /// Dynamic state that changes during the activity's lifetime.
    struct ContentState: Codable, Hashable {

        enum TranscriptionState: String, Codable, Hashable {
            /// Audio engine alive, waiting for user to start a burst
            case recording
            /// Actively recognizing speech
            case transcribing
            /// Finalizing / sending to cloud
            case processing
            /// Engine stopped — activity visible during 5-min countdown
            case idle
        }

        var transcriptionState: TranscriptionState
        /// Normalized audio level (0.0–1.0) for waveform visualization
        var audioLevel: Float
        /// Whether the audio engine is currently running
        var isEngineRunning: Bool

        init(
            transcriptionState: TranscriptionState,
            audioLevel: Float = 0,
            isEngineRunning: Bool = true
        ) {
            self.transcriptionState = transcriptionState
            self.audioLevel = audioLevel
            self.isEngineRunning = isEngineRunning
        }
    }

    init() {}
}

// MARK: - UI Helpers

extension TranscriptionActivityAttributes.ContentState.TranscriptionState {

    /// Full label for Lock Screen and expanded Dynamic Island
    var label: String {
        switch self {
        case .recording:    return "Ready to Dictate"
        case .transcribing: return "Listening\u{2026}"
        case .processing:   return "Processing\u{2026}"
        case .idle:         return "Engine Off"
        }
    }

    /// Short label for compact Dynamic Island trailing
    var shortLabel: String {
        switch self {
        case .recording:    return "ON"
        case .transcribing: return "LIVE"
        case .processing:   return "\u{2026}"
        case .idle:         return "OFF"
        }
    }

    /// SF Symbol name for the state
    var iconName: String {
        switch self {
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .processing:   return "ellipsis.circle"
        case .idle:         return "mic.slash"
        }
    }

    /// Tint color for the state icon
    var tintColor: Color {
        switch self {
        case .recording:    return .green
        case .transcribing: return .red
        case .processing:   return .yellow
        case .idle:         return .gray
        }
    }
}
#endif

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// The dictation Live Activity shown on the Lock Screen and Dynamic Island
/// while the Pocket Demo audio engine is running.
struct TranscriptionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            // Lock Screen / notification banner UI
            TranscriptionLockScreenView(state: Self.state(context))
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            let state = Self.state(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: state.transcriptionState.iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(state.transcriptionState.tintColor)
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: state.transcriptionState == .transcribing
                            )
                        Text(state.transcriptionState.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.isEngineRunning {
                        Button(intent: StopEngineIntent()) {
                            Label("Stop", systemImage: "stop.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.red))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(.gray)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.gray.opacity(0.3)))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.transcriptionState == .transcribing {
                        AudioWaveformView(level: state.audioLevel)
                            .frame(height: 24)
                            .padding(.horizontal, 8)
                    } else if state.transcriptionState == .recording {
                        Text("Tap Speak in the keyboard to start dictating")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } compactLeading: {
                Image(systemName: state.transcriptionState.iconName)
                    .foregroundStyle(state.transcriptionState.tintColor)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: state.transcriptionState == .transcribing
                    )
            } compactTrailing: {
                Text(state.transcriptionState.shortLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.transcriptionState.tintColor)
            } minimal: {
                Image(systemName: state.transcriptionState.iconName)
                    .foregroundStyle(state.transcriptionState.tintColor)
            }
            .keylineTint(state.transcriptionState.tintColor)
        }
    }

    /// Returns the current content state, defaulting to `.idle` if the activity is stale.
    private static func state(
        _ context: ActivityViewContext<TranscriptionActivityAttributes>
    ) -> TranscriptionActivityAttributes.ContentState {
        if context.isStale {
            return TranscriptionActivityAttributes.ContentState(
                transcriptionState: .idle,
                audioLevel: 0,
                isEngineRunning: false
            )
        }
        return context.state
    }
}

// MARK: - Lock Screen View

struct TranscriptionLockScreenView: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.transcriptionState.tintColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: state.transcriptionState.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(state.transcriptionState.tintColor)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: state.transcriptionState == .transcribing
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Pocket Demo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(state.transcriptionState.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if state.transcriptionState == .transcribing {
                AudioWaveformView(level: state.audioLevel)
                    .frame(width: 60, height: 28)
            }

            if state.isEngineRunning {
                Button(intent: StopEngineIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Audio Waveform

/// Simple animated bars that respond to the audio level.
struct AudioWaveformView: View {
    let level: Float

    private static let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: level)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = CGFloat(Self.barCount - 1) / 2.0
        let distance = abs(CGFloat(index) - center)
        let envelope = 1.0 - (distance / center) * 0.5
        let maxHeight: CGFloat = 20
        let minHeight: CGFloat = 4
        let normalized = CGFloat(max(0, min(level, 1)))
        return minHeight + (maxHeight - minHeight) * normalized * envelope
    }
}

// MARK: - Previews

extension TranscriptionActivityAttributes {
    fileprivate static var preview: TranscriptionActivityAttributes {
        TranscriptionActivityAttributes()
    }
}

extension TranscriptionActivityAttributes.ContentState {
    fileprivate static var transcribing: TranscriptionActivityAttributes.ContentState {
        .init(transcriptionState: .transcribing, audioLevel: 0.6, isEngineRunning: true)
    }
    fileprivate static var recording: TranscriptionActivityAttributes.ContentState {
        .init(transcriptionState: .recording, audioLevel: 0, isEngineRunning: true)
    }
    fileprivate static var idle: TranscriptionActivityAttributes.ContentState {
        .init(transcriptionState: .idle, audioLevel: 0, isEngineRunning: false)
    }
}

#Preview("Lock Screen", as: .content, using: TranscriptionActivityAttributes.preview) {
    TranscriptionLiveActivity()
} contentStates: {
    TranscriptionActivityAttributes.ContentState.transcribing
    TranscriptionActivityAttributes.ContentState.recording
    TranscriptionActivityAttributes.ContentState.idle
}

import SwiftUI
import Speech
import AVFoundation

/// Shown when the keyboard extension opens the main app via the `pocketdemo://dictate`
/// URL scheme. Starts the audio engine and then shows instructions asking the user
/// to switch back to the previous app. The engine runs in the background via
/// LiveTranscriptionManager.shared while the user dictates from the keyboard.
struct SwitchBackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engineStarted = false
    @State private var permissionError: String?

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let permissionError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("Permission required")
                        .font(.title2.bold())
                    Text(permissionError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }
            } else if engineStarted {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: engineStarted)

                    Text("Dictation Active")
                        .font(.title.bold())

                    Text("Switch back to your app and tap \u{201C}Speak\u{201D} in the Pocket Keyboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Starting engine…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            startEngine()
        }
    }

    private func startEngine() {
        // Verify permissions first
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micGranted = AVAudioApplication.shared.recordPermission == .granted

        guard speechStatus == .authorized else {
            permissionError = "Speech recognition permission is required. Please enable it in Settings."
            return
        }
        guard micGranted else {
            permissionError = "Microphone permission is required. Please enable it in Settings."
            return
        }

        // Start the engine
        LiveTranscriptionManager.shared.startRecording()

        // Wait briefly for the engine to report "recording" or "transcribing"
        Task { @MainActor in
            for _ in 0..<30 { // up to 3s
                try? await Task.sleep(for: .milliseconds(100))
                switch LiveTranscriptionManager.shared.state {
                case .recording, .transcribing:
                    engineStarted = true
                    return
                case .error(let message):
                    permissionError = message
                    return
                default:
                    continue
                }
            }
            // Timeout — still show the success state if no error
            if permissionError == nil {
                engineStarted = true
            }
        }
    }
}

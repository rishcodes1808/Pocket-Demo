import SwiftUI
import Speech
import AVFoundation

struct ContentView: View {
    @State private var testText: String = ""
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var micGranted: Bool = AVAudioApplication.shared.recordPermission == .granted

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("Pocket Keyboard")
                            .font(.title.bold())
                        Text("Custom keyboard with voice dictation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    // Permissions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.headline)

                        permissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            granted: micGranted
                        )

                        permissionRow(
                            icon: "waveform",
                            title: "Speech Recognition",
                            granted: speechStatus == .authorized
                        )

                        if !micGranted || speechStatus != .authorized {
                            Button {
                                requestPermissions()
                            } label: {
                                Text("Grant Permissions")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Setup instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup")
                            .font(.headline)

                        setupStep(number: 1, text: "Open Settings > General > Keyboard > Keyboards")
                        setupStep(number: 2, text: "Tap \"Add New Keyboard...\"")
                        setupStep(number: 3, text: "Select \"Pocket Keyboard\"")
                        setupStep(number: 4, text: "Tap \"Pocket Keyboard\" and enable \"Allow Full Access\"")
                        setupStep(number: 5, text: "When typing, hold the globe key and select Pocket Keyboard")

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Link to the Try it out page.
                    NavigationLink {
                        TryItOutView(text: $testText)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Try it out")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Test the Pocket Keyboard")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Pocket Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshPermissionStatus()
        }
    }

    // MARK: - Permission Helpers

    private func permissionRow(icon: String, title: String, granted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 24)
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
                .font(.body)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
        }
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                speechStatus = status
            }
        }

        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                micGranted = granted
            }
        }
    }

    private func refreshPermissionStatus() {
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        micGranted = AVAudioApplication.shared.recordPermission == .granted
    }
}

struct TryItOutView: View {
    @Binding var text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try it out")
                    .font(.headline)

                PocketKeyboardTextView(text: $text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(UIColor.separator), lineWidth: 0.5)
                    )

                Text("Tap the field above — the Pocket Keyboard opens automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Try it out")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}

import SwiftUI

/// Shown briefly when a transcription burst detects no speech.
struct SilenceBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("No speech detected")
                .font(.system(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

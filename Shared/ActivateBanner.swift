import SwiftUI

/// Shown when the audio engine is not running and we're outside the main app.
/// Tapping opens the main app via URL scheme to start the engine.
struct ActivateBanner: View {
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                Text("Activate Dictation")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(colorScheme == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.25))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark
                          ? Color(UIColor.systemGray5).opacity(0.3)
                          : Color(UIColor.systemGray5))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

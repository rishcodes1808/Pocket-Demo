import SwiftUI

/// Shown after the keyboard triggers a URL scheme to open the main app and
/// is waiting for the engine to start up.
struct WaitingBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(colorScheme == .dark ? .white : .primary)
            Text("Starting engine\u{2026}")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

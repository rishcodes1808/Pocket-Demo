import SwiftUI

struct ReadyBanner: View {
    let onSpeak: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSpeak) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                Text("Speak")
                    .font(.system(size: 16, weight: .semibold))
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
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(colorScheme == .dark
                                  ? Color.white.opacity(0.15)
                                  : Color.black.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        lightGenerator.prepare()
        softGenerator.prepare()
        mediumGenerator.prepare()
    }

    func keyTap() {
        lightGenerator.impactOccurred()
    }

    func trackpadTick() {
        softGenerator.impactOccurred(intensity: 0.4)
    }

    func longPress() {
        mediumGenerator.impactOccurred()
    }

    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

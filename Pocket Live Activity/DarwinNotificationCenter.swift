import Foundation

/// Thread-safe wrapper around CFNotificationCenter's Darwin notification API
/// for cross-process signaling between the main app and keyboard extension.
final class DarwinNotificationCenter: @unchecked Sendable {

    static let shared = DarwinNotificationCenter()

    private let center: CFNotificationCenter
    private var handlers: [String: @Sendable () -> Void] = [:]
    private let lock = NSLock()

    private init() {
        center = CFNotificationCenterGetDarwinNotifyCenter()
    }

    // MARK: - Post

    func post(_ name: String) {
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    // MARK: - Observe

    func observe(_ name: String, handler: @escaping @Sendable () -> Void) {
        // Remove any existing C-level observer for this name first.
        // CFNotificationCenterAddObserver accumulates observers — calling it N times
        // means the callback fires N times per notification.
        CFNotificationCenterRemoveObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )

        lock.lock()
        handlers[name] = handler
        lock.unlock()

        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, notificationName, _, _ in
                guard let observer else { return }
                let center = Unmanaged<DarwinNotificationCenter>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                if let name = notificationName?.rawValue as String? {
                    center.lock.lock()
                    let handler = center.handlers[name]
                    center.lock.unlock()
                    handler?()
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Remove

    func removeObserver(_ name: String) {
        CFNotificationCenterRemoveObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
        lock.lock()
        handlers.removeValue(forKey: name)
        lock.unlock()
    }

    func removeAllObservers() {
        CFNotificationCenterRemoveEveryObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque()
        )
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }
}

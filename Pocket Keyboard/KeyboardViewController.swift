import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {

    private var hostingController: UIHostingController<KeyboardContainerView>?
    private var keyboardProxy: KeyboardProxy!
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Audio Feedback

    var enableInputClicksWhenVisible: Bool { true }

    // MARK: - Keyboard Height

    /// Extension keyboard height. Base is 315pt to fit the transcription
    /// banner (which now has a partial-transcript preview line above the
    /// waveform), plus the four key rows and the safe-area inset.
    private var keyboardHeight: CGFloat {
        315 + view.safeAreaInsets.bottom
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        keyboardProxy = KeyboardProxy(proxy: textDocumentProxy)

        let keyboardView = KeyboardContainerView(
            proxy: keyboardProxy,
            needsInputModeSwitchKey: needsInputModeSwitchKey,
            hasFullAccess: hasFullAccess,
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            },
            openURL: { [weak self] url in
                self?.openApp(url: url)
            }
        )

        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hostingController

        let hc = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        hc.priority = .defaultHigh
        hc.isActive = true
        heightConstraint = hc
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // If there's already a pending transcription result when the keyboard
        // reappears (e.g., returning from the main app), insert it immediately.
        if let pendingText = AppGroupManager.shared.consumePendingDictationText(),
           !pendingText.isEmpty {
            textDocumentProxy.insertText(pendingText)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        heightConstraint?.constant = keyboardHeight
    }

    override func textWillChange(_ textInput: UITextInput?) {
        keyboardProxy?.updateProxy(textDocumentProxy)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        keyboardProxy?.updateProxy(textDocumentProxy)
    }

    // MARK: - Open Main App

    /// Opens a URL by walking the responder chain to find UIApplication.
    /// UIApplication.shared is unavailable in extensions, but the instance
    /// is reachable via the responder chain.
    private func openApp(url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }

        // Fallback: some iOS versions require performSelector approach
        var fallbackResponder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = fallbackResponder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            fallbackResponder = r.next
        }
    }
}

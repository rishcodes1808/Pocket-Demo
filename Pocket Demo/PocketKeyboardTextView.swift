import SwiftUI
import UIKit

/// A `UITextView` wrapper that forces the Pocket Keyboard as its input view
/// by setting `inputView` to a `UIHostingController` hosting `KeyboardContainerView`.
///
/// This bypasses the `UIInputViewController` / keyboard extension lifecycle
/// entirely — the keyboard's SwiftUI view is embedded directly in the main
/// app's process. A `KeyboardProxy(textView:)` bridges key taps from the
/// SwiftUI keyboard into the `UITextView`, so characters appear as the user
/// types and dictation results flow in via the same path.
///
/// Because this runs inside the main app, dictation bypasses the URL-scheme
/// handoff: the `openURL` callback starts `LiveTranscriptionManager` directly,
/// and the bridge picks up the `engineStarted` Darwin notification from the
/// same process.
struct PocketKeyboardTextView: UIViewRepresentable {
    @Binding var text: String

    /// Height of the embedded keyboard. The keyboard extension uses
    /// `291 + safeArea`, but in embedded mode there's no safe-area inset
    /// because the keyboard isn't pinned to the bottom of the screen. Bump the
    /// value so the key rows + transcription banner (now two-line) get enough
    /// vertical breathing room.
    private let keyboardHeight: CGFloat = 360

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PocketKeyboardTextView

        /// Hosting controller kept alive so the keyboard view persists.
        var keyboardHostingController: UIHostingController<KeyboardContainerView>?

        /// The last text value we pushed to or received from the binding.
        /// Used so `updateUIView` can distinguish a genuine external change
        /// (caller reassigned the binding) from a re-render that still holds
        /// a stale snapshot while a dictation burst is mid-flight.
        var lastSyncedText: String = ""

        init(parent: PocketKeyboardTextView) {
            self.parent = parent
            super.init()
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            lastSyncedText = newText
            parent.text = newText
        }
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.text = text
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isScrollEnabled = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none

        // Route key taps + dictation inserts directly into this text view
        let proxy = KeyboardProxy(textView: textView)

        // Build the keyboard view in embedded mode
        let keyboardView = KeyboardContainerView(
            proxy: proxy,
            needsInputModeSwitchKey: false,
            hasFullAccess: true,
            advanceToNextInputMode: { /* no-op in embedded mode */ },
            openURL: { url in
                // In embedded mode, we're already in the main app, so starting
                // dictation doesn't need to go through the URL scheme. Instead
                // of `UIApplication.open(...)`, we start the live transcription
                // manager directly. The bridge still transitions correctly
                // because `LiveTranscriptionManager.startRecording()` posts the
                // `engineStarted` Darwin notification the bridge is listening for.
                if url == PKConstants.URLScheme.dictateURL {
                    LiveTranscriptionManager.shared.startRecording()
                } else {
                    UIApplication.shared.open(url)
                }
            }
        )

        // Host the SwiftUI view in a UIHostingController and set it as the
        // text view's inputView so UIKit shows it whenever the text view
        // becomes first responder.
        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear
        let screenWidth = UIScreen.main.bounds.width
        hostingController.view.frame = CGRect(
            x: 0, y: 0,
            width: screenWidth,
            height: keyboardHeight
        )
        textView.inputView = hostingController.view

        context.coordinator.keyboardHostingController = hostingController
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Only sync the binding → view when the caller genuinely changed the
        // binding from outside (e.g. a Clear button reassigning `testText`).
        //
        // During a dictation burst, SwiftUI can re-render this representable
        // with a stale snapshot of `text` while the bridge is in the middle
        // of a delete-and-insert sequence. If we unconditionally wrote
        // `textView.text = text` here, we'd clobber the live partial that was
        // just inserted and reset the field to an older value, making it look
        // like earlier bursts get "cleared out".
        //
        // The coordinator tracks the last value we actually synced. We only
        // overwrite the text view when the binding has diverged from BOTH
        // that tracked value AND the current text view content — meaning the
        // change came from outside, not from our own delegate roundtrip.
        if text != context.coordinator.lastSyncedText && textView.text != text {
            textView.text = text
            context.coordinator.lastSyncedText = text
        }
    }
}

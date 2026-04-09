import UIKit

/// Abstraction over the text target that the keyboard types into.
///
/// In the **keyboard extension**, this wraps a `UITextDocumentProxy` — the
/// handle UIKit gives the extension for typing into the host app's focused
/// text field.
///
/// In the **main app** (when the keyboard view is embedded inside a
/// `UITextView.inputView`), this wraps the `UITextView` directly so taps on
/// the SwiftUI keys insert characters into the text view without going through
/// the extension's proxy at all.
@Observable
final class KeyboardProxy {
    private var proxy: UITextDocumentProxy?
    private weak var textView: UITextView?

    /// Backs the proxy with a keyboard extension's `UITextDocumentProxy`.
    init(proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    /// Backs the proxy with a `UITextView` for embedded / in-app usage.
    init(textView: UITextView) {
        self.textView = textView
    }

    func updateProxy(_ newProxy: UITextDocumentProxy) {
        self.proxy = newProxy
    }

    func insertText(_ text: String) {
        if let proxy {
            proxy.insertText(text)
        } else if let textView {
            textView.insertText(text)
        }
    }

    /// Replaces text immediately before the cursor while being conservative
    /// about what it deletes. This avoids backspacing into earlier user text
    /// if the host field normalized the previously-inserted partial (for
    /// example around pause/finalization boundaries).
    func replaceTrailingText(_ oldText: String, with newText: String) {
        guard !oldText.isEmpty else {
            insertText(newText)
            return
        }

        let contextBefore = documentContextBeforeInput ?? ""
        let deleteCount = Self.commonSuffixLength(between: contextBefore, and: oldText)

        if deleteCount > 0 {
            for _ in 0..<deleteCount {
                deleteBackward()
            }
        }

        let remainingContext = String(contextBefore.dropLast(deleteCount))
        let overlap = Self.suffixPrefixOverlapLength(
            suffixSource: remainingContext,
            prefixSource: newText
        )
        let textToInsert = String(newText.dropFirst(overlap))

        if !textToInsert.isEmpty {
            insertText(textToInsert)
        }
    }

    func deleteBackward() {
        if let proxy {
            proxy.deleteBackward()
        } else if let textView {
            textView.deleteBackward()
        }
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        if let proxy {
            proxy.adjustTextPosition(byCharacterOffset: offset)
        } else if let textView, let selectedRange = textView.selectedTextRange {
            if let newPosition = textView.position(from: selectedRange.start, offset: offset) {
                textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
            }
        }
    }

    var documentContextBeforeInput: String? {
        if let proxy { return proxy.documentContextBeforeInput }
        guard let textView, let selectedRange = textView.selectedTextRange else { return nil }
        let start = textView.beginningOfDocument
        guard let range = textView.textRange(from: start, to: selectedRange.start) else { return nil }
        return textView.text(in: range)
    }

    var documentContextAfterInput: String? {
        if let proxy { return proxy.documentContextAfterInput }
        guard let textView, let selectedRange = textView.selectedTextRange else { return nil }
        let end = textView.endOfDocument
        guard let range = textView.textRange(from: selectedRange.end, to: end) else { return nil }
        return textView.text(in: range)
    }

    var hasText: Bool {
        if let proxy { return proxy.hasText }
        return textView?.hasText ?? false
    }

    var returnKeyType: UIReturnKeyType {
        if let proxy { return proxy.returnKeyType ?? .default }
        return textView?.returnKeyType ?? .default
    }

    private static func commonSuffixLength(between lhs: String, and rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var index = 0

        while index < lhsChars.count && index < rhsChars.count {
            let lhsChar = lhsChars[lhsChars.count - 1 - index]
            let rhsChar = rhsChars[rhsChars.count - 1 - index]
            guard lhsChar == rhsChar else { break }
            index += 1
        }

        return index
    }

    private static func suffixPrefixOverlapLength(
        suffixSource: String,
        prefixSource: String
    ) -> Int {
        let suffixChars = Array(suffixSource)
        let prefixChars = Array(prefixSource)
        let maxOverlap = min(suffixChars.count, prefixChars.count)

        guard maxOverlap > 0 else { return 0 }

        for candidate in stride(from: maxOverlap, through: 1, by: -1) {
            let suffixSlice = suffixChars.suffix(candidate)
            let prefixSlice = prefixChars.prefix(candidate)
            if Array(suffixSlice) == Array(prefixSlice) {
                return candidate
            }
        }

        return 0
    }
}

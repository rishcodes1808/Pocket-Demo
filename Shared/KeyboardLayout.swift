import Foundation

enum NativeKeyboardMetrics {
    static let keyHeight: CGFloat = 42.0
    static let keyCornerRadius: CGFloat = 8.5
    static let interKeyGap: CGFloat = 6.5

    static let standardKeyWidth: CGFloat = 33.0
    static let wideKeyWidth: CGFloat = 45.0
    static let punctuationKeyWidth: CGFloat = 50.0
    static let modeSwitchKeyWidth: CGFloat = 84.0
    static let returnKeyWidth: CGFloat = 88.0
    static let narrowKeyWidth: CGFloat = 33.0

    static let letterFontSize: CGFloat = 23.0
    static let modifierFontSize: CGFloat = 16.0
}

enum ShiftState {
    case off
    case on
    case capsLock
}

enum KeyboardPage {
    case letters
    case numbers
    case symbols
}

enum CalloutAlignment {
    case left, center, right
}

struct KeyModel: Identifiable {
    let id = UUID()
    let label: String
    let type: KeyType
    var width: KeyWidth = .standard
    var calloutAlignment: CalloutAlignment = .center

    enum KeyType {
        case letter(String)
        case backspace
        case shift
        case returnKey
        case space
        case globe
        case numbers
        case symbols
        case letters
        case period
        case comma
    }

    enum KeyWidth {
        case standard
        case wide        // 1.5x (shift, backspace, #+=)
        case punctuation // 50pt — numeric/symbol third-row punctuation
        case modeSwitch  // 123 / ABC toggle in the bottom row
        case returnKey   // return / search key in the bottom row
        case space       // fills remaining
        case narrow      // period in bottom row
    }

    // MARK: - Key behavior

    var autorepeats: Bool {
        switch type {
        case .backspace, .returnKey: return true
        default: return false
        }
    }

    var actionOnPress: Bool {
        switch type {
        case .numbers, .symbols, .letters: return true
        default: return autorepeats
        }
    }

    var displaysCallout: Bool {
        switch type {
        case .letter: return true
        default: return false
        }
    }

    var supportsTrackpadMode: Bool {
        switch type {
        case .space: return true
        default: return false
        }
    }

    func displayTitle(shiftState: ShiftState) -> String? {
        switch type {
        case .letter(let char):
            switch shiftState {
            case .off: return char.lowercased()
            case .on, .capsLock: return char.uppercased()
            }
        case .numbers: return label
        case .symbols: return label
        case .letters: return label
        default: return nil
        }
    }

    var titleFontSize: CGFloat {
        switch type {
        case .numbers, .symbols, .letters, .space, .returnKey:
            return NativeKeyboardMetrics.modifierFontSize
        case .backspace: return 23
        default: return NativeKeyboardMetrics.letterFontSize
        }
    }

    var fixedWidth: CGFloat? {
        switch width {
        case .standard: return NativeKeyboardMetrics.standardKeyWidth
        case .wide: return NativeKeyboardMetrics.wideKeyWidth
        case .punctuation: return NativeKeyboardMetrics.punctuationKeyWidth
        case .modeSwitch: return NativeKeyboardMetrics.modeSwitchKeyWidth
        case .returnKey: return NativeKeyboardMetrics.returnKeyWidth
        case .space: return nil
        case .narrow: return NativeKeyboardMetrics.narrowKeyWidth
        }
    }

    func calloutTitleOffset(keyWidth: CGFloat) -> CGFloat {
        let calloutW = keyWidth * KeyCalloutShape.calloutScaleWidth
        switch calloutAlignment {
        case .left: return (calloutW - keyWidth) / 2
        case .right: return -(calloutW - keyWidth) / 2
        case .center: return 0
        }
    }
}

// MARK: - Layout Data

enum KeyboardLayoutData {

    static func makeRow(_ chars: String, width: KeyModel.KeyWidth = .standard) -> [KeyModel] {
        let arr = Array(chars)
        return arr.enumerated().map { i, c in
            var alignment: CalloutAlignment = .center
            if i == 0 { alignment = .left }
            if i == arr.count - 1 { alignment = .right }
            return KeyModel(label: String(c), type: .letter(String(c)), width: width, calloutAlignment: alignment)
        }
    }

    static let letterRows: [[KeyModel]] = [
        makeRow("QWERTYUIOP"),
        makeRow("ASDFGHJKL"),
        [
            KeyModel(label: "shift", type: .shift, width: .wide),
        ] + makeRow("ZXCVBNM") + [
            KeyModel(label: "delete", type: .backspace, width: .wide),
        ],
    ]

    static let numberRows: [[KeyModel]] = [
        makeRow("1234567890"),
        makeRow("-/:;()$&@\""),
        [
            KeyModel(label: "#+=", type: .symbols, width: .wide),
        ] + makeRow(".,?!'", width: .punctuation) + [
            KeyModel(label: "delete", type: .backspace, width: .wide),
        ],
    ]

    static let symbolRows: [[KeyModel]] = [
        makeRow("[]{}#%^*+="),
        makeRow("_\\|~<>\u{20AC}\u{00A3}\u{00A5}\u{2022}"),
        [
            KeyModel(label: "123", type: .numbers, width: .wide),
        ] + makeRow(".,?!'", width: .punctuation) + [
            KeyModel(label: "delete", type: .backspace, width: .wide),
        ],
    ]

    static func bottomRow(page: KeyboardPage, needsInputModeSwitchKey: Bool) -> [KeyModel] {
        var keys: [KeyModel] = [
            KeyModel(label: page == .letters ? "123" : "ABC",
                     type: page == .letters ? .numbers : .letters,
                     width: .modeSwitch),
        ]
        if needsInputModeSwitchKey {
            keys.append(KeyModel(label: "globe", type: .globe, width: .narrow))
        }
        keys.append(KeyModel(label: "space", type: .space, width: .space))
        keys.append(KeyModel(label: ".", type: .period, width: .narrow))
        keys.append(KeyModel(label: "return", type: .returnKey, width: .returnKey))
        return keys
    }
}

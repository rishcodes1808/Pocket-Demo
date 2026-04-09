import SwiftUI
import AVFAudio

struct KeyboardContainerView: View {
    let proxy: KeyboardProxy
    let needsInputModeSwitchKey: Bool
    let hasFullAccess: Bool
    let advanceToNextInputMode: () -> Void
    let openURL: (URL) -> Void

    // MARK: - Keyboard State

    @State private var shiftState: ShiftState = .off
    @State private var currentPage: KeyboardPage = .letters
    @State private var isTrackpadMode: Bool = false

    // MARK: - Dictation Bridge State

    @State private var bridge = KeyboardTranscriptionBridge()

    // MARK: - Auto-behaviors

    @State private var lastSpaceTime: Date?
    @State private var lastShiftTapTime: Date?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Constants

    private let interRowGap: CGFloat = 11
    private let edgeRowPadding: CGFloat = 6.75
    private let middleRowPadding: CGFloat = 26.5

    // MARK: - Permissions

    private var hasMicAccess: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 0 — Context-aware banner
            bannerView
                .padding(.horizontal)

            // Key rows area
            VStack(spacing: 0) {
                let rows = currentRows
                let totalKeyboardRows = rows.count + 1
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    KeyRow(
                        keys: row,
                        horizontalPadding: horizontalPadding(forRow: rowIndex),
                        topHitPadding: topHitPadding(forRow: rowIndex, totalRows: totalKeyboardRows),
                        bottomHitPadding: bottomHitPadding(forRow: rowIndex, totalRows: totalKeyboardRows),
                        shiftState: shiftState,
                        isTrackpadMode: isTrackpadMode,
                        returnKeyType: proxy.returnKeyType,
                        onKeyTap: handleKeyTap,
                        trackpadModeEnabled: handleTrackpadModeChange,
                        cursorAdjust: handleCursorAdjust
                    )
                }

                // Bottom row
                KeyRow(
                    keys: KeyboardLayoutData.bottomRow(
                        page: currentPage,
                        needsInputModeSwitchKey: needsInputModeSwitchKey
                    ),
                    horizontalPadding: edgeRowPadding,
                    topHitPadding: topHitPadding(forRow: totalKeyboardRows - 1, totalRows: totalKeyboardRows),
                    bottomHitPadding: bottomHitPadding(forRow: totalKeyboardRows - 1, totalRows: totalKeyboardRows),
                    shiftState: shiftState,
                    isTrackpadMode: isTrackpadMode,
                    returnKeyType: proxy.returnKeyType,
                    onKeyTap: handleKeyTap,
                    trackpadModeEnabled: handleTrackpadModeChange,
                    cursorAdjust: handleCursorAdjust
                )
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .onAppear {
            bridge.onOpenURL = openURL
            bridge.onInsertText = { text in
                proxy.insertText(text)
            }
            // Live partial-text replacement: delete the previously-inserted
            // partial and insert the new one without backspacing into earlier
            // user text if the host app normalized the trailing content.
            bridge.onReplacePartialText = { oldText, newText in
                proxy.replaceTrailingText(oldText, with: newText)
            }
            // Lets the bridge peek at the text immediately before the cursor
            // so it can decide whether to prepend a separator space at the
            // start of a new burst (so "todayHello" becomes "today Hello").
            bridge.onGetContextBefore = {
                proxy.documentContextBeforeInput
            }
            bridge.startPersistentObservers()
            bridge.checkForPendingResult()
            checkAutoCapitalization()
        }
        .onChange(of: bridge.result) { _, result in
            // Fallback: handle via SwiftUI .onChange in case callback wasn't set
            if let text = result, !text.isEmpty {
                proxy.insertText(text)
                bridge.result = nil
            }
        }
    }

    // MARK: - Banner View

    @ViewBuilder
    private var bannerView: some View {
        if !hasFullAccess {
            permissionBanner(
                icon: "lock.shield",
                title: "Enable Full Access for voice dictation",
                subtitle: "Settings \u{203A} Keyboards \u{203A} Pocket Keyboard \u{203A} Allow Full Access"
            )
        } else if !hasMicAccess {
            permissionBanner(
                icon: "mic.slash",
                title: "Microphone access required",
                subtitle: "Open the Pocket Demo app to grant permissions"
            )
        } else {
            switch bridge.state {
            case .transcribing:
                TranscribingBanner(
                    isProcessing: false,
                    onCancel: {
                        bridge.cancelTranscription()
                    },
                    onDone: {
                        bridge.stopDictation()
                    }
                )
            case .processing:
                TranscribingBanner(
                    isProcessing: true,
                    onCancel: {
                        bridge.cancelTranscription()
                    },
                    onDone: { }
                )
            case .recording, .completed:
                if bridge.showSilenceMessage {
                    SilenceBanner()
                } else {
                    ReadyBanner(
                        onSpeak: {
                            bridge.startTranscribingOnly()
                        }
                    )
                }
            case .waitingForApp:
                WaitingBanner()
            case .idle, .error:
                ActivateBanner {
                    bridge.startDictation()
                }
            }
        }
    }

    // MARK: - Permission Banner

    private func permissionBanner(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark
                      ? Color(UIColor.systemGray6)
                      : Color(UIColor.systemGray5))
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Current Rows

    private var currentRows: [[KeyModel]] {
        switch currentPage {
        case .letters: return KeyboardLayoutData.letterRows
        case .numbers: return KeyboardLayoutData.numberRows
        case .symbols: return KeyboardLayoutData.symbolRows
        }
    }

    private func horizontalPadding(forRow rowIndex: Int) -> CGFloat {
        rowIndex == 1 ? middleRowPadding : edgeRowPadding
    }

    private func topHitPadding(forRow rowIndex: Int, totalRows: Int) -> CGFloat {
        rowIndex == 0 ? 0 : interRowGap / 2
    }

    private func bottomHitPadding(forRow rowIndex: Int, totalRows: Int) -> CGFloat {
        rowIndex == totalRows - 1 ? 0 : interRowGap / 2
    }

    // MARK: - Key Handling

    private func handleKeyTap(_ key: KeyModel) {
        UIDevice.current.playInputClick()

        switch key.type {
        case .letter(let char):
            let text: String
            switch shiftState {
            case .off: text = char.lowercased()
            case .on:
                text = char.uppercased()
                shiftState = .off
            case .capsLock:
                text = char.uppercased()
            }
            proxy.insertText(text)
            checkAutoCapitalization()

        case .backspace:
            proxy.deleteBackward()
            checkAutoCapitalization()

        case .space:
            handleSpaceTap()

        case .returnKey:
            proxy.insertText("\n")
            checkAutoCapitalization()

        case .shift:
            handleShiftTap()

        case .globe:
            advanceToNextInputMode()

        case .numbers:
            currentPage = .numbers

        case .symbols:
            currentPage = .symbols

        case .letters:
            currentPage = .letters

        case .period:
            proxy.insertText(".")
            checkAutoCapitalization()

        case .comma:
            proxy.insertText(",")
        }
    }

    // MARK: - Shift Logic

    private func handleShiftTap() {
        let now = Date()
        if let lastTap = lastShiftTapTime, now.timeIntervalSince(lastTap) < 0.4 {
            shiftState = .capsLock
            lastShiftTapTime = nil
        } else {
            switch shiftState {
            case .off: shiftState = .on
            case .on: shiftState = .off
            case .capsLock: shiftState = .off
            }
            lastShiftTapTime = now
        }
    }

    // MARK: - Space / Double-Space Period Shortcut

    private func handleSpaceTap() {
        let now = Date()

        if let lastSpace = lastSpaceTime, now.timeIntervalSince(lastSpace) < 0.3 {
            if let context = proxy.documentContextBeforeInput, context.hasSuffix(" ") {
                proxy.deleteBackward()
                proxy.insertText(". ")
                shiftState = .on
                lastSpaceTime = nil
                return
            }
        }

        proxy.insertText(" ")
        lastSpaceTime = now
        checkAutoCapitalization()
    }

    // MARK: - Auto-Capitalization

    private func checkAutoCapitalization() {
        guard shiftState != .capsLock else { return }

        let context = proxy.documentContextBeforeInput ?? ""

        if context.isEmpty {
            shiftState = .on
            return
        }

        let trimmed = context.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            shiftState = .on
            return
        }

        if let last = trimmed.last, ".!?".contains(last) && context.hasSuffix(" ") {
            shiftState = .on
            return
        }

        if context.hasSuffix("\n") {
            shiftState = .on
            return
        }
    }

    // MARK: - Spacebar Trackpad

    private func handleTrackpadModeChange(_ enabled: Bool) {
        isTrackpadMode = enabled
        if enabled {
            HapticManager.shared.keyTap()
        }
    }

    private func handleCursorAdjust(_ delta: Int) {
        proxy.adjustTextPosition(byCharacterOffset: delta)
        HapticManager.shared.trackpadTick()
    }
}

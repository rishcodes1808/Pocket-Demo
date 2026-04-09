import SwiftUI

struct KeyRow: View {
    let keys: [KeyModel]
    let horizontalPadding: CGFloat
    let topHitPadding: CGFloat
    let bottomHitPadding: CGFloat
    let shiftState: ShiftState
    let isTrackpadMode: Bool
    let returnKeyType: UIReturnKeyType
    let onKeyTap: (KeyModel) -> Void
    let trackpadModeEnabled: ((Bool) -> Void)?
    let cursorAdjust: ((Int) -> Void)?

    init(
        keys: [KeyModel],
        horizontalPadding: CGFloat = 0,
        topHitPadding: CGFloat = 0,
        bottomHitPadding: CGFloat = 0,
        shiftState: ShiftState,
        isTrackpadMode: Bool = false,
        returnKeyType: UIReturnKeyType = .default,
        onKeyTap: @escaping (KeyModel) -> Void,
        trackpadModeEnabled: ((Bool) -> Void)? = nil,
        cursorAdjust: ((Int) -> Void)? = nil
    ) {
        self.keys = keys
        self.horizontalPadding = horizontalPadding
        self.topHitPadding = topHitPadding
        self.bottomHitPadding = bottomHitPadding
        self.shiftState = shiftState
        self.isTrackpadMode = isTrackpadMode
        self.returnKeyType = returnKeyType
        self.onKeyTap = onKeyTap
        self.trackpadModeEnabled = trackpadModeEnabled
        self.cursorAdjust = cursorAdjust
    }

    private var hasFlexibleKey: Bool {
        keys.contains(where: { $0.width == .space })
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                let leadingPadding = leadingHitPadding(for: index)
                let trailingPadding = trailingHitPadding(for: index)

                KeyButton(
                    key: key,
                    shiftState: shiftState,
                    isTrackpadMode: isTrackpadMode,
                    returnKeyType: returnKeyType,
                    action: { onKeyTap(key) },
                    trackpadModeEnabled: trackpadModeEnabled,
                    cursorAdjust: cursorAdjust,
                    leadingHitPadding: leadingPadding,
                    trailingHitPadding: trailingPadding,
                    topHitPadding: topHitPadding,
                    bottomHitPadding: bottomHitPadding
                )
                .frame(
                    width: fixedCellWidth(
                        for: key,
                        leadingPadding: leadingPadding,
                        trailingPadding: trailingPadding
                    ),
                    height: fixedCellHeight()
                )
                .frame(maxWidth: flexibleMaxWidth(for: key))
            }
        }
        .frame(maxWidth: hasFlexibleKey ? nil : .infinity)
        .background(edgeTapCatcher)
    }

    @ViewBuilder
    private var edgeTapCatcher: some View {
        if !hasFlexibleKey {
            HStack(spacing: 0) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { if let key = keys.first { onKeyTap(key) } }
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { if let key = keys.last { onKeyTap(key) } }
            }
        }
    }

    private func fixedCellWidth(
        for key: KeyModel,
        leadingPadding: CGFloat,
        trailingPadding: CGFloat
    ) -> CGFloat? {
        guard let visibleKeyWidth = key.fixedWidth else { return nil }
        return visibleKeyWidth + leadingPadding + trailingPadding
    }

    private func fixedCellHeight() -> CGFloat {
        NativeKeyboardMetrics.keyHeight + topHitPadding + bottomHitPadding
    }

    private func flexibleMaxWidth(for key: KeyModel) -> CGFloat? {
        switch key.width {
        case .space:
            return .infinity
        case .standard, .wide, .punctuation, .modeSwitch, .returnKey, .narrow:
            return nil
        }
    }

    private func leadingHitPadding(for index: Int) -> CGFloat {
        if index == 0 { return horizontalPadding }
        return effectiveGap(between: index - 1, and: index) / 2
    }

    private func trailingHitPadding(for index: Int) -> CGFloat {
        if index == keys.count - 1 { return horizontalPadding }
        return effectiveGap(between: index, and: index + 1) / 2
    }

    private func effectiveGap(between i: Int, and j: Int) -> CGFloat {
        let a = keys[i].width
        let b = keys[j].width
        if (a == .wide) != (b == .wide) {
            return 14.25
        }
        return NativeKeyboardMetrics.interKeyGap
    }
}

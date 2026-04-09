import SwiftUI

// MARK: - Key Callout Shape

struct KeyCalloutShape: Shape {
    static let calloutScaleWidth: CGFloat = 1.50
    static let bubbleHeightRatio: CGFloat = 1.18
    static let stemHeight: CGFloat = 3.0

    let alignment: CalloutAlignment

    func path(in rect: CGRect) -> Path {
        let kw = rect.width
        let kh = rect.height
        let bw = kw * Self.calloutScaleWidth
        let bh = kh * Self.bubbleHeightRatio
        let stemH = Self.stemHeight

        let bubbleRadius: CGFloat = 9.0
        let keyRadius = min(KeyView.cornerRadius, kh * 0.28)

        let bubbleMinX: CGFloat
        switch alignment {
        case .center: bubbleMinX = (kw - bw) / 2
        case .left:   bubbleMinX = 0
        case .right:  bubbleMinX = kw - bw
        }
        let bubbleMaxX = bubbleMinX + bw

        let bubbleTop = -(bh + stemH)
        let bubbleBot = -stemH

        var p = Path()

        p.move(to: CGPoint(x: bubbleMinX + bubbleRadius, y: bubbleTop))
        p.addLine(to: CGPoint(x: bubbleMaxX - bubbleRadius, y: bubbleTop))
        p.addArc(center: CGPoint(x: bubbleMaxX - bubbleRadius, y: bubbleTop + bubbleRadius),
                 radius: bubbleRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: bubbleMaxX, y: bubbleBot - bubbleRadius))
        p.addArc(center: CGPoint(x: bubbleMaxX - bubbleRadius, y: bubbleBot - bubbleRadius),
                 radius: bubbleRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        p.addLine(to: CGPoint(x: kw, y: 0))

        p.addLine(to: CGPoint(x: kw, y: kh - keyRadius))
        p.addQuadCurve(to: CGPoint(x: kw - keyRadius, y: kh),
                       control: CGPoint(x: kw, y: kh))
        p.addLine(to: CGPoint(x: keyRadius, y: kh))
        p.addQuadCurve(to: CGPoint(x: 0, y: kh - keyRadius),
                       control: CGPoint(x: 0, y: kh))

        p.addLine(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: bubbleMinX + bubbleRadius, y: bubbleBot))

        p.addArc(center: CGPoint(x: bubbleMinX + bubbleRadius, y: bubbleBot - bubbleRadius),
                 radius: bubbleRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: bubbleMinX, y: bubbleTop + bubbleRadius))
        p.addArc(center: CGPoint(x: bubbleMinX + bubbleRadius, y: bubbleTop + bubbleRadius),
                 radius: bubbleRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()

        return p
    }
}

// MARK: - Key View

struct KeyView: View {
    static let cornerRadius: CGFloat = NativeKeyboardMetrics.keyCornerRadius
    private static let autorepeatStartDelay: TimeInterval = 0.5
    private static let autorepeatInterval: TimeInterval = 0.1

    let key: KeyModel
    let shiftState: ShiftState
    let isTrackpadMode: Bool
    let returnKeyType: UIReturnKeyType
    let isTouchDownAction: Bool
    let action: (() -> Void)?
    let leadingHitPadding: CGFloat
    let trailingHitPadding: CGFloat
    let topHitPadding: CGFloat
    let bottomHitPadding: CGFloat

    @State private var isPressed = false
    @State private var autorepeatTimer: Timer?
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Return key helpers

    private var isReturnBlue: Bool {
        switch returnKeyType {
        case .send, .go, .search, .join, .route: return true
        default: return false
        }
    }

    // MARK: - Light mode backgrounds

    private func lightKeyBackground(isPressed: Bool) -> Color {
        if isTrackpadMode { return Color(UIColor.systemGray5) }
        switch key.type {
        case .letter, .space:
            return isPressed ? Color(UIColor.systemGray4) : .white
        case .returnKey:
            if isReturnBlue { return isPressed ? Color(red: 0, green: 0.38, blue: 0.85) : Color(UIColor.systemBlue) }
            return isPressed ? Color(UIColor.systemGray4) : Color(UIColor.systemGray3)
        default:
            return isPressed ? Color(UIColor.systemGray4) : Color(UIColor.systemGray3)
        }
    }

    // MARK: - Dark mode backgrounds

    private func darkKeyBackground(isPressed: Bool) -> Color {
        if isTrackpadMode { return Color.white.opacity(0.06) }
        switch key.type {
        case .returnKey:
            if isReturnBlue { return isPressed ? Color(red: 0, green: 0.38, blue: 0.85) : Color(UIColor.systemBlue) }
            return Color.white.opacity(isPressed ? 0.30 : 0.20)
        default:
            return Color.white.opacity(isPressed ? 0.30 : 0.20)
        }
    }

    private func keyBackground(isPressed: Bool) -> Color {
        colorScheme == .dark ? darkKeyBackground(isPressed: isPressed) : lightKeyBackground(isPressed: isPressed)
    }

    // MARK: - Text color

    private var keyTitleColor: Color {
        if key.isReturnType && isReturnBlue { return .white }
        return colorScheme == .dark ? .white : .black
    }

    // MARK: - Shadow (light mode only)

    private var keyShadowColor: Color {
        if colorScheme == .dark || isTrackpadMode { return .clear }
        return Color.black.opacity(0.25)
    }

    // MARK: - Callout fill

    private var calloutFill: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.42), Color(white: 0.30)],
                startPoint: .top, endPoint: .bottom
            ))
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [.white, Color(white: 0.95)],
                startPoint: .top, endPoint: .bottom
            ))
        }
    }

    // MARK: - Body

    var body: some View {
        let showsCallout = isPressed && key.displaysCallout && !isTrackpadMode

        GeometryReader { geo in
            let keyRect = visibleKeyRect(in: geo.size)
            let keyWidth = keyRect.width
            let keyHeight = keyRect.height
            let bubbleHeight = keyHeight * KeyCalloutShape.bubbleHeightRatio
            let stemHeight = KeyCalloutShape.stemHeight

            ZStack {
                Color.black.opacity(0.001)

                if !showsCallout {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(keyBackground(isPressed: isPressed))
                        .frame(width: keyWidth, height: keyHeight)
                        .position(x: keyRect.midX, y: keyRect.midY)
                        .shadow(color: keyShadowColor, radius: 0, x: 0, y: 1)
                }

                if showsCallout {
                    ZStack {
                        KeyCalloutShape(alignment: key.calloutAlignment)
                            .fill(calloutFill)
                            .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 3)

                        if let title = key.displayTitle(shiftState: shiftState) {
                            let titleY = -(bubbleHeight * 0.85 + stemHeight)
                            Text(title)
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .font(.system(size: key.titleFontSize * 1.35, weight: .light))
                                .offset(
                                    x: key.calloutTitleOffset(keyWidth: keyWidth),
                                    y: titleY
                                )
                        }
                    }
                    .frame(width: keyWidth, height: keyHeight)
                    .position(x: keyRect.midX, y: keyRect.midY)
                }

                if !isTrackpadMode && !(isPressed && key.displaysCallout) {
                    keyContentView
                        .frame(width: keyWidth, height: keyHeight)
                        .position(x: keyRect.midX, y: keyRect.midY)
                }
            }
        }
        .animation(nil, value: UUID())
        .zIndex(isPressed && key.displaysCallout ? 10 : 0)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                    if !isTouchDownAction {
                        action?()
                        HapticManager.shared.keyTap()
                    }
                }
        )
        .onChange(of: isPressed) { _, newValue in
            handlePressChange(newValue)
        }
        .onDisappear {
            autorepeatTimer?.invalidate()
            autorepeatTimer = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func visibleKeyRect(in size: CGSize) -> CGRect {
        let width = max(0, size.width - leadingHitPadding - trailingHitPadding)
        let height = max(0, size.height - topHitPadding - bottomHitPadding)
        return CGRect(
            x: leadingHitPadding,
            y: topHitPadding,
            width: width,
            height: height
        )
    }

    // MARK: - Key Content

    @ViewBuilder
    private var keyContentView: some View {
        switch key.type {
        case .letter:
            Text(key.displayTitle(shiftState: shiftState) ?? key.label)
                .foregroundStyle(keyTitleColor)
                .font(.system(size: key.titleFontSize))

        case .backspace:
            Image(systemName: "delete.backward")
                .font(.system(size: 20))
                .foregroundStyle(keyTitleColor)

        case .shift:
            Image(systemName: shiftIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(keyTitleColor)

        case .returnKey:
            returnKeyView

        case .space:
            Text("space")
                .font(.system(size: key.titleFontSize))
                .foregroundStyle(keyTitleColor.opacity(0.45))

        case .globe:
            Image(systemName: "globe")
                .font(.system(size: NativeKeyboardMetrics.modifierFontSize))
                .foregroundStyle(keyTitleColor)

        case .numbers, .symbols, .letters:
            Text(key.label)
                .foregroundStyle(keyTitleColor)
                .font(.system(size: key.titleFontSize))

        case .period:
            Text(".")
                .foregroundStyle(keyTitleColor)
                .font(.system(size: key.titleFontSize))

        case .comma:
            Text(",")
                .foregroundStyle(keyTitleColor)
                .font(.system(size: key.titleFontSize))
        }
    }

    @ViewBuilder
    private var returnKeyView: some View {
        switch returnKeyType {
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isReturnBlue ? .white : keyTitleColor)
        case .send:
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        case .go:
            Text("Go")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isReturnBlue ? .white : keyTitleColor)
        default:
            Image(systemName: "return")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(keyTitleColor)
        }
    }

    private var shiftIcon: String {
        switch shiftState {
        case .off: return "shift"
        case .on: return "shift.fill"
        case .capsLock: return "capslock.fill"
        }
    }

    // MARK: - Autorepeat

    private func handlePressChange(_ isPressed: Bool) {
        if isPressed && isTouchDownAction {
            action?()
        }

        if key.autorepeats {
            if isPressed {
                autorepeatTimer = Timer.scheduledTimer(
                    withTimeInterval: Self.autorepeatStartDelay, repeats: false
                ) { _ in
                    autorepeatTimer?.invalidate()
                    autorepeatTimer = Timer.scheduledTimer(
                        withTimeInterval: Self.autorepeatInterval, repeats: true
                    ) { _ in
                        action?()
                    }
                }
            } else {
                autorepeatTimer?.invalidate()
                autorepeatTimer = nil
            }
        }
    }
}

// MARK: - Key Button View

struct KeyButton: View {
    let key: KeyModel
    let shiftState: ShiftState
    let isTrackpadMode: Bool
    let returnKeyType: UIReturnKeyType
    let action: () -> Void
    let trackpadModeEnabled: ((Bool) -> Void)?
    let cursorAdjust: ((Int) -> Void)?
    let leadingHitPadding: CGFloat
    let trailingHitPadding: CGFloat
    let topHitPadding: CGFloat
    let bottomHitPadding: CGFloat

    @State private var lastTrackpadX: CGFloat = 0
    @GestureState private var isLongPressing = false

    init(
        key: KeyModel,
        shiftState: ShiftState = .off,
        isTrackpadMode: Bool = false,
        returnKeyType: UIReturnKeyType = .default,
        action: @escaping () -> Void,
        trackpadModeEnabled: ((Bool) -> Void)? = nil,
        cursorAdjust: ((Int) -> Void)? = nil,
        leadingHitPadding: CGFloat = 0,
        trailingHitPadding: CGFloat = 0,
        topHitPadding: CGFloat = 0,
        bottomHitPadding: CGFloat = 0
    ) {
        self.key = key
        self.shiftState = shiftState
        self.isTrackpadMode = isTrackpadMode
        self.returnKeyType = returnKeyType
        self.action = action
        self.trackpadModeEnabled = trackpadModeEnabled
        self.cursorAdjust = cursorAdjust
        self.leadingHitPadding = leadingHitPadding
        self.trailingHitPadding = trailingHitPadding
        self.topHitPadding = topHitPadding
        self.bottomHitPadding = bottomHitPadding
    }

    var body: some View {
        if key.supportsTrackpadMode {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    tapExpansionZone(height: topHitPadding)

                    HStack(spacing: 0) {
                        tapExpansionZone(width: leadingHitPadding)

                        keyContent
                            .frame(
                                width: max(0, geo.size.width - leadingHitPadding - trailingHitPadding),
                                height: max(0, geo.size.height - topHitPadding - bottomHitPadding)
                            )

                        tapExpansionZone(width: trailingHitPadding)
                    }

                    tapExpansionZone(height: bottomHitPadding)
                }
            }
        } else {
            KeyView(
                key: key,
                shiftState: shiftState,
                isTrackpadMode: isTrackpadMode,
                returnKeyType: returnKeyType,
                isTouchDownAction: key.actionOnPress,
                action: action,
                leadingHitPadding: leadingHitPadding,
                trailingHitPadding: trailingHitPadding,
                topHitPadding: topHitPadding,
                bottomHitPadding: bottomHitPadding
            )
        }
    }

    private var spacebarKeyView: some View {
        SpacebarKeyView(
            key: key,
            isTrackpadMode: isTrackpadMode
        )
    }

    @ViewBuilder
    private var keyContent: some View {
        if key.supportsTrackpadMode {
            spacebarKeyView
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .updating($isLongPressing) { current, state, _ in
                            state = current
                        }
                        .onEnded { _ in
                            trackpadModeEnabled?(true)
                            HapticManager.shared.keyTap()
                        }
                        .sequenced(before:
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { gesture in
                                    let currentX = gesture.location.x
                                    if lastTrackpadX == 0 {
                                        lastTrackpadX = currentX
                                        return
                                    }
                                    let delta = currentX - lastTrackpadX
                                    let charThreshold: CGFloat = 7
                                    if abs(delta) >= charThreshold {
                                        let chars = Int(delta / charThreshold)
                                        cursorAdjust?(chars)
                                        lastTrackpadX += CGFloat(chars) * charThreshold
                                    }
                                }
                                .onEnded { _ in
                                    trackpadModeEnabled?(false)
                                    lastTrackpadX = 0
                                }
                        )
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            if !isTrackpadMode {
                                triggerTapAction()
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tapExpansionZone(width: CGFloat) -> some View {
        if width > 0 {
            Color.black
                .opacity(0.001)
                .frame(width: width)
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerTapAction()
                }
        }
    }

    @ViewBuilder
    private func tapExpansionZone(height: CGFloat) -> some View {
        if height > 0 {
            Color.black
                .opacity(0.001)
                .frame(height: height)
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerTapAction()
                }
        }
    }

    private func triggerTapAction() {
        action()
        HapticManager.shared.keyTap()
    }
}

// MARK: - Spacebar Key View

private struct SpacebarKeyView: View {
    let key: KeyModel
    let isTrackpadMode: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        if isTrackpadMode {
            return colorScheme == .dark ? Color.white.opacity(0.06) : Color(UIColor.systemGray5)
        }
        return colorScheme == .dark ? Color.white.opacity(0.20) : .white
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var shadowColor: Color {
        colorScheme == .dark || isTrackpadMode ? .clear : Color.black.opacity(0.25)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyView.cornerRadius)
                .fill(bgColor)
                .shadow(color: shadowColor, radius: 0, x: 0, y: 1)

            if !isTrackpadMode {
                Text("space")
                    .font(.system(size: key.titleFontSize))
                    .foregroundStyle(titleColor.opacity(0.45))
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helper

private extension KeyModel {
    var isReturnType: Bool {
        if case .returnKey = type { return true }
        return false
    }
}

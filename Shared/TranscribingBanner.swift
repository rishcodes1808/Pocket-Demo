import SwiftUI

/// Shown while the main app's audio engine is actively transcribing.
///
/// Layout (top → bottom):
///   1. Live partial transcript preview (right-aligned, truncates at the head
///      so the most-recent words stay visible)
///   2. Cancel (X) · Waveform · Done (✓)
///
/// The partial transcript is also inserted into the active text field live,
/// so the preview here is a secondary confirmation that the recognizer is
/// picking up speech.
struct TranscribingBanner: View {
    var isProcessing: Bool = false
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var partialTranscript: String = ""
    @State private var partialRefreshTimer: Timer?

    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.25)
    }

    private var circleBackground: Color {
        colorScheme == .dark
            ? Color(UIColor.systemGray5).opacity(0.4)
            : Color(UIColor.systemGray5)
    }

    /// Placeholder when the recognizer hasn't returned anything yet for this burst.
    private var previewText: String {
        if !partialTranscript.isEmpty { return partialTranscript }
        if isProcessing { return "Transcribing\u{2026}" }
        return "Listening\u{2026}"
    }

    var body: some View {
        VStack(spacing: 4) {
            // Live partial transcript preview — right-aligned, head-truncated
            Text(previewText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(foreground.opacity(partialTranscript.isEmpty ? 0.35 : 0.75))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .animation(.easeInOut(duration: 0.12), value: partialTranscript)

            HStack(spacing: 10) {
                // Cancel button (X)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(foreground)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(circleBackground))
                }
                .buttonStyle(.plain)

                if isProcessing {
                    // Processing state — show spinner + "Transcribing Text…"
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(foreground)
                        Text("Transcribing Text\u{2026}")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(foreground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                } else {
                    // Waveform visualization (reads AppGroupManager.audioLevel)
                    WaveformView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }

                // Done button (checkmark) — disabled when processing
                Button(action: onDone) {
                    Group {
                        if isProcessing {
                            ProgressView()
                                .tint(foreground.opacity(0.4))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(foreground)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(circleBackground))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.5 : 1.0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 6)
        .onAppear {
            startPartialTranscriptRefresh()
        }
        .onDisappear {
            partialRefreshTimer?.invalidate()
            partialRefreshTimer = nil
        }
    }

    private func startPartialTranscriptRefresh() {
        partialRefreshTimer?.invalidate()
        partialRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                AppGroupManager.shared.sharedDefaults.synchronize()
                let text = AppGroupManager.shared.partialTranscript
                if text != partialTranscript {
                    partialTranscript = text
                }
            }
        }
    }
}

// MARK: - CADisplayLink Waveform
//
// 20 thin pill-shaped bars arranged in a gentle bell curve. Each bar has its
// own traveling-wave phase offset and fades subtly from the tint color at the
// top to a darker shade at the bottom. When the audio is quiet, the bars
// idle with a slow breathing animation; when audio is present, they swell in
// a flowing wave that propagates from one edge to the other.

struct WaveformView: UIViewRepresentable {

    func makeUIView(context: Context) -> WaveformUIView {
        WaveformUIView()
    }

    func updateUIView(_ uiView: WaveformUIView, context: Context) {}

    static func dismantleUIView(_ uiView: WaveformUIView, coordinator: Coordinator) {
        uiView.reset()
    }
}

final class WaveformUIView: UIView {

    // MARK: - Configuration

    /// Fewer but thicker bars for a more substantial, readable waveform.
    static let numBars = 14
    static let barWidth: CGFloat = 5.0
    static let barSpacing: CGFloat = 4.0
    static let barStep: CGFloat = barWidth + barSpacing
    static let barHeightMinimum: CGFloat = 4.0
    static let barHeightMaximum: CGFloat = 40.0
    static let targetFPS: Int = 60

    /// Fast attack so the bars snap to speech immediately.
    static let smoothingUp: CGFloat = 0.55
    /// Slightly quicker decay so they settle naturally between words.
    static let smoothingDown: CGFloat = 0.20

    /// Per-bar wave phase offset (seconds). Larger = more dramatic traveling wave.
    static let barPhaseOffset: TimeInterval = 0.09
    /// Slower breathing, larger idle amplitude — visible motion even in silence.
    static let breathCycleDuration: TimeInterval = 1.8
    /// Faster active wave cycle for a more energetic look.
    static let waveCycleDuration: TimeInterval = 0.7

    /// Flatter bell envelope (higher sigma) so edge bars stay reactive instead
    /// of withering at the sides.
    static let bellSigma: CGFloat = 8.0

    /// Low-level boost curve. `pow(level, 0.3)` is much more aggressive than
    /// `sqrt(level)` — a raw 10% audio level becomes ≈50% visual height,
    /// making quiet speech produce big motion.
    static let levelExponent: CGFloat = 0.30

    /// Multiplier for the blend between idle and active rendering. Higher
    /// values mean the waveform reaches "fully active" sooner. At 4.0 a 25%
    /// audio level is already rendering at full activity.
    static let activeBlendMultiplier: CGFloat = 4.0

    /// Idle breathing amplitude (pt). Larger = more visible even in silence.
    static let idleBreathAmplitude: CGFloat = 6.0

    /// Tint color at the top of each bar. Soft blue-violet.
    static var topTintColor: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.70, blue: 1.00, alpha: 1.0)
                : UIColor(red: 0.22, green: 0.36, blue: 0.95, alpha: 1.0)
        }
    }

    /// Tint color at the bottom of each bar. Slightly deeper.
    static var bottomTintColor: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.48, green: 0.40, blue: 0.95, alpha: 1.0)
                : UIColor(red: 0.45, green: 0.25, blue: 0.90, alpha: 1.0)
        }
    }

    // MARK: - State

    private var barLayers: [CAGradientLayer] = []
    private var displayLink: CADisplayLink?
    private var smoothedLevel: CGFloat = 0.0
    private var startTime: TimeInterval = 0.0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        setupBars()
        startTime = CACurrentMediaTime()
        startDisplayLink()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WaveformUIView, _) in
            view.refreshBarColors()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }

    // MARK: - Setup

    private func setupBars() {
        let top = Self.topTintColor.cgColor
        let bottom = Self.bottomTintColor.cgColor
        for _ in 0..<Self.numBars {
            let layer = CAGradientLayer()
            layer.colors = [top, bottom]
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint(x: 0.5, y: 1)
            layer.cornerRadius = Self.barWidth / 2
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            self.layer.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    private func refreshBarColors() {
        let top = Self.topTintColor.cgColor
        let bottom = Self.bottomTintColor.cgColor
        for layer in barLayers {
            layer.colors = [top, bottom]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionBars()
    }

    private func positionBars() {
        let totalWidth = CGFloat(Self.numBars) * Self.barWidth
            + CGFloat(Self.numBars - 1) * Self.barSpacing
        let xStart = (bounds.width - totalWidth) / 2.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, layer) in barLayers.enumerated() {
            let x = xStart + CGFloat(i) * Self.barStep
            let h = max(Self.barHeightMinimum, layer.bounds.height)
            let y = (bounds.height - h) / 2.0
            layer.frame = CGRect(x: x, y: y, width: Self.barWidth, height: h)
        }
        CATransaction.commit()
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFramesPerSecond = Self.targetFPS
        displayLink?.add(to: .main, forMode: .default)
    }

    @objc private func tick() {
        // Read audio level from shared storage (written by main app's audio tap)
        let rawLevel = CGFloat(AppGroupManager.shared.audioLevel)

        // Asymmetric smoothing — fast attack, slightly slower decay
        let factor = rawLevel > smoothedLevel ? Self.smoothingUp : Self.smoothingDown
        smoothedLevel += factor * (rawLevel - smoothedLevel)

        // Aggressive low-level boost: pow(level, 0.3) makes a 10% raw level
        // render at ≈50% height, so quiet speech produces prominent motion.
        let amplifiedLevel = pow(smoothedLevel, Self.levelExponent)

        let now = CACurrentMediaTime() - startTime
        let center = CGFloat(Self.numBars - 1) / 2.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let totalWidth = CGFloat(Self.numBars) * Self.barWidth
            + CGFloat(Self.numBars - 1) * Self.barSpacing
        let xStart = (bounds.width - totalWidth) / 2.0

        for (i, layer) in barLayers.enumerated() {
            let fi = CGFloat(i)

            // Flatter bell envelope (sigma = 8) — edge bars still respond
            let distFromCenter = fi - center
            let envelope = exp(-(distFromCenter * distFromCenter) / (2 * Self.bellSigma * Self.bellSigma))

            // Per-bar traveling wave oscillation — more pronounced than before
            let phase = now / Self.waveCycleDuration + Double(i) * Self.barPhaseOffset
            let wave = 0.5 + 0.5 * sin(phase * 2.0 * .pi)

            // Idle breathing — larger amplitude so silence still has motion
            let breathPhase = now / Self.breathCycleDuration + Double(i) * 0.05
            let breath = 0.5 + 0.5 * sin(breathPhase * 2.0 * .pi)
            let idleHeight = Self.barHeightMinimum + Self.idleBreathAmplitude * breath * envelope

            // Active height — wave contributes more (0.35 baseline + 0.65 wave)
            // so each bar swings dramatically during speech
            let activeRange = Self.barHeightMaximum - Self.barHeightMinimum
            let activeHeight = Self.barHeightMinimum
                + activeRange * amplifiedLevel * envelope * (0.35 + 0.65 * wave)

            // Fast blend — at 25% amplified level we're fully in active mode
            let blendFactor = min(amplifiedLevel * Self.activeBlendMultiplier, 1.0)
            let finalHeight = max(Self.barHeightMinimum,
                                  idleHeight * (1.0 - blendFactor) + activeHeight * blendFactor)

            // Update frame centered vertically
            let x = xStart + fi * Self.barStep
            let y = (bounds.height - finalHeight) / 2.0
            layer.frame = CGRect(x: x, y: y, width: Self.barWidth, height: finalHeight)
        }

        CATransaction.commit()
    }

    // MARK: - Reset

    func reset() {
        displayLink?.invalidate()
        displayLink = nil
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        smoothedLevel = 0.0
    }
}

import AppKit
import SwiftUI

struct ElasticSlider: View {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var valueText: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    var dragStep: Double?
    var trackHeight: CGFloat = 26
    var hitHeight: CGFloat = 26
    var fillColor: Color = Color.white.opacity(0.20)
    var dragFillColor: Color?
    var thumbSize: CGFloat = 18
    var thumbWidth: CGFloat? = 38
    var thumbHeight: CGFloat? = 18
    var thumbColor: Color = Color.white
    var showStepDots: Bool = true
    var showTooltip: Bool = true
    var setsValueFromPointerLocation = true

    @State private var visualProgress: Double?
    @State private var dragStartValue: Double = 0
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var isPointingCursorActive = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let currentNormalized = normalized(value).clamped(to: 0...1)
            let progress = (visualProgress ?? currentNormalized).clamped(to: 0...1)

            let resolvedThumbWidth = thumbWidth ?? thumbSize
            let resolvedThumbHeight = min(thumbHeight ?? (trackHeight - 8), trackHeight - 4)
            let thumbRadius = resolvedThumbWidth / 2

            let travelDistance = max(width - resolvedThumbWidth, 1)
            let valueX = thumbRadius + travelDistance * CGFloat(progress)

            ZStack {
                // Background Track Bar with fully rounded capsule container
                ZStack(alignment: .leading) {
                    // Outer track container: seamless dark dark grey (close to black)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.38))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(isHovering || isDragging ? 0.16 : 0.08), lineWidth: 1)
                        }

                    // Step dots / Graduation markers (only on un-scrolled section to the right)
                    if showStepDots && width > 80 {
                        stepDots(width: width, thumbX: valueX, thumbWidth: resolvedThumbWidth)
                    }
                }
                .frame(width: width, height: trackHeight)
                .clipShape(Capsule(style: .continuous))

                // Sliding Fully Rounded Pill Tab Handle
                Capsule(style: .continuous)
                    .fill(thumbColor)
                    .frame(width: resolvedThumbWidth, height: resolvedThumbHeight)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(0.38), radius: isDragging ? 4 : 2, y: 1)
                    .scaleEffect(isDragging ? 1.05 : (isHovering ? 1.02 : 1.0))
                    .position(x: valueX, y: trackHeight / 2)
                    .animation(Theme.springFast, value: isDragging)
                    .animation(Theme.springFast, value: isHovering)
                    .allowsHitTesting(false)

                // Floating translucent value tooltip badge while scrubbing
                if showTooltip, isDragging, let valueText, !valueText.isEmpty {
                    floatingValueTooltip(valueText: valueText, thumbX: valueX)
                }
            }
            .frame(width: width, height: trackHeight)
            .contentShape(Capsule(style: .continuous))
            .gesture(dragGesture(width: width, thumbWidth: resolvedThumbWidth))
        }
        .frame(height: trackHeight)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovering = hovering
            updateCursor()
        }
        .onChange(of: isEnabled) {
            updateCursor()
        }
        .onDisappear {
            popPointingCursorIfNeeded()
        }
        .focusable(isEnabled)
        .focusEffectDisabled()
        .onMoveCommand(perform: handleMoveCommand)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step)
        }
        .onChange(of: value) { _, nextValue in
            guard !isDragging else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                visualProgress = normalized(nextValue)
            }
        }
    }

    // Step dots spaced along track - only shown for un-scrolled area (to the right of the thumb)
    private func stepDots(width: CGFloat, thumbX: CGFloat, thumbWidth: CGFloat) -> some View {
        let dotCount = min(max(Int(width / 32), 3), 6)
        let thumbRightThreshold = thumbX + (thumbWidth * 0.40)
        let padding: CGFloat = 18
        let availableWidth = max(width - (padding * 2), 1)

        return ZStack(alignment: .leading) {
            ForEach(0..<dotCount, id: \.self) { index in
                let fraction = CGFloat(index) / CGFloat(max(dotCount - 1, 1))
                let dotX = padding + fraction * availableWidth

                if dotX > thumbRightThreshold {
                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 4, height: 4)
                        .position(x: dotX, y: trackHeight / 2)
                }
            }
        }
        .frame(width: width, height: trackHeight)
        .allowsHitTesting(false)
    }

    // Floating dynamic translucent badge while dragging
    private func floatingValueTooltip(valueText: String, thumbX: CGFloat) -> some View {
        Text(valueText)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.85))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
            .position(x: thumbX, y: -16)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .allowsHitTesting(false)
    }

    private func dragGesture(width: CGFloat, thumbWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                guard isEnabled else { return }

                if !isDragging {
                    isDragging = true
                    dragStartValue = value
                    performHaptic()
                    onEditingChanged(true)
                }

                let travelDistance = max(width - thumbWidth, 1)
                let thumbRadius = thumbWidth / 2
                let relativeX = gesture.location.x - thumbRadius
                let progress = Double((relativeX / travelDistance).clamped(to: 0...1))
                let nextValue = steppedValue(for: progress, step: dragStep ?? step)

                visualProgress = progress
                value = nextValue
            }
            .onEnded { _ in
                guard isEnabled else { return }
                isDragging = false
                onEditingChanged(false)

                let settledProgress = normalized(value).clamped(to: 0...1)
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 26)) {
                    visualProgress = settledProgress
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard !isDragging else { return }
                    visualProgress = nil
                }
            }
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard isEnabled else { return }
        switch direction {
        case .left, .down:
            stepValue(by: -step)
        case .right, .up:
            stepValue(by: step)
        @unknown default:
            break
        }
    }

    private func stepValue(by delta: Double) {
        let proposedValue = (value + delta).clamped(to: range)
        let nextValue = steppedValue(for: normalized(proposedValue).clamped(to: 0...1), step: step)
        value = nextValue
        performHaptic()
        withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) {
            visualProgress = normalized(nextValue)
        }
    }

    private func updateCursor() {
        if isEnabled && isHovering {
            pushPointingCursorIfNeeded()
        } else {
            popPointingCursorIfNeeded()
        }
    }

    private func pushPointingCursorIfNeeded() {
        guard !isPointingCursorActive else { return }
        NSCursor.pointingHand.push()
        isPointingCursorActive = true
    }

    private func popPointingCursorIfNeeded() {
        guard isPointingCursorActive else { return }
        NSCursor.pop()
        isPointingCursorActive = false
    }

    private func normalized(_ input: Double) -> Double {
        guard range.upperBound != range.lowerBound else { return 0 }
        return (input - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func steppedValue(for progress: Double, step: Double) -> Double {
        let rawValue = range.lowerBound + progress * (range.upperBound - range.lowerBound)
        let safeStep = max(step, Double.ulpOfOne)
        let stepped = (round((rawValue - range.lowerBound) / safeStep) * safeStep) + range.lowerBound
        return stepped.clamped(to: range)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

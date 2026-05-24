import AppKit
import SwiftUI

struct ElasticSlider: View {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    var dragStep: Double?
    var trackHeight: CGFloat = 16
    var hitHeight: CGFloat = 32
    var fillColor: Color = Color(red: 0.961, green: 0.961, blue: 0.961)
    var dragFillColor: Color?
    var thumbSize: CGFloat = 0
    var thumbWidth: CGFloat?
    var thumbHeight: CGFloat?
    var thumbColor: Color = Color.white.opacity(0.98)
    var setsValueFromPointerLocation = false

    @State private var visualProgress: Double?
    @State private var settlingCommittedProgress: Double?
    @State private var dragStartValue: Double = 0
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var isPointingCursorActive = false

    private let maxPull: CGFloat = 18
    private let maxSquish = 0.92
    private let maxStretch = 1.08

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let committedProgress = (
                settlingCommittedProgress ?? normalized(isDragging ? dragStartValue : value)
            ).clamped(to: 0...1)
            let progress = visualProgress ?? normalized(value)
            let clampedProgress = progress.clamped(to: 0...1)
            let overpull = progress < 0 ? progress : max(0, progress - 1)
            let pullAmount = min(abs(overpull), 1)
            let offsetX = CGFloat(overpull.clamped(to: -1...1)) * maxPull
            let scaleX = 1 + (maxStretch - 1) * pullAmount
            let scaleY = 1 - (1 - maxSquish) * pullAmount
            let resolvedThumbWidth = thumbWidth ?? thumbSize
            let resolvedThumbHeight = thumbHeight ?? thumbSize
            let hasThumb = resolvedThumbWidth > 0 && resolvedThumbHeight > 0
            let committedFillWidth = width * CGFloat(committedProgress)
            let dragFillWidth = isDragging
                ? width * CGFloat(clampedProgress)
                : nil
            let drawsDragFillAboveCommitted = isDragging && clampedProgress < committedProgress
            let resolvedFillColor = drawsDragFillAboveCommitted ? effectiveDragFillColor : fillColor
            let resolvedDragFillColor = drawsDragFillAboveCommitted ? fillColor : effectiveDragFillColor
            let valueX = width * CGFloat(clampedProgress)

            ZStack {
                sliderTrack(
                    width: width,
                    fillWidth: committedFillWidth,
                    fillColor: resolvedFillColor,
                    dragFillWidth: dragFillWidth,
                    dragFillColor: resolvedDragFillColor,
                    drawsDragFillAboveCommitted: drawsDragFillAboveCommitted
                )
                    .scaleEffect(x: scaleX, y: scaleY)
                    .offset(x: hasThumb ? 0 : offsetX)
                    .animation(.easeOut(duration: 0.15), value: isEnabled)

                if hasThumb {
                    RoundedRectangle(cornerRadius: min(resolvedThumbWidth, resolvedThumbHeight) / 2, style: .continuous)
                        .fill(thumbColor)
                        .frame(width: resolvedThumbWidth, height: resolvedThumbHeight)
                        .overlay {
                            RoundedRectangle(cornerRadius: min(resolvedThumbWidth, resolvedThumbHeight) / 2, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.14), radius: 6, y: 2)
                        .scaleEffect(isDragging ? 0.86 : 1)
                        .position(x: valueX, y: hitHeight / 2)
                        .animation(.interpolatingSpring(stiffness: 360, damping: 28), value: isDragging)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: hitHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: hitHeight)
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
            withAnimation(.easeOut(duration: 0.15)) {
                visualProgress = normalized(nextValue)
            }
        }
    }

    private var effectiveDragFillColor: Color {
        dragFillColor ?? fillColor
    }

    private func sliderTrack(
        width: CGFloat,
        fillWidth: CGFloat,
        fillColor: Color,
        dragFillWidth: CGFloat? = nil,
        dragFillColor: Color,
        drawsDragFillAboveCommitted: Bool = false
    ) -> some View {
        Capsule()
            .fill(Theme.border)
            .overlay {
                LinearGradient(
                    colors: [
                        Theme.border,
                        Color.clear,
                        Theme.scrim
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                if let dragFillWidth, !drawsDragFillAboveCommitted {
                    Rectangle()
                        .fill(dragFillColor)
                        .frame(width: dragFillWidth)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) {
                if fillWidth > 0 {
                    Rectangle()
                        .fill(fillColor)
                        .frame(width: fillWidth)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) {
                if let dragFillWidth, drawsDragFillAboveCommitted {
                    Rectangle()
                        .fill(dragFillColor)
                        .frame(width: dragFillWidth)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Theme.border, lineWidth: 1)
            }
            .frame(width: width, height: trackHeight)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                guard isEnabled else { return }

                if !isDragging {
                    isDragging = true
                    settlingCommittedProgress = nil
                    dragStartValue = value
                    performDragStartHaptic()
                    onEditingChanged(true)
                }

                let nextProgress = if setsValueFromPointerLocation {
                    progress(for: gesture.location.x, width: width)
                } else {
                    normalized(dragStartValue) + Double(gesture.translation.width / width)
                }
                visualProgress = nextProgress
                value = steppedValue(for: nextProgress.clamped(to: 0...1), step: dragStep ?? step)
            }
            .onEnded { _ in
                guard isEnabled else { return }
                let settledProgress = (visualProgress ?? normalized(value)).clamped(to: 0...1)
                let dragStartProgress = normalized(dragStartValue).clamped(to: 0...1)

                settlingCommittedProgress = dragStartProgress
                isDragging = false
                onEditingChanged(false)

                withAnimation(.interpolatingSpring(stiffness: 230, damping: 22)) {
                    settlingCommittedProgress = settledProgress
                    visualProgress = settledProgress
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard !isDragging else { return }
                    visualProgress = nil
                    settlingCommittedProgress = nil
                }
            }
    }

    private func performDragStartHaptic() {
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

        withAnimation(.interpolatingSpring(stiffness: 200, damping: 60)) {
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

    private func progress(for x: CGFloat, width: CGFloat) -> Double {
        Double((x / max(width, 1)).clamped(to: 0...1))
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

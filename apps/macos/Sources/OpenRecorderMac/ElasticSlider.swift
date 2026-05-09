import SwiftUI

struct ElasticSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    @State private var visualProgress: Double?
    @State private var dragStartValue: Double = 0
    @State private var isDragging = false

    private let trackHeight: CGFloat = 16
    private let hitHeight: CGFloat = 32
    private let maxPull: CGFloat = 18
    private let maxSquish = 0.92
    private let maxStretch = 1.08

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = visualProgress ?? normalized(value)
            let clampedProgress = progress.clamped(to: 0...1)
            let overpull = progress < 0 ? progress : max(0, progress - 1)
            let pullAmount = min(abs(overpull), 1)
            let offsetX = CGFloat(overpull.clamped(to: -1...1)) * maxPull
            let scaleX = 1 + (maxStretch - 1) * pullAmount
            let scaleY = 1 - (1 - maxSquish) * pullAmount

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear,
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color(red: 0.961, green: 0.961, blue: 0.961))
                            .frame(width: width * clampedProgress)
                            .allowsHitTesting(false)
                    }
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .overlay {
                        if isFocused {
                            Capsule()
                                .stroke(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.48), lineWidth: 3)
                                .blur(radius: 0.5)
                        }
                    }
                    .frame(height: trackHeight)
                    .scaleEffect(x: scaleX, y: scaleY)
                    .offset(x: offsetX)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
                    .animation(.easeOut(duration: 0.15), value: isEnabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: hitHeight)
        .opacity(isEnabled ? 1 : 0.5)
        .focusable(isEnabled)
        .focused($isFocused)
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

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                guard isEnabled else { return }

                if !isDragging {
                    isDragging = true
                    dragStartValue = value
                }

                let nextProgress = normalized(dragStartValue) + Double(gesture.translation.width / width)
                visualProgress = nextProgress
                value = steppedValue(for: nextProgress.clamped(to: 0...1))
            }
            .onEnded { _ in
                guard isEnabled else { return }
                isDragging = false

                let settledProgress = (visualProgress ?? normalized(value)).clamped(to: 0...1)
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 34)) {
                    visualProgress = settledProgress
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard !isDragging else { return }
                    visualProgress = nil
                }
            }
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
        let nextValue = steppedValue(for: normalized(proposedValue).clamped(to: 0...1))
        value = nextValue

        withAnimation(.interpolatingSpring(stiffness: 200, damping: 60)) {
            visualProgress = normalized(nextValue)
        }
    }

    private func normalized(_ input: Double) -> Double {
        guard range.upperBound != range.lowerBound else { return 0 }
        return (input - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func steppedValue(for progress: Double) -> Double {
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

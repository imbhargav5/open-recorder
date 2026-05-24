import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SettingsInspector: View {
    @Binding var borderRadius: Double
    @Binding var padding: Double
    @Binding var shadow: Double
    @Binding var backgroundBlur: Double
    @Binding var background: BackgroundStyle
    @Binding var inset: Double
    @Binding var insetColor: SerializableColor
    @Binding var insetOpacity: Double
    @Binding var insetBalance: VideoInsetBalance
    @Binding var showCursor: Bool
    @Binding var loopCursor: Bool
    @Binding var cursorSize: Double
    @Binding var cursorSmoothing: Double
    @Binding var cursorStyleID: CursorStyleID
    var recordingSession: RecordingSession?

    @State private var activeTab: InspectorTab = .appearance
    @State private var hoveredTab: InspectorTab?
    @State private var isInsetBalanceExpanded = false

    private let railWidth: CGFloat = 48
    private let railButtonSize: CGFloat = 36
    private let railButtonSpacing: CGFloat = 10
    private let railVerticalPadding: CGFloat = 12
    private let insetBalanceScrollID = "inset-balance-accordion"

    private var hasRecordedCamera: Bool {
        recordingSession?.hasRecordedCamera == true
    }

    private var showsInsetControls: Bool {
        inset > 0
    }

    var body: some View {
        HStack(spacing: 0) {
            inspectorRail
            inspectorContent
        }
        .overlay(alignment: .topLeading) {
            if let hoveredTab {
                InspectorRailTooltip(title: hoveredTab.title)
                    .frame(width: 0, alignment: .trailing)
                    .offset(x: -10, y: railItemOffset(for: hoveredTab) + 4)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .studioEditorPaneChrome(clipContent: false)
        .animation(.snappy(duration: 0.14), value: hoveredTab?.id)
        .onChange(of: showsInsetControls) { _, isVisible in
            if !isVisible {
                isInsetBalanceExpanded = false
            }
        }
    }

    private func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var inspectorRail: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: railButtonSpacing) {
                ForEach(InspectorTab.allCases) { tab in
                    InspectorRailButton(
                        tab: tab,
                        isActive: activeTab == tab,
                        size: railButtonSize
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            activeTab = tab
                        }
                    } onHoverChanged: { isHovering in
                        hoveredTab = isHovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                    }
                }
            }
            .padding(.vertical, railVerticalPadding)
            .frame(width: railWidth)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.appBgMuted.opacity(0.54))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderStrong.opacity(0.44))
                .frame(width: 1)
        }
    }

    private func railItemOffset(for tab: InspectorTab) -> CGFloat {
        let index = InspectorTab.allCases.firstIndex(of: tab) ?? 0
        return railVerticalPadding + CGFloat(index) * (railButtonSize + railButtonSpacing)
    }

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        inspectorHeader
                        tabContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                    .animation(.snappy(duration: 0.34), value: activeTab.id)
                    .animation(.snappy(duration: 0.34), value: background.presetKind)
                    .animation(.snappy(duration: 0.34), value: hasRecordedCamera)
                    .animation(.snappy(duration: 0.34), value: cursorStyleID)
                    .animation(.smooth(duration: 0.30), value: showsInsetControls)
                    .onChange(of: isInsetBalanceExpanded) { _, isExpanded in
                        guard isExpanded else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.snappy(duration: 0.34)) {
                                scrollProxy.scrollTo(insetBalanceScrollID, anchor: .bottom)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            Rectangle()
                .fill(Theme.borderStrong.opacity(0.44))
                .frame(height: 1)

            inspectorFooter
        }
    }

    private var inspectorHeader: some View {
        Text(activeTab.title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.fg.opacity(0.96))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 18)
    }

    private var inspectorFooter: some View {
        HStack(spacing: 8) {
            InspectorFooterButton(title: "Report Bug", symbolName: "ladybug") {
                openExternal("https://github.com/imbhargav5/open-recorder/issues/new/choose")
            }
            InspectorFooterButton(title: "Star on GitHub", symbolName: "star") {
                openExternal("https://github.com/imbhargav5/open-recorder")
            }
        }
        .padding(12)
        .background(Theme.appBgMuted.opacity(0.38))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .appearance:
            BackgroundPickerView(selection: $background, showsTopDivider: false)
            InspectorGroup(title: "Frame", symbolName: "rectangle.on.rectangle") {
                InspectorSlider(title: "Padding", valueText: "\(Int(padding))%", value: $padding, range: 0...100, step: 1, defaultValue: 18, leadingSymbolName: "arrow.down.right.and.arrow.up.left", trailingSymbolName: "arrow.up.left.and.arrow.down.right")
                InspectorSlider(title: "Background Blur", valueText: String(format: "%.1fpx", backgroundBlur), value: $backgroundBlur, range: 0...8, step: 0.25, defaultValue: 0, leadingSymbolName: "camera.filters", trailingSymbolName: "drop.fill")
                InspectorSlider(title: "Shadow", valueText: "\(Int(shadow * 100))%", value: $shadow, range: 0...1, step: 0.01, defaultValue: 0.35, leadingSymbolName: "circle", trailingSymbolName: "circle.fill")
            }
            InspectorGroup(title: "Shape", symbolName: "rectangle.inset.filled") {
                InspectorSlider(title: "Roundness", valueText: "\(Int(borderRadius))px", value: $borderRadius, range: 0...25, step: 0.5, defaultValue: 12, leadingSymbolName: "rectangle", trailingSymbolName: "app")
            }
            InspectorGroup(title: "Inset Styling", symbolName: "square.inset.filled") {
                InspectorSlider(title: "Inset", valueText: "\(Int(inset.rounded()))", value: $inset, range: 0...100, step: 1, defaultValue: 0, leadingSymbolName: "rectangle", trailingSymbolName: "rectangle.inset.filled")
                if showsInsetControls {
                    insetAdvancedControls
                }
            }
        case .cursor:
            InspectorGroup(title: "Cursor", symbolName: "cursorarrow", showsTopDivider: false) {
                InspectorSwitch(title: "Show Cursor", isOn: $showCursor)
                CursorStylePicker(selection: $cursorStyleID)
            }
            InspectorGroup(title: "Motion", symbolName: "point.3.connected.trianglepath.dotted") {
                InspectorSwitch(title: "Loop Cursor", isOn: $loopCursor)
                InspectorSlider(title: "Size", valueText: String(format: "%.2fx", cursorSize), value: $cursorSize, range: 1...8, step: 0.05, defaultValue: 1, leadingSymbolName: "cursorarrow", trailingSymbolName: "cursorarrow.rays")
                InspectorSlider(title: "Smoothing", valueText: String(format: "%.2f", cursorSmoothing), value: $cursorSmoothing, range: 0...2, step: 0.01, defaultValue: 0.45, leadingSymbolName: "point.topleft.down.curvedto.point.bottomright.up", trailingSymbolName: "waveform.path.ecg")
            }
        case .camera:
            InspectorGroup(title: "Facecam", symbolName: "camera", showsTopDivider: false) {
                Text(hasRecordedCamera ? "Timeline camera layer" : "No facecam recorded")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let path = recordingSession?.facecamVideoPath {
                SessionAssetRow(title: "Facecam File", path: path)
            }
        case .audio:
            InspectorGroup(title: "Preview", symbolName: "speaker.wave.2", showsTopDivider: false) {
                InspectorSwitch(title: "Mute Preview", isOn: .constant(false), isInteractive: false)
                InspectorSlider(title: "Volume", valueText: "100%", value: .constant(1), range: 0...1, step: 0.01, defaultValue: 1, leadingSymbolName: "speaker.slash", trailingSymbolName: "speaker.wave.2")
            }
            if let sourceName = recordingSession?.sourceName {
                SessionAssetRow(title: "Source", path: sourceName)
            }
        }
    }

    private var insetAdvancedControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            InsetColorPicker(color: $insetColor)
            InspectorSlider(title: "Inset Opacity", valueText: String(format: "%.2f", insetOpacity), value: $insetOpacity, range: 0...1, step: 0.01, defaultValue: 1, leadingSymbolName: "circle", trailingSymbolName: "circle.fill")
            InsetBalanceAccordion(isExpanded: $isInsetBalanceExpanded) {
                InsetBalancePicker(balance: $insetBalance)
            }
            .id(insetBalanceScrollID)
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
            )
        )
    }
}

struct SessionAssetRow: View {
    var title: String
    var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InspectorRailButton: View {
    var tab: InspectorTab
    var isActive: Bool
    var size: CGFloat
    var action: () -> Void
    var onHoverChanged: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: size, height: size)
                    .foregroundStyle(isActive ? Theme.accent : Theme.fg.opacity(0.86))
                    .background(isHovering ? Color.white.opacity(0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 14, height: 2.5)
                    .opacity(isActive ? 1 : 0)
                    .offset(y: 1)
            }
            .frame(width: size, height: size)
            .roundedHitTarget(12)
            .animation(.snappy(duration: 0.14), value: isHovering)
            .animation(.snappy(duration: 0.18), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged(hovering)
        }
    }
}

struct InspectorRailTooltip: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.fg.opacity(0.94))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.borderStrong.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 10, y: 5)
            .allowsHitTesting(false)
    }
}

struct InspectorFooterButton: View {
    var title: String
    var symbolName: String
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(7), action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(Theme.fgMuted)
                .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }
        }
    }
}

enum InspectorTab: CaseIterable, Identifiable {
    case appearance
    case cursor
    case camera
    case audio

    var id: String { title }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .cursor: "Cursor"
        case .camera: "Camera"
        case .audio: "Audio"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "Appearance"
        case .cursor: "Cursor"
        case .camera: "Camera"
        case .audio: "Audio"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: "slider.horizontal.3"
        case .cursor: "cursorarrow"
        case .camera: "camera"
        case .audio: "speaker.wave.2"
        }
    }
}

struct InspectorGroup<Content: View>: View {
    var title: String
    var symbolName: String
    var showsTopDivider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTopDivider {
                Rectangle()
                    .fill(Theme.borderStrong.opacity(0.55))
                    .frame(height: 1)
            }

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.fg.opacity(0.94))
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.bottom, 17)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.bottom, 18)
        }
    }
}

struct InspectorSlider: View {
    var title: String
    var valueText: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var defaultValue: Double?
    var leadingSymbolName: String = "minus"
    var trailingSymbolName: String = "plus"
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var draftValueText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                    .lineLimit(1)
                Spacer(minLength: 12)

                resetControl
                    .frame(width: 44, alignment: .trailing)

                valueInput
            }
            .frame(height: 24)

            HStack(spacing: 8) {
                sliderIcon(leadingSymbolName)

                ElasticSlider(
                    value: $value,
                    range: range,
                    step: step,
                    onEditingChanged: onEditingChanged,
                    dragStep: intermediateStep,
                    trackHeight: 7,
                    hitHeight: 30,
                    fillColor: Color.primary.opacity(0.92),
                    dragFillColor: Color(red: 0.48, green: 0.48, blue: 0.50),
                    setsValueFromPointerLocation: true
                )
                .accessibilityLabel(title)

                sliderIcon(trailingSymbolName)
            }
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftValueText = displayValueText
        }
        .onChange(of: valueText) { _, newValue in
            if !isInputFocused {
                draftValueText = displayValueText(for: newValue)
            }
        }
        .onChange(of: isInputFocused) { _, focused in
            if focused {
                draftValueText = displayValueText
            } else {
                commitDraftValue()
            }
        }
    }

    @ViewBuilder
    private var resetControl: some View {
        if let defaultValue, abs(value - defaultValue) > max(step / 2, 0.0001) {
                    StudioButton(hitTarget: .rounded(5)) {
                        withAnimation(.snappy(duration: 0.18)) {
                            value = clamped(defaultValue)
                        }
                    } label: {
                        Text("Reset")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.fgSubtle)
                    }
        } else {
            Color.clear
        }
    }

    private var valueInput: some View {
        TextField("", text: $draftValueText)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.fg)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .focused($isInputFocused)
            .frame(width: inputWidth)
            .frame(height: 22)
            .padding(.horizontal, 5)
            .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isInputFocused ? Theme.accent.opacity(0.65) : Theme.borderSubtle, lineWidth: 1)
            }
            .onSubmit(commitDraftValue)
    }

    private var intermediateStep: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return step }
        return min(step, span / 200)
    }

    private var inputWidth: CGFloat {
        38
    }

    private var displayValueText: String {
        displayValueText(for: valueText)
    }

    private func displayValueText(for text: String) -> String {
        if text.hasSuffix("%") {
            let digits = text.filter(\.isNumber)
            return "\(String(digits.prefix(3)))%"
        }

        return text
    }

    private func sliderIcon(_ symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.fgSubtle)
            .frame(width: 18, height: 26)
    }

    private func commitDraftValue() {
        guard let nextValue = parsedDraftValue() else {
            draftValueText = displayValueText
            return
        }

        value = steppedValue(clamped(nextValue))
        draftValueText = displayValueText
    }

    private func parsedDraftValue() -> Double? {
        let trimmed = draftValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericCharacters = trimmed.filter { character in
            character.isNumber || character == "." || character == "-"
        }

        guard let rawValue = Double(numericCharacters) else { return nil }

        if valueText.contains("%"), range.upperBound <= 1 {
            return rawValue / 100
        }

        return rawValue
    }

    private func steppedValue(_ rawValue: Double) -> Double {
        let safeStep = max(step, Double.ulpOfOne)
        let stepped = (round((rawValue - range.lowerBound) / safeStep) * safeStep) + range.lowerBound
        return clamped(stepped)
    }

    private func clamped(_ rawValue: Double) -> Double {
        min(max(rawValue, range.lowerBound), range.upperBound)
    }
}

struct InsetColorPicker: View {
    @Binding var color: SerializableColor

    private let swatchSize: CGFloat = 28
    private let swatchCornerRadius: CGFloat = 7

    private var colorBinding: Binding<Color> {
        Binding(
            get: { color.color },
            set: { color = SerializableColor(NSColor($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Inset color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fgMuted)

            HStack(spacing: 7) {
                selectedColorWell

                Text(color.hexString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.fg.opacity(0.92))
                    .lineLimit(1)
                    .frame(width: 104, height: swatchSize, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Theme.appBgMuted.opacity(0.70), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(BackgroundPresets.solidColors, id: \.self) { swatch in
                            colorSwatch(swatch)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
                .frame(height: swatchSize + 4)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.06),
                            .init(color: .white, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private var selectedColorWell: some View {
        ZStack {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: swatchSize, height: swatchSize)
                .opacity(0.02)

            RoundedRectangle(cornerRadius: swatchCornerRadius, style: .continuous)
                .fill(color.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay {
                    RoundedRectangle(cornerRadius: swatchCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.86), lineWidth: 2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: swatchCornerRadius + 3, style: .continuous)
                        .stroke(Theme.borderStrong.opacity(0.74), lineWidth: 1)
                        .padding(-2)
                }
                .allowsHitTesting(false)
        }
        .frame(width: swatchSize, height: swatchSize)
        .help("Choose custom inset color")
    }

    private func colorSwatch(_ swatch: SerializableColor) -> some View {
        StudioButton(hitTarget: .rounded(8)) {
            color = swatch
        } label: {
            RoundedRectangle(cornerRadius: swatchCornerRadius, style: .continuous)
                .fill(swatch.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay {
                    RoundedRectangle(cornerRadius: swatchCornerRadius, style: .continuous)
                        .stroke(color == swatch ? Theme.accent : Theme.borderStrong.opacity(0.72), lineWidth: color == swatch ? 2 : 1)
                }
        }
        .help(swatch.hexString)
    }
}

struct InsetBalanceAccordion<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioButton(hitTarget: .rounded(8)) {
                withAnimation(.snappy(duration: 0.28)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Text("Inset balance")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.fgMuted)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.fg.opacity(0.92))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.28), value: isExpanded)
    }
}

struct InsetBalancePicker: View {
    @Binding var balance: VideoInsetBalance

    private let knobSize: CGFloat = 24
    private let fieldHeight: CGFloat = 142
    private let fieldCornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Placement")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                Spacer()
                Text(offsetText(for: balance.clamped))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.fg.opacity(0.92))
            }

            GeometryReader { proxy in
                let resolvedBalance = balance.clamped
                let x = knobCenter(for: resolvedBalance.left, length: proxy.size.width)
                let y = knobCenter(for: resolvedBalance.top, length: proxy.size.height)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous)
                        .fill(Theme.surface.opacity(0.42))

                    offsetSpotlight(size: proxy.size, origin: CGPoint(x: x, y: y))

                    offsetGrid(size: proxy.size, opacity: 0.018)
                    offsetGrid(size: proxy.size, opacity: 0.062)
                        .mask {
                            offsetFocusMask(size: proxy.size, origin: CGPoint(x: x, y: y))
                        }

                    offsetAxes(size: proxy.size, origin: CGPoint(x: x, y: y), opacity: 0.06)
                    offsetAxes(size: proxy.size, origin: CGPoint(x: x, y: y), opacity: 0.20)
                        .mask {
                            offsetFocusMask(size: proxy.size, origin: CGPoint(x: x, y: y))
                        }

                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: knobSize, height: knobSize)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.78), lineWidth: 1)
                        }
                        .shadow(color: Color.white.opacity(0.34), radius: 28)
                        .shadow(color: Color.white.opacity(0.24), radius: 12)
                        .shadow(color: Color.black.opacity(0.48), radius: 12, y: 5)
                        .position(x: x, y: y)
                }
                .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.4)
                }
                .contentShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateBalance(at: value.location, in: proxy.size)
                        }
                )
            }
            .frame(height: fieldHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func offsetText(for balance: VideoInsetBalance) -> String {
        let horizontal = balance.left - 0.5
        let vertical = 0.5 - balance.top
        return "\(formattedOffset(horizontal)), \(formattedOffset(vertical))"
    }

    private func formattedOffset(_ value: Double) -> String {
        String(format: "%+.0f%%", value * 100)
    }

    private func offsetGrid(size: CGSize, opacity: Double) -> some View {
        Path { path in
            for index in 1..<4 {
                let y = size.height * CGFloat(index) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            for index in 1..<8 {
                let x = size.width * CGFloat(index) / 8
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.white.opacity(opacity), lineWidth: 1)
    }

    private func offsetAxes(size: CGSize, origin: CGPoint, opacity: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: origin.x, y: 0))
            path.addLine(to: CGPoint(x: origin.x, y: size.height))
            path.move(to: CGPoint(x: 0, y: origin.y))
            path.addLine(to: CGPoint(x: size.width, y: origin.y))
        }
        .stroke(Color.white.opacity(opacity), lineWidth: 1.15)
    }

    private func offsetSpotlight(size: CGSize, origin: CGPoint) -> some View {
        RadialGradient(
            colors: [
                Color.white.opacity(0.105),
                Color.white.opacity(0.045),
                Color.clear
            ],
            center: UnitPoint(x: origin.x / max(size.width, 1), y: origin.y / max(size.height, 1)),
            startRadius: 0,
            endRadius: 112
        )
        .allowsHitTesting(false)
    }

    private func offsetFocusMask(size: CGSize, origin: CGPoint) -> some View {
        RadialGradient(
            colors: [
                Color.white,
                Color.white.opacity(0.72),
                Color.clear
            ],
            center: UnitPoint(x: origin.x / max(size.width, 1), y: origin.y / max(size.height, 1)),
            startRadius: 28,
            endRadius: 140
        )
    }

    private func knobCenter(for progress: Double, length: CGFloat) -> CGFloat {
        let availableLength = max(length - knobSize, 0)
        return knobSize / 2 + CGFloat(progress) * availableLength
    }

    private func updateBalance(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let availableWidth = max(size.width - knobSize, 1)
        let availableHeight = max(size.height - knobSize, 1)
        let left = (location.x - knobSize / 2) / availableWidth
        let top = (location.y - knobSize / 2) / availableHeight

        balance = VideoInsetBalance(
            left: max(0, min(Double(left), 1)),
            top: max(0, min(Double(top), 1))
        )
    }
}

struct CursorStylePicker: View {
    @Binding var selection: CursorStyleID

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(CursorStyleCategory.allCases) { category in
                let styles = CursorStyleRegistry.definitions(in: category)
                if !styles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(styles) { style in
                                CursorStyleButton(
                                    style: style,
                                    isSelected: normalizedSelection == style.id
                                ) {
                                    selection = style.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .onAppear(perform: normalizeSelection)
        .onChange(of: selection) { _, _ in
            normalizeSelection()
        }
    }

    private var normalizedSelection: CursorStyleID {
        CursorStyleRegistry.resolvedStyleID(selection)
    }

    private func normalizeSelection() {
        selection = normalizedSelection
    }
}

struct CursorStyleButton: View {
    var style: CursorStyleDefinition
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(7), help: style.title, action: action) {
            VStack(spacing: 5) {
                CursorGlyphView(styleID: style.id, scale: 0.56)
                    .frame(width: 38, height: 34)
                Text(style.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
            .background(isSelected ? Theme.accent.opacity(0.82) : Theme.overlay, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Theme.accent.opacity(0.95) : Theme.overlay)
            }
        }
    }
}

struct InspectorSwitch: View {
    var title: String
    @Binding var isOn: Bool
    var isInteractive = true

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .allowsHitTesting(isInteractive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rectangularHitTarget()
        .onTapGesture {
            guard isInteractive else { return }
            isOn.toggle()
        }
    }
}

struct PositionGrid: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(FacecamAnchor.allCases) { anchor in
                    StudioButton(hitTarget: .rounded(5), help: anchor.title) {
                        selection = anchor.rawValue
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected(anchor) ? Theme.accent.opacity(0.28) : Theme.overlay)
                            .frame(height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected(anchor) ? Theme.accent.opacity(0.5) : Theme.overlay)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func isSelected(_ anchor: FacecamAnchor) -> Bool {
        FacecamAnchor.resolve(selection) == anchor
    }
}

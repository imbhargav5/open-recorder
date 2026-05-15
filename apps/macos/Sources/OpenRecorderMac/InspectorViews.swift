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
    @Binding var cursorStyle: CursorStyle
    @Binding var cursorVariant: CursorVariant
    @Binding var facecamEnabled: Bool
    @Binding var facecamSize: Double
    @Binding var facecamBorderWidth: Double
    @Binding var facecamAnchor: String
    var recordingSession: RecordingSession?

    @State private var activeTab: InspectorTab = .appearance

    private var hasRecordedCamera: Bool {
        recordingSession?.hasRecordedCamera == true
    }

    var body: some View {
        HStack(spacing: 0) {
            inspectorRail
            inspectorContent
        }
        .studioEditorPaneChrome()
    }

    private func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var inspectorRail: some View {
        VStack(spacing: 8) {
            ForEach(InspectorTab.allCases) { tab in
                InspectorRailButton(tab: tab, isActive: activeTab == tab) {
                    activeTab = tab
                }
            }
        }
        .frame(width: 56)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(width: 1)
        }
    }

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inspectorHeader
                    tabContent
                }
                .padding(12)
            }

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            inspectorFooter
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: activeTab.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(activeTab.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(activeTab.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(activeTab.id)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06))
        }
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
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .appearance:
            InspectorSlider(title: "Shadow", valueText: "\(Int(shadow * 100))%", value: $shadow, range: 0...1, step: 0.01)
            InspectorSlider(title: "Roundness", valueText: "\(Int(borderRadius))px", value: $borderRadius, range: 0...25, step: 0.5)
            InspectorSlider(title: "Padding", valueText: "\(Int(padding))%", value: $padding, range: 0...100, step: 1)
            InspectorSlider(title: "Inset", valueText: "\(Int(inset.rounded()))", value: $inset, range: 0...100, step: 1)
            if inset > 0 {
                InsetColorPicker(color: $insetColor)
                InspectorSlider(title: "Inset Opacity", valueText: String(format: "%.2f", insetOpacity), value: $insetOpacity, range: 0...1, step: 0.01)
                InsetBalancePicker(balance: $insetBalance)
            }
            InspectorSlider(title: "Background Blur", valueText: String(format: "%.1fpx", backgroundBlur), value: $backgroundBlur, range: 0...8, step: 0.25)
            BackgroundPickerView(selection: $background)
        case .cursor:
            InspectorSwitch(title: "Show Cursor", isOn: $showCursor)
            CursorStylePicker(selection: $cursorStyle, variant: $cursorVariant)
            CursorVariantPicker(style: cursorStyle, selection: $cursorVariant)
            InspectorSwitch(title: "Loop Cursor", isOn: $loopCursor)
            InspectorSlider(title: "Size", valueText: String(format: "%.2fx", cursorSize), value: $cursorSize, range: 1...8, step: 0.05)
            InspectorSlider(title: "Smoothing", valueText: String(format: "%.2f", cursorSmoothing), value: $cursorSmoothing, range: 0...2, step: 0.01)
        case .camera:
            InspectorSwitch(title: "Facecam", isOn: $facecamEnabled, isInteractive: hasRecordedCamera)
                .disabled(!hasRecordedCamera)
                .opacity(hasRecordedCamera ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 16) {
                InspectorSlider(title: "Facecam Size", valueText: "\(Int(facecamSize.rounded()))%", value: $facecamSize, range: 12...40, step: 1)
                InspectorSlider(title: "Border Width", valueText: "\(Int(facecamBorderWidth.rounded()))px", value: $facecamBorderWidth, range: 0...16, step: 1)
                PositionGrid(selection: $facecamAnchor)
            }
            .disabled(!hasRecordedCamera || !facecamEnabled)
            .opacity(hasRecordedCamera && facecamEnabled ? 1 : 0.45)
            if let path = recordingSession?.facecamVideoPath {
                SessionAssetRow(title: "Facecam File", path: path)
            }
        case .audio:
            InspectorSwitch(title: "Mute Preview", isOn: .constant(false), isInteractive: false)
            InspectorSlider(title: "Volume", valueText: "100%", value: .constant(1), range: 0...1, step: 0.01)
            if let sourceName = recordingSession?.sourceName {
                SessionAssetRow(title: "Source", path: sourceName)
            }
        }
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
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(9), help: tab.title, action: action) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(isActive ? Color.brand : Color.secondary)
                .background(isActive ? Color.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isActive ? Color.brand.opacity(0.24) : Color.clear, lineWidth: 1)
                }
        }
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
                .foregroundStyle(.secondary)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
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
        case .appearance: "Frame styling, background, crop, and composition."
        case .cursor: "Cursor visibility and motion effects."
        case .camera: "Facecam overlay settings."
        case .audio: "Master preview and MP4 export audio."
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

struct InspectorSlider: View {
    var title: String
    var valueText: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
            }
            ElasticSlider(value: $value, range: range, step: step, onEditingChanged: onEditingChanged)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

struct InsetColorPicker: View {
    @Binding var color: SerializableColor

    private var colorBinding: Binding<Color> {
        Binding(
            get: { color.color },
            set: { color = SerializableColor(NSColor($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Inset color")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(color.hexString)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.88))
                }

                Spacer(minLength: 0)

                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 28, height: 28)
                    .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 5), spacing: 6) {
                ForEach(BackgroundPresets.solidColors.prefix(10), id: \.self) { swatch in
                    StudioButton(hitTarget: .rounded(7)) {
                        color = swatch
                    } label: {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(swatch.color)
                            .frame(height: 30)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(color == swatch ? Color.brand : Color.white.opacity(0.18), lineWidth: color == swatch ? 2 : 1)
                            }
                    }
                    .help(swatch.hexString)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}

struct InsetBalancePicker: View {
    @Binding var balance: VideoInsetBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Inset Balance")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("left: \(percent(balance.clamped.left)), top: \(percent(balance.clamped.top))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
            }

            GeometryReader { proxy in
                let resolvedBalance = balance.clamped
                let knobSize: CGFloat = 22
                let x = resolvedBalance.left * proxy.size.width
                let y = resolvedBalance.top * proxy.size.height

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.045))

                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                        path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                        path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                    }
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Circle()
                        .fill(Color.studioPanel)
                        .frame(width: knobSize, height: knobSize)
                        .overlay {
                            Circle()
                                .stroke(Color.brand, lineWidth: 2)
                        }
                        .shadow(color: Color.black.opacity(0.24), radius: 8, y: 4)
                        .position(x: x, y: y)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08))
                }
                .rectangularHitTarget()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateBalance(at: value.location, in: proxy.size)
                        }
                )
            }
            .frame(height: 116)

            StudioButton(hitTarget: .rounded(7)) {
                balance = .centered
            } label: {
                Label("Reset Balance", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(Color.secondary.opacity(0.92))
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.06))
                    }
            }
            .disabled(balance.clamped == .centered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func updateBalance(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        balance = VideoInsetBalance(
            left: max(0, min(location.x / size.width, 1)),
            top: max(0, min(location.y / size.height, 1))
        )
    }
}

struct CursorStylePicker: View {
    @Binding var selection: CursorStyle
    @Binding var variant: CursorVariant

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(CursorStyle.allCases) { style in
                    StudioButton(hitTarget: .rounded(7), help: style.title) {
                        selection = style
                        variant = style.resolvedVariant(variant)
                    } label: {
                        VStack(spacing: 5) {
                            CursorGlyphView(style: style, variant: style.resolvedVariant(variant), scale: 0.56)
                                .frame(width: 38, height: 34)
                            Text(style.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .foregroundStyle(selection == style ? Color.white : Color.primary.opacity(0.86))
                        .background(selection == style ? Color.brand.opacity(0.82) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selection == style ? Color.brand.opacity(0.95) : Color.white.opacity(0.07))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}

struct CursorVariantPicker: View {
    var style: CursorStyle
    @Binding var selection: CursorVariant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variant")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(style.supportedVariants) { variant in
                    StudioButton(hitTarget: .rounded(7), help: variant.title) {
                        selection = variant
                    } label: {
                        VStack(spacing: 4) {
                            CursorGlyphView(style: style, variant: variant, scale: 0.42)
                                .frame(width: 28, height: 24)
                            Text(variant.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(selection == variant ? Color.white : Color.primary.opacity(0.82))
                        .background(selection == variant ? Color.brand.opacity(0.82) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selection == variant ? Color.brand.opacity(0.95) : Color.white.opacity(0.08), lineWidth: selection == variant ? 2 : 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if selection == variant {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .padding(4)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .onAppear(perform: normalizeSelection)
        .onChange(of: style) { _, _ in
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        selection = style.resolvedVariant(selection)
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
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .allowsHitTesting(!isInteractive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
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
                            .fill(isSelected(anchor) ? Color.brand.opacity(0.28) : Color.white.opacity(0.06))
                            .frame(height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected(anchor) ? Color.brand.opacity(0.5) : Color.white.opacity(0.06))
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

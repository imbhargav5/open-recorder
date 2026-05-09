import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum HUDWindowMetrics {
    static let height: CGFloat = 155
    static let horizontalScreenMargin: CGFloat = 32
    static let minWidth: CGFloat = 360
    static let defaultSize = CGSize(width: 620, height: height)

    static func clampedSize(for measuredSize: CGSize, screen: NSScreen?) -> CGSize {
        clampedSize(for: measuredSize, visibleFrame: screen?.visibleFrame)
    }

    static func clampedSize(for measuredSize: CGSize, visibleFrame: CGRect?) -> CGSize {
        let measuredWidth = measuredSize.width.isFinite && measuredSize.width > 0
            ? measuredSize.width.rounded(.up)
            : defaultSize.width
        let maximumWidth = visibleFrame.map { frame in
            max(minWidth, frame.width - horizontalScreenMargin * 2)
        } ?? CGFloat.greatestFiniteMagnitude
        let width = min(max(measuredWidth, minWidth), maximumWidth)

        return CGSize(width: width.rounded(.up), height: height)
    }
}

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }

    func rectangularHitTarget() -> some View {
        contentShape(Rectangle())
    }

    func roundedHitTarget(_ cornerRadius: CGFloat) -> some View {
        contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func capsuleHitTarget() -> some View {
        contentShape(Capsule())
    }

    func circleHitTarget() -> some View {
        contentShape(Circle())
    }

    @ViewBuilder
    func studioHitTarget(_ target: StudioHitTarget) -> some View {
        switch target {
        case .rectangle:
            rectangularHitTarget()
        case .rounded(let cornerRadius):
            roundedHitTarget(cornerRadius)
        case .capsule:
            capsuleHitTarget()
        case .circle:
            circleHitTarget()
        }
    }
}

enum StudioHitTarget {
    case rectangle
    case rounded(CGFloat)
    case capsule
    case circle
}

struct StudioButton<Label: View>: View {
    var hitTarget: StudioHitTarget
    var help: String?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    init(
        hitTarget: StudioHitTarget = .rectangle,
        help: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.hitTarget = hitTarget
        self.help = help
        self.action = action
        self.label = label
    }

    var body: some View {
        let control = Button(action: action) {
            label()
                .studioHitTarget(hitTarget)
        }
        .buttonStyle(.plain)

        if let help {
            control.help(help)
        } else {
            control
        }
    }
}

struct StudioMenu<Label: View, Content: View>: View {
    var hitTarget: StudioHitTarget
    var help: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    init(
        hitTarget: StudioHitTarget = .rectangle,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.hitTarget = hitTarget
        self.help = help
        self.content = content
        self.label = label
    }

    var body: some View {
        let control = Menu {
            content()
        } label: {
            label()
                .studioHitTarget(hitTarget)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)

        if let help {
            control.help(help)
        } else {
            control
        }
    }
}


struct HUDSurface<Content: View>: View {
    var isRecording = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRecording
                                ? [Color(red: 0.16, green: 0.10, blue: 0.11), Color(red: 0.045, green: 0.043, blue: 0.055)]
                                : [Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.045, green: 0.043, blue: 0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(isRecording ? Color.red.opacity(0.24) : Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
            .shadow(color: Color.black.opacity(0.36), radius: 28, y: 18)
    }
}

struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 28, height: 36)
            .background(Color.white.opacity(0.001), in: Capsule())
    }
}

struct HUDDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 2)
    }
}

struct HUDControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(4)
        .background(Color.black.opacity(0.20), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct HUDPrimaryButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 100)
                .frame(height: 40)
                .padding(.horizontal, 14)
                .background(isDestructive ? Color.red.opacity(0.86) : Color.white, in: Capsule())
                .foregroundStyle(isDestructive ? Color.white : Color.studioBackground)
        }
    }
}

struct HUDPrimaryIconButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 42, height: 40)
                .background(isDestructive ? Color.red.opacity(0.86) : Color.white, in: Circle())
                .foregroundStyle(isDestructive ? Color.white : Color.studioBackground)
        }
    }
}

struct HUDIconActionButton: View {
    var symbolName: String
    var title: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(tint.opacity(0.95))
                .background(tint.opacity(0.14), in: Circle())
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

struct HUDPermissionGroup: View {
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label("Permission", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.red.opacity(0.95))
                .padding(.leading, 10)

            StudioButton(hitTarget: .capsule, action: action) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.red.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.red.opacity(0.95))
            }
        }
        .frame(height: 38)
        .padding(.trailing, 4)
        .background(Color.red.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        }
    }
}

struct CaptureModeButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 104)
                .frame(height: 38)
                .padding(.horizontal, 14)
                .foregroundStyle(isActive ? Color.studioBackground : Color.white.opacity(0.72))
                .background(isActive ? Color.white : Color.white.opacity(0.07), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(isActive ? 0 : 0.10), lineWidth: 1)
                }
        }
    }
}

enum FlowTone {
    case blue
    case green
    case red
    case amber
}

struct FlowLabel: View {
    var tone: FlowTone
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.65), radius: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.40))
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.84))
            }
        }
        .frame(width: 104, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08))
        }
    }

    private var dotColor: Color {
        switch tone {
        case .blue: Color.blue
        case .green: Color.green
        case .red: Color.red
        case .amber: Color.yellow
        }
    }
}

struct CompactFlowLabel: View {
    var tone: FlowTone
    var value: String

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(tone: tone)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.white.opacity(0.84))
        }
        .frame(width: 74, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08))
        }
    }
}

struct StatusDot: View {
    var tone: FlowTone

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .shadow(color: dotColor.opacity(0.65), radius: 7)
    }

    private var dotColor: Color {
        switch tone {
        case .blue: Color.blue
        case .green: Color.green
        case .red: Color.red
        case .amber: Color.yellow
        }
    }
}

struct SourceChip: View {
    var source: CaptureSource?
    var tone: FlowTone = .green
    var minWidth: CGFloat = 132
    var maxWidth: CGFloat = 198

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(tone: source == nil ? .amber : tone)
            Image(systemName: source?.kind == .window ? "macwindow" : source?.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(source?.name ?? "Choose source")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: max(48, maxWidth - 58), alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
        .frame(height: 38)
        .background(Color.black.opacity(0.20), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .capsuleHitTarget()
    }
}

struct CaptureStatusChip: View {
    var message: String
    var isError: Bool
    var maxWidth: CGFloat = 130

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isError ? Color.red.opacity(0.95) : Color.white.opacity(0.76))
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background((isError ? Color.red : Color.white).opacity(isError ? 0.12 : 0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke((isError ? Color.red : Color.white).opacity(isError ? 0.28 : 0.10), lineWidth: 1)
            }
    }
}

struct HUDToggle: View {
    var symbolName: String
    var isActive: Bool
    var title: String
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(isActive ? Color.blue.opacity(0.95) : Color.white.opacity(0.55))
                .background(isActive ? Color.blue.opacity(0.16) : Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isActive ? Color.blue.opacity(0.35) : Color.white.opacity(0.09), lineWidth: 1)
                }
        }
    }
}


extension Color {
    static let brand = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let studioBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let studioMutedBackground = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let studioPanel = Color(red: 0.075, green: 0.075, blue: 0.088)
    static let studioCard = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let studioControl = Color(red: 0.12, green: 0.12, blue: 0.145)
    static let studioBorder = Color.white.opacity(0.10)
    static let timelineClip = Color(red: 0.68, green: 0.40, blue: 0.02)
    static let timelineClipBorder = Color(red: 0.92, green: 0.56, blue: 0.06).opacity(0.52)
    static let timelineHandle = Color(red: 1.0, green: 0.68, blue: 0.05)
}

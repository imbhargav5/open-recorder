import SwiftUI

struct TranscriptEditor: View {
    var edits: TimelineEditDriver
    var playback: VideoPlaybackController
    @State private var selectedSegmentIDs: Set<UUID> = []

    private var track: CaptionTrack? { edits.snapshot.captions }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text("Transcript").font(.headline)
                Spacer()
                if !selectedSegmentIDs.isEmpty {
                    Button("Delete selected") { deleteSelected() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                }
            }

            if let track, !track.segments.isEmpty {
                Text("Select words to trim them from the video. Deleted segments become trim regions.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                ScrollView {
                    TranscriptTextFlow(
                        segments: track.segments,
                        selectedIDs: $selectedSegmentIDs,
                        currentTime: playback.currentTime,
                        seek: { playback.seek(to: $0) }
                    )
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No transcript available")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Generate captions first in the Captions tab, then return here to edit by transcript.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    private func deleteSelected() {
        guard let track else { return }
        let toDelete = track.segments.filter { selectedSegmentIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        let duration = playback.duration
        for segment in toDelete.sorted(by: { $0.start > $1.start }) {
            let span = TimelineSpan(start: segment.start, end: segment.end)
                .normalized(duration: duration)
            edits.send(.add(.trim, currentTime: span.start, duration: duration))
        }

        var updatedTrack = track
        updatedTrack.segments.removeAll { selectedSegmentIDs.contains($0.id) }
        updatedTrack.isEdited = true
        edits.send(.replaceCaptions(updatedTrack))
        selectedSegmentIDs.removeAll()
    }
}

private struct TranscriptTextFlow: View {
    var segments: [CaptionSegment]
    @Binding var selectedIDs: Set<UUID>
    var currentTime: Double
    var seek: (Double) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(segments) { segment in
                TranscriptWord(
                    segment: segment,
                    isActive: segment.contains(currentTime),
                    isSelected: selectedIDs.contains(segment.id),
                    onTap: {
                        if NSEvent.modifierFlags.contains(.shift) {
                            if selectedIDs.contains(segment.id) {
                                selectedIDs.remove(segment.id)
                            } else {
                                selectedIDs.insert(segment.id)
                            }
                        } else {
                            selectedIDs = [segment.id]
                        }
                        seek(segment.start)
                    }
                )
            }
        }
        .padding(8)
    }
}

private struct TranscriptWord: View {
    var segment: CaptionSegment
    var isActive: Bool
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Text(segment.text)
            .font(.system(size: 13, weight: isActive ? .bold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isSelected ? Color.red.opacity(0.3) :
                    (isActive ? Color.accentColor.opacity(0.2) : Color.clear),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityLabel(segment.text)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                                  proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var offsets: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return ArrangeResult(offsets: offsets, size: CGSize(width: maxX, height: y + rowHeight))
    }
}

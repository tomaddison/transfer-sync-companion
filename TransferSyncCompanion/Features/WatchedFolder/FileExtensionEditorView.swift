import SwiftUI

struct FileExtensionEditorView: View {
    @Environment(WatchedFolderManager.self) private var manager
    @State private var newExtension = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File Types")
                    .font(.headline)

                Spacer()

                Button("Reset") {
                    manager.whitelist.reset()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.ghost)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Extension tags
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(sortedExtensions, id: \.self) { ext in
                        extensionTag(ext)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            // Add extension
            HStack(spacing: 8) {
                TextField("Extension", text: $newExtension)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button("Add") {
                    guard !newExtension.isEmpty else { return }
                    manager.whitelist.addExtension(newExtension)
                    newExtension = ""
                }
                .font(.caption)
                .buttonStyle(.ghost)
                .disabled(newExtension.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var sortedExtensions: [String] {
        manager.whitelist.extensions.sorted()
    }

    private func extensionTag(_ ext: String) -> some View {
        HStack(spacing: 4) {
            Text(".\(ext)")
                .font(.caption)

            Button {
                manager.whitelist.removeExtension(ext)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.ghostIcon(size: 16))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Simple flow layout for extension tags.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

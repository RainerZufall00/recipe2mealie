import SwiftUI

extension Color {
    /// The warm orange of the app icon.
    public static let brand = Color(red: 0.86, green: 0.49, blue: 0.20)
}

extension ShapeStyle where Self == Color {
    public static var brand: Color { Color.brand }
}

/// Recipe photo from Mealie with a warm placeholder while loading or when there is none.
public struct RecipeImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 20

    public init(url: URL?, cornerRadius: CGFloat = 20) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().transition(.opacity)
                    default:
                        placeholder
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        LinearGradient(colors: [.brand.opacity(0.35), .brand.opacity(0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.title)
                    .foregroundStyle(.brand.opacity(0.7))
            }
    }
}

/// Small rounded label, e.g. "25 min" or a tag.
public struct InfoChip: View {
    let title: String
    let systemImage: String?

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: .capsule)
    }
}

/// Wrapping layout for chips.
public struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Card background used across the import flow.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 28))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

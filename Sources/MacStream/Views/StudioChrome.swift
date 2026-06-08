import SwiftUI

struct StudioBadge: View {
    var title: String
    var systemImage: String?
    var tint: Color
    var isFilled = false

    var body: some View {
        badgeContent
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isFilled ? Color.white : tint)
            .background {
                Capsule()
                    .fill(isFilled ? tint : tint.opacity(0.14))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isFilled ? Color.white.opacity(0.16) : tint.opacity(0.18), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var badgeContent: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

struct StudioGroupLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .lineLimit(1)
    }
}

private struct StudioCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

extension View {
    func studioCard(padding: CGFloat = 14, cornerRadius: CGFloat = 14) -> some View {
        modifier(StudioCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

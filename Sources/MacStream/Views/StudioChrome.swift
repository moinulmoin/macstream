import SwiftUI

// MARK: - Design tokens

enum StudioMetrics {
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14

    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

enum StudioPalette {
    /// Brand accent used for primary actions and selection. Applied app-wide via `.tint`.
    static let accent = Color(red: 0.36, green: 0.42, blue: 0.86)
    static let live = Color(red: 0.93, green: 0.27, blue: 0.32)
    static let recording = Color(red: 0.96, green: 0.46, blue: 0.20)
    static let success = Color(red: 0.28, green: 0.78, blue: 0.46)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.20)
    static let info = Color(red: 0.34, green: 0.62, blue: 0.96)
}

// MARK: - Badges & labels

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
                    .fill(isFilled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isFilled ? Color.white.opacity(0.22) : tint.opacity(0.20), lineWidth: 1)
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

/// A small status dot, optionally pulsing, for live/recording indicators.
struct StudioStatusDot: View {
    var tint: Color
    var pulsing: Bool = false
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(tint.gradient)
            .frame(width: 8, height: 8)
            .overlay {
                if pulsing {
                    Circle()
                        .stroke(tint, lineWidth: 2)
                        .scaleEffect(animate ? 2.6 : 1)
                        .opacity(animate ? 0 : 0.7)
                }
            }
            .shadow(color: tint.opacity(0.6), radius: pulsing ? 4 : 0)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

// MARK: - Panel header

/// Standard panel header: tinted glyph chip, title, optional subtitle, trailing accessory.
struct StudioPanelHeader<Trailing: View>: View {
    var title: String
    var systemImage: String
    var subtitle: String?
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        tint: Color = StudioPalette.accent,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: StudioMetrics.md) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: StudioMetrics.sm)

            trailing()
        }
    }
}

extension StudioPanelHeader where Trailing == EmptyView {
    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        tint: Color = StudioPalette.accent
    ) {
        self.init(title: title, systemImage: systemImage, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - Button styles

/// Prominent, responsive primary action (hover lift, press depress, focus glow).
struct StudioPrimaryButtonStyle: ButtonStyle {
    var tint: Color = StudioPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, tint: tint)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                        .fill(tint.gradient)
                        .brightness(configuration.isPressed ? -0.05 : (hovering ? 0.06 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: tint.opacity(isEnabled ? 0.40 : 0), radius: configuration.isPressed ? 3 : 9, y: 3)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: hovering)
        }
    }
}

/// Quiet, responsive secondary action that complements the primary style.
struct StudioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }

    private struct SecondaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.12 : 0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: hovering)
        }
    }
}

// MARK: - Card

private struct StudioCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

extension View {
    func studioCard(padding: CGFloat = StudioMetrics.cardPadding, cornerRadius: CGFloat = StudioMetrics.cardRadius) -> some View {
        modifier(StudioCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

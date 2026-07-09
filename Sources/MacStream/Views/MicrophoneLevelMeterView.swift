import SwiftUI

struct MicrophoneLevelMeterView: View {
    var level: Double
    var title = "Mic level"
    var detail: String?
    var isActive = true

    var body: some View {
        let normalizedLevel = min(max(level, 0), 1)

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(detail ?? "\(Int((normalizedLevel * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary.opacity(isActive ? 1 : 0.6))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(levelFill)
                        .frame(width: meterWidth(in: proxy.size.width, level: normalizedLevel))
                        .opacity(isActive ? 1 : 0.35)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int((normalizedLevel * 100).rounded())) percent"))
    }

    private var levelFill: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func meterWidth(in width: CGFloat, level: Double) -> CGFloat {
        guard isActive, level > 0 else { return 0 }
        return max(6, width * level)
    }
}

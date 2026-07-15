import SwiftUI
import MacStreamCore

struct StudioMicrophoneLevelMeterView: View {
    var store: StudioStore
    var title = "Mic level"
    var showsStatusDetail = false

    var body: some View {
        MicrophoneLevelMeterView(
            level: store.latestSignals.speechLevel,
            title: title,
            detail: showsStatusDetail ? statusDetail : nil,
            isActive: isActive
        )
        .help(helpText)
    }

    private var isActive: Bool {
        store.isSourceEnabled(.microphone)
            && store.sourceLevel(.microphone) > 0
            && store.selectedMicrophoneDeviceID != nil
    }

    private var statusDetail: String {
        if !store.isSourceEnabled(.microphone) { return "Off" }
        if store.sourceLevel(.microphone) <= 0 { return "Muted" }
        if store.selectedMicrophoneDeviceID == nil { return "No input" }
        if store.latestSignals.isMicMuted { return "No signal" }
        return "\(Int((store.latestSignals.speechLevel * 100).rounded()))%"
    }

    private var helpText: String {
        if !store.isSourceEnabled(.microphone) { return "Turn the microphone source on in Sources." }
        if store.sourceLevel(.microphone) <= 0 { return "Raise the microphone source level in Sources." }
        if store.selectedMicrophoneDeviceID == nil { return "Choose a microphone in Sources or Capture preflight." }
        return "Live microphone input level."
    }
}

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

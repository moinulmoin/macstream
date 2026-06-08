import SwiftUI
import MacStreamCore

struct DirectorPanelView: View {
    var store: StudioStore

    var body: some View {
        if let recommendation = store.recommendation {
            expandedDirectorPanel(for: recommendation)
        } else {
            compactDirectorPanel
        }
    }

    private var compactDirectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Director", systemImage: "sparkles.tv")
                    .font(.headline)

                StudioBadge(title: store.directorMode.title, systemImage: "sparkles", tint: directorModeTint)

                Spacer(minLength: 10)

                directorActionButtons
            }

            HStack(spacing: 8) {
                Label("No cue pending", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            SignalStripView(signals: store.latestSignals)
        }
        .studioCard()
    }

    private func expandedDirectorPanel(for recommendation: DirectorRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Director", systemImage: "sparkles.tv")
                    .font(.headline)

                StudioBadge(title: store.directorMode.title, systemImage: "sparkles", tint: directorModeTint)

                Spacer()

                directorActionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Cue \(recommendation.target.title)", systemImage: recommendation.target.symbolName)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    StudioBadge(title: "\(Int(recommendation.confidence * 100))%", systemImage: "gauge.with.dots.needle.50percent", tint: recommendationTint(for: recommendation), isFilled: recommendation.urgency == .immediate)
                }

                Text(recommendation.reason)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let cueTimingText = cueTimingText(for: recommendation) {
                    Label(cueTimingText, systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if recommendation.target != store.selectedSceneKind {
                        Button {
                            store.applyRecommendation()
                        } label: {
                            Label("Take", systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canApplyRecommendation)
                        .help(store.recommendationActionBlockedReason ?? "Take cue")
                    }

                    Button {
                        store.dismissRecommendation()
                    } label: {
                        Label("Hold", systemImage: "hand.raised")
                    }
                    .help("Keep the current scene")
                }
                .controlSize(.regular)
            }
            .padding(12)
            .background(recommendationTint(for: recommendation).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(recommendationTint(for: recommendation).opacity(0.18), lineWidth: 1)
            }

            SignalStripView(signals: store.latestSignals)
        }
        .studioCard()
    }

    private var directorActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.advanceDirector()
            } label: {
                Label(store.isLive ? "Tick" : "Sample", systemImage: "waveform.path")
            }
            .help(store.isLive ? "Run one director evaluation now" : "Preview one director evaluation")

            Button {
                store.markClip()
            } label: {
                Label("Clip", systemImage: "bookmark")
            }
            .disabled(!store.canMarkClip)
            .help(store.canMarkClip ? "Mark clip" : "Start streaming or recording before marking a clip")
        }
        .controlSize(.small)
    }

    private var directorModeTint: Color {
        switch store.directorMode {
        case .paused: .secondary
        case .suggest: .accentColor
        case .auto: .purple
        }
    }

    private func recommendationTint(for recommendation: DirectorRecommendation) -> Color {
        switch recommendation.urgency {
        case .calm: .accentColor
        case .soon: .orange
        case .immediate: .red
        }
    }

    private func cueTimingText(for recommendation: DirectorRecommendation) -> String? {
        if store.directorMode == .auto,
           recommendation.target != store.selectedSceneKind,
           let remainingSeconds = store.autoCueRemainingSeconds {
            return remainingSeconds > 0 ? "Auto in \(remainingSeconds)s" : "Switching now"
        }

        guard recommendation.delaySeconds > 0 else { return nil }
        return "\(recommendation.delaySeconds)s cue"
    }
}

private struct SignalStripView: View {
    var signals: SignalSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideSignals
            stackedSignals
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Director signals"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var wideSignals: some View {
        HStack(spacing: 8) {
            micSignal
            motionSignal
            appSignal
            idleSignal
        }
    }

    private var stackedSignals: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                micSignal
                motionSignal
            }
            HStack(spacing: 8) {
                appSignal
                idleSignal
            }
        }
    }

    private var micSignal: some View {
        signal("Mic", value: "\(Int(signals.speechLevel * 100))%", symbol: signals.isSpeaking ? "waveform" : "mic")
    }

    private var motionSignal: some View {
        signal("Motion", value: "\(Int(signals.screenMotion * 100))%", symbol: "rectangle.dashed")
    }

    private var appSignal: some View {
        signal("App", value: signals.activeApplication, symbol: "app")
    }

    private var idleSignal: some View {
        signal(signals.isScreenFrozen ? "Screen" : "Idle", value: signals.isScreenFrozen ? "Frozen" : "\(Int(signals.idleSeconds))s", symbol: signals.isScreenFrozen ? "exclamationmark.triangle" : "timer")
    }

    private var accessibilityValue: String {
        "Mic \(Int(signals.speechLevel * 100)) percent. Motion \(Int(signals.screenMotion * 100)) percent. App \(signals.activeApplication). \(signals.isScreenFrozen ? "Screen frozen" : "Idle \(Int(signals.idleSeconds)) seconds")."
    }

    private func signal(_ title: String, value: String, symbol: String) -> some View {
        Label {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

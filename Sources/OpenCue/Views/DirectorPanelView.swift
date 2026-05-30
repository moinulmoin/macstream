import SwiftUI
import OpenCueCore

struct DirectorPanelView: View {
    @Bindable var store: StudioStore

    var body: some View {
        if let recommendation = store.recommendation {
            expandedDirectorPanel(for: recommendation)
        } else {
            compactDirectorPanel
        }
    }

    private var compactDirectorPanel: some View {
        HStack(spacing: 12) {
            Label("Director", systemImage: "sparkles.tv")
                .font(.headline)

            Divider()
                .frame(height: 24)

            Label("No cue pending", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 10)

            SignalStripView(signals: store.latestSignals)

            directorActionButtons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func expandedDirectorPanel(for recommendation: DirectorRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Director", systemImage: "sparkles.tv")
                    .font(.headline)
                Spacer()
                directorActionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cue \(recommendation.target.title)", systemImage: recommendation.target.symbolName)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(Int(recommendation.confidence * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(recommendation.reason)
                    .foregroundStyle(.secondary)

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
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            SignalStripView(signals: store.latestSignals)
        }
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
                Image(systemName: "bookmark")
            }
            .disabled(!store.canMarkClip)
            .help(store.canMarkClip ? "Mark clip" : "Start streaming or recording before marking a clip")
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
        HStack(spacing: 10) {
            signal("Mic", value: "\(Int(signals.speechLevel * 100))%", symbol: signals.isSpeaking ? "waveform" : "mic")
            signal("Motion", value: "\(Int(signals.screenMotion * 100))%", symbol: "rectangle.dashed")
            signal("App", value: signals.activeApplication, symbol: "app")
            signal(signals.isScreenFrozen ? "Screen" : "Idle", value: signals.isScreenFrozen ? "Frozen" : "\(Int(signals.idleSeconds))s", symbol: signals.isScreenFrozen ? "exclamationmark.triangle" : "timer")
        }
        .font(.caption)
        .lineLimit(1)
    }

    private func signal(_ title: String, value: String, symbol: String) -> some View {
        Label {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .fontWeight(.semibold)
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

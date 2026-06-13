import Combine
import Sparkle
import SwiftUI

/// App-owned wrapper around Sparkle's standard updater.
///
/// A single instance is created by `MacStreamApp` and shared between the
/// "Check for Updates…" menu command and the Settings "About & Updates" tab,
/// so the app never spins up two `SPUUpdater` instances. Sparkle's updater is
/// main-actor only, hence `@MainActor`.
@MainActor
@Observable
final class SparkleUpdater {
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: AnyCancellable?

    /// Mirrors `SPUUpdater.canCheckForUpdates` (KVO-compliant) so SwiftUI can
    /// enable/disable the check action while a check is already in flight.
    private(set) var canCheckForUpdates = false

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater
            .publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = canCheck
                }
            }
    }

    /// Starts a user-initiated update check with Sparkle's standard progress UI.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// Menu body for the standard `Check for Updates…` item. Receives the shared
/// `SparkleUpdater` rather than creating its own.
struct CheckForUpdatesCommand: View {
    var updater: SparkleUpdater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

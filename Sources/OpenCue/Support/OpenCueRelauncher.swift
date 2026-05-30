import AppKit
import Foundation

enum OpenCueRelauncher {
    @MainActor
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]

        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(bundleURL)
        }

        NSApplication.shared.terminate(nil)
    }
}

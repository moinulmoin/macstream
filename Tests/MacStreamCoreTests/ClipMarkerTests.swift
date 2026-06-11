import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
@MainActor
func manualClipMarkerUsesSelectedScene() async {
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Great moment.")

    #expect(store.clipMarkers.count == 1)
    #expect(store.canExportClipMarkers)
    #expect(store.clipMarkers[0].scene == store.selectedSceneKind)
    #expect(store.clipMarkers[0].source == .manual)
    #expect(store.events[0].kind == .clip)
}

@Test
@MainActor
func manualClipMarkerNormalizesReasonForExport() async {
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "   \n\t")

    #expect(store.clipMarkers[0].reason == "Marked by operator.")
    #expect(store.events[0].detail == "Marked by operator.")

    let longReason = String(repeating: "a", count: 400)
    store.markClip(reason: longReason)

    #expect(store.clipMarkers[0].reason.count == 240)
    #expect(store.events[0].detail.count == 240)
}

@Test
@MainActor
func manualClipMarkerRequiresActiveCapture() {
    let store = StudioStore()

    store.markClip(reason: "Not live.")

    #expect(!store.canMarkClip)
    #expect(!store.canExportClipMarkers)
    #expect(store.clipMarkers.isEmpty)
    #expect(store.events[0].title == "Clip unavailable")
}

@Test
@MainActor
func repeatedUnavailableClipMarksDoNotSpamEvents() {
    let store = StudioStore()

    store.markClip(reason: "Not live.")
    store.markClip(reason: "Still not live.")

    #expect(store.clipMarkers.isEmpty)
    #expect(store.events.filter { $0.title == "Clip unavailable" }.count == 1)
}

@Test
@MainActor
func directorAddsAutomaticClipMarkerForLiveSafetyCue() async {
    let pipeline = SpyMediaPipeline()
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.clipMarkers.count == 1)
    #expect(store.clipMarkers[0].source == .director)
    #expect(store.clipMarkers[0].scene == .face)
}

@Test
@MainActor
func directorDoesNotAutoMarkClipsWhenOffline() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)

    store.advanceDirector()

    #expect(store.recommendation?.urgency == .immediate)
    #expect(store.clipMarkers.isEmpty)
}

@Test
func clipMarkerExporterWritesJSONPayload() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-clip-export-\(UUID().uuidString)", isDirectory: true)
    let marker = ClipMarker(
        title: "Clip Face",
        reason: "Great explanation.",
        scene: .face,
        source: .manual,
        timestamp: Date(timeIntervalSince1970: 10)
    )

    let url = try ClipMarkerExporter().export(
        [marker],
        to: directory,
        now: Date(timeIntervalSince1970: 20)
    )

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(ClipMarkerExportPayload.self, from: data)

    #expect(payload.markers == [marker])
}

@Test
func clipMarkerExporterAvoidsSameSecondOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-clip-export-collision-\(UUID().uuidString)", isDirectory: true)
    let marker = ClipMarker(
        title: "Clip Face",
        reason: "Great explanation.",
        scene: .face,
        source: .manual,
        timestamp: Date(timeIntervalSince1970: 10)
    )
    let now = Date(timeIntervalSince1970: 20)
    let exporter = ClipMarkerExporter()

    let firstURL = try exporter.export([marker], to: directory, now: now)
    let secondURL = try exporter.export([marker], to: directory, now: now)

    #expect(firstURL != secondURL)
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
}

@Test
@MainActor
func studioStoreExportsClipMarkers() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-store-export-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Worth review.")
    let url = store.exportClipMarkers(to: directory)

    #expect(url != nil)
    #expect(store.latestClipExportURL == url)
    #expect(store.events[0].title == "Clips exported")
    #expect(FileManager.default.fileExists(atPath: url?.path ?? ""))
}

@Test
@MainActor
func newCaptureSessionClearsPreviousClipArtifacts() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-clear-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Old moment.")
    let exportURL = store.exportClipMarkers(to: directory)
    #expect(exportURL != nil)
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.clipMarkers.isEmpty)
    #expect(store.latestClipExportURL == nil)
    #expect(store.latestSessionReportURL == nil)
    #expect(store.events.contains { $0.title == "Session started" })
}

@Test
@MainActor
func studioStoreDoesNotExportEmptyClipMarkers() {
    let store = StudioStore()

    let url = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)

    #expect(!store.canExportClipMarkers)
    #expect(url == nil)
    #expect(store.latestClipExportURL == nil)
    #expect(store.events[0].title == "No clips")
}

@Test
@MainActor
func repeatedEmptyClipExportsDoNotSpamEvents() {
    let store = StudioStore()

    let firstURL = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)
    let secondURL = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)

    #expect(firstURL == nil)
    #expect(secondURL == nil)
    #expect(store.events.filter { $0.title == "No clips" }.count == 1)
}

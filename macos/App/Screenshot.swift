// Renders the panel to a PNG for the README.
//
// This draws the view offscreen rather than taking a picture of the screen, so
// it needs no screen recording permission, gives the same image every time,
// and cannot possibly capture a real calendar: the data comes from
// SampleData.swift.
//
// Run it with: make screenshot

import AppKit
import SwiftUI

import CrossroadsCore

enum Screenshot {
    /// Draws the panel into `directory`.
    @MainActor
    static func write(into directory: URL) throws {
        let model = AppModel.shared
        model.settings = sampleSettings
        let now = sampleNow()
        model.snapshot = sampleSnapshot(now: now)
        model.calendars = sampleCalendars
        model.days = model.settings.defaultRange
        model.selection = 0

        try render(
            PanelView(model: model, forScreenshot: true),
            to: directory.appending(path: "screenshot-macos.png")
        )
    }

    private struct CouldNotRender: Error {
        let path: String
    }

    @MainActor
    private static func render(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.now, sampleNow()))
        // Twice the size, so the picture stays sharp when the README scales it.
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            throw CouldNotRender(path: url.path)
        }
        try data.write(to: url)
        FileHandle.standardError.write("wrote \(url.lastPathComponent)\n".data(using: .utf8)!)
    }
}

// The menu bar icon, and the shortcut that opens the panel.

import AppKit
import SwiftUI

import CrossroadsCore

@main
struct CrossroadsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Button(model.flagged == 0 ? "Open Crossroads" : "Open Crossroads (\(model.flagged))") {
                delegate.panel?.show()
            }
            .keyboardShortcut("o")

            Button("Settings") {
                model.showingSettings = true
                delegate.panel?.show()
            }

            Divider()
            Button("Quit Crossroads") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            // The one-color mark as a template image, so it follows the menu bar.
            HStack(spacing: 3) {
                Image("MenuBarIcon")
                if model.flagged > 0 {
                    Text("\(model.flagged)")
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: PanelController?
    private let hotkey = Hotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--screenshot <dir>` draws the panel with made-up data and stops. It
        // never touches EventKit, so it needs no permission and shows nobody's
        // real calendar.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--screenshot"), flag + 1 < arguments.count {
            do {
                try Screenshot.write(into: URL(fileURLWithPath: arguments[flag + 1]))
                exit(0)
            } catch {
                FileHandle.standardError.write("screenshot failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }

        let model = AppModel.shared
        let panel = PanelController(model: model)
        self.panel = panel

        // Keep the old shortcut when the new one is already taken, so there is
        // always exactly one (Settings.OneShortcut, ShortcutNeverConflicts).
        Task { await model.refresh() }

        let took = hotkey.register(model.settings.shortcut) { panel.toggle() }
        if !took {
            NSLog("Crossroads: %@ is already taken, so no shortcut is registered", model.settings.shortcut.label)
        }
    }
}

// The menu bar icon, and the shortcut that opens the panel.

import AppKit
import ServiceManagement
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
                model.state.showingSettings = true
                delegate.panel?.show()
            }

            Divider()

            Toggle("Open at login", isOn: Binding(
                get: { LaunchAtLogin.isOn },
                set: { LaunchAtLogin.set($0) }
            ))

            Button(googleTitle) {
                Task { await signIn() }
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

extension CrossroadsApp {
    private var googleTitle: String {
        let accounts = GoogleAuth.signedInAccounts()
        if accounts.isEmpty { return "Connect Gmail…" }
        return "Connect another Gmail account… (\(accounts.count) connected)"
    }

    /// Asks which account, then runs the consent flow in the browser.
    private func signIn() async {
        guard GoogleAuth.hasClient else {
            await MainActor.run { chooseClientFile() }
            return
        }
        guard let account = await MainActor.run(body: { askForAccount() }) else { return }
        do {
            try await GoogleAuth.signIn(account: account)
            await AppModel.shared.refresh()
        } catch {
            await MainActor.run { report(error) }
        }
    }

    /// The first time, Crossroads needs the OAuth client you made in Google
    /// Cloud. See macos/README.md.
    @MainActor
    private func chooseClientFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Google OAuth client"
        panel.message = "Pick the client_secret….json you downloaded from Google Cloud."
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            try GoogleAuth.saveClient(from: file)
            Task { await signIn() }
        } catch {
            report(error)
        }
    }

    @MainActor
    private func askForAccount() -> String? {
        let alert = NSAlert()
        alert.messageText = "Which Google account?"
        alert.informativeText = "Crossroads reads unread mail from this account. It never reads message bodies."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "you@gmail.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "Sign in")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let account = field.stringValue.trimmingCharacters(in: .whitespaces)
        return account.isEmpty ? nil : account
    }

    @MainActor
    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not connect Gmail"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}

/// Opening at login, through the system rather than a login item of our own.
enum LaunchAtLogin {
    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Crossroads: could not change open at login: %@", error.localizedDescription)
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

        // `--demo` runs the real app on made-up data, for taking a screenshot.
        // It reads no account and saves no setting.
        let demo = arguments.contains("--demo")
        if demo { model.startDemo() }

        let panel = PanelController(model: model)
        self.panel = panel

        // Keep the old shortcut when the new one is already taken, so there is
        // always exactly one (Settings.OneShortcut, ShortcutNeverConflicts).
        if demo {
            // Opening it here is too early: the app has not finished coming up
            // and the panel never appears. The next pass of the run loop works.
            DispatchQueue.main.async { panel.show() }
        } else {
            Task { await model.refresh() }
        }

        // Changing the shortcut in settings re-registers it, and says whether
        // the system gave it to us so the old one can be kept.
        model.registerShortcut = { [hotkey, weak panel] shortcut in
            hotkey.register(shortcut) { panel?.toggle() }
        }

        let took = hotkey.register(model.state.settings.shortcut) { panel.toggle() }
        if !took {
            NSLog("Crossroads: %@ is already taken, so no shortcut is registered", model.state.settings.shortcut.label)
        }

        // A timer does not fire while the Mac is asleep, so the data would be
        // as old as the nap without this.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in await AppModel.shared.refreshIfDue() }
        }
    }
}

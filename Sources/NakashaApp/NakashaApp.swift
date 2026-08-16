import SwiftUI
import NakashaCore

@main
struct NakashaApp: App {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup("NAKASHA") {
            // No frame here. ContentView already declares the minimum it needs;
            // declaring a SECOND, smaller minimum on the same view made the window
            // open at the full size of the display instead of the default below.
            ContentView()
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            // The menu bar was deliberately left bare, on the theory that advocates
            // want to drop a file and go. That was wrong: with no menu there is no
            // Cmd-, for Settings and no Cmd-+ for text size, and on a 27-inch display
            // the table is unreadable with no visible way to fix it. Menus are where
            // macOS users look for exactly these two things.

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NotificationCenter.nakasha_post(.openSettings) }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Bigger Text") { settings.nudgeTextSize(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Bigger Text (=)") { settings.nudgeTextSize(by: 1) }
                    // Cmd-= is what the key actually is on most layouts without Shift.
                    .keyboardShortcut("=", modifiers: .command)
                Button("Smaller Text") { settings.nudgeTextSize(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { settings.tableTextSize = 12 }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Board…") { NotificationCenter.nakasha_post(.openBoard) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Remove All Boards") { NotificationCenter.nakasha_post(.clearBoards) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Find My Matters") { NotificationCenter.nakasha_post(.run) }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Export PDF…") { NotificationCenter.nakasha_post(.exportPDF) }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Export CSV…") { NotificationCenter.nakasha_post(.exportCSV) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("About NAKASHA") { NotificationCenter.nakasha_post(.openAbout) }
            }
        }
    }
}

/// Menu commands cannot reach the window's model directly, so they post and the
/// window listens. Kept as one small enum rather than scattered string names, so a
/// typo is a compile error instead of a menu item that silently does nothing.
enum NakashaCommand: String {
    case openBoard, clearBoards, run, exportPDF, exportCSV, openSettings, openAbout

    var notification: Notification.Name { Notification.Name("nakasha." + rawValue) }
}

extension NotificationCenter {
    static func nakasha_post(_ command: NakashaCommand) {
        NotificationCenter.default.post(name: command.notification, object: nil)
    }
}

extension View {
    /// Runs `action` when the given menu command fires.
    func onCommand(_ command: NakashaCommand, perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: command.notification)) { _ in
            action()
        }
    }
}

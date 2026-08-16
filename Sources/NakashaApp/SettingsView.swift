import SwiftUI
import AppKit

/// User-facing appearance and table legibility settings. Persisted to
/// UserDefaults.standard under NAKASHA.* keys; nothing else reads or writes
/// those keys, so clearing them resets the app's visible state cleanly.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {

    /// One instance. The menu bar changes the text size and the window must see
    /// the same object, or Cmd-+ moves a number nothing is bound to.
    static let shared = SettingsStore()

    /// Steps the results-table text size and clamps it. Driven by Cmd-+ / Cmd--.
    func nudgeTextSize(by delta: Double) {
        tableTextSize = min(20, max(9, tableTextSize + delta))
    }


    private enum Key {
        static let appearance = "NAKASHA.appearance"
        static let tableTextSize = "NAKASHA.tableTextSize"
    }

    private static let minTextSize: Double = 9
    private static let maxTextSize: Double = 20
    private static let defaultTextSize: Double = 12

    @Published var appearance: AppearanceChoice {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    @Published var tableTextSize: Double {
        didSet {
            let clamped = Self.clamp(tableTextSize)
            guard clamped != tableTextSize else {
                // Already in range; persist the (possibly nudged) value and stop.
                UserDefaults.standard.set(clamped, forKey: Key.tableTextSize)
                return
            }
            // Reassign with the clamped value. didSet will fire once more with
            // a value that is already in range, at which point the guard above
            // breaks the recursion.
            tableTextSize = clamped
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Key.appearance) ?? AppearanceChoice.system.rawValue
        self.appearance = AppearanceChoice(rawValue: raw) ?? .system

        let stored = defaults.object(forKey: Key.tableTextSize) as? Double
            ?? Self.defaultTextSize
        let initial = Self.clamp(stored)
        // Write back the clamped value so the on-disk state is always valid.
        defaults.set(initial, forKey: Key.tableTextSize)
        self.tableTextSize = initial

        // Push the loaded appearance to NSApp immediately so the window chrome
        // matches user expectation on launch.
        applyAppearance()
    }

    /// Push the current `appearance` to NSApp. Safe to call repeatedly.
    func apply() {
        applyAppearance()
    }

    private func applyAppearance() {
        // `NSApp` is an implicitly-unwrapped global that is nil until NSApplication
        // exists. This store is a `static let shared` read from `NakashaApp.init()`,
        // which runs BEFORE that — so touching NSApp here crashed the app on launch
        // with a nil unwrap, every time, before a window was ever shown.
        //
        // Skipping is safe and complete: `ContentView.onAppear` calls `apply()` again
        // once there is an application to apply it to.
        guard NSApp != nil else { return }
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        if value < minTextSize { return minTextSize }
        if value > maxTextSize { return maxTextSize }
        return value
    }
}

/// Settings UI. One screen: appearance and the one knob that affects whether
/// the table is usable on a 13-inch laptop versus a 27-inch display.
struct SettingsView: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker("Appearance", selection: $store.appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("Results table text size")
                        Spacer()
                        Text("\(Int(store.tableTextSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $store.tableTextSize,
                        in: SettingsStore.minMaxForSlider,
                        step: 1
                    )
                    Text("Advocates use Macs from 13-inch laptops to 27-inch displays, and an unreadable table is a useless table.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420)
        .padding(20)
    }
}

private extension SettingsStore {
    /// Exposed for the Slider's `in:` argument without leaking the raw bounds.
    static var minMaxForSlider: ClosedRange<Double> {
        minTextSize ... maxTextSize
    }
}

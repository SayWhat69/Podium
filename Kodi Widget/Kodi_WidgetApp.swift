import SwiftUI
import SwiftData
import Kingfisher

@main
struct KodiWidgetApp: App {

    init() {
        seedUserDefaults()
        configureKingfisher()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Device.self, AppSettings.self])
    }

    // MARK: - Setup

    /// Registers defaults from Settings.bundle so `UserDefaults` values match
    /// what iOS Settings shows before the user makes any change.
    private func seedUserDefaults() {
        guard let url = Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"),
              let plist = NSDictionary(contentsOf: url) as? [String: Any],
              let prefs = plist["PreferenceSpecifiers"] as? [[String: Any]]
        else { return }

        let defaults = prefs.reduce(into: [String: Any]()) { result, pref in
            if let key = pref["Key"] as? String, let value = pref["DefaultValue"] {
                result[key] = value
            }
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Caps Kingfisher's in-memory image cache to prevent unbounded growth.
    private func configureKingfisher() {
        ImageCache.default.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        ImageCache.default.diskStorage.config.sizeLimit = 500 * 1024 * 1024        // 500 MB
    }
}

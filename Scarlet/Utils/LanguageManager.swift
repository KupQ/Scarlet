//
//  LanguageManager.swift
//  Scarlet
//
//  Runtime language switching without restarting the app.
//

import SwiftUI

/// Manages in-app language switching independently of system locale.
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    struct AppLanguage: Identifiable, Equatable {
        let id: String        // locale code: "en", "ru"
        let name: String      // native name: "English", "Русский"
        let flag: String      // emoji flag
    }

    static let supportedLanguages: [AppLanguage] = [
        AppLanguage(id: "en", name: "English", flag: "🇺🇸"),
        AppLanguage(id: "ru", name: "Русский", flag: "🇷🇺"),
    ]

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "app_language")
            loadBundle()
        }
    }

    private(set) var bundle: Bundle = .main

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "app_language") {
            // User has explicitly chosen a language — use it
            self.currentLanguage = saved
        } else {
            // First launch — detect device language, fall back to English
            let supportedCodes = Self.supportedLanguages.map { $0.id }
            let deviceLang = Locale.preferredLanguages.first ?? "en"
            let langCode = String(deviceLang.prefix(2)) // e.g. "ru-US" → "ru"
            self.currentLanguage = supportedCodes.contains(langCode) ? langCode : "en"
            UserDefaults.standard.set(self.currentLanguage, forKey: "app_language")
        }
        loadBundle()
    }

    private func loadBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }

    /// Localize a key using the currently selected language bundle.
    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Localize with format arguments.
    func localized(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, arguments: args)
    }
}

/// Convenience global function
func L(_ key: String) -> String {
    LanguageManager.shared.localized(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = LanguageManager.shared.bundle.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, arguments: args)
}

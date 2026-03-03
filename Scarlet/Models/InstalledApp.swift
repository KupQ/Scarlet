//
//  InstalledApp.swift
//  Scarlet
//
//  Separate store for apps that have been actually installed on device.
//  Independent from imported IPAs — deleting an IPA doesn't remove the
//  installed entry, and vice versa.
//

import Foundation

// MARK: - InstalledApp Model

/// Lightweight record of an app installed on the device.
struct InstalledApp: Identifiable, Codable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let version: String
    let installedDate: Date
    /// Relative icon filename (may or may not still exist on disk).
    let iconFileName: String?

    var iconURL: URL? {
        guard let name = iconFileName else { return nil }
        return ImportedAppsManager.appsDirectory.appendingPathComponent(name)
    }
}

// MARK: - InstalledAppsManager

/// Singleton manager for installed apps. Persists independently from imported IPAs.
class InstalledAppsManager: ObservableObject {
    static let shared = InstalledAppsManager()

    @Published private(set) var apps: [InstalledApp] = []

    private let file: URL = {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("installed_apps.json")
    }()

    private init() { load() }

    // MARK: - Public API

    /// Records a newly installed app from an ImportedApp source.
    func add(from app: ImportedApp) {
        // Avoid duplicates by bundleId
        apps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        let record = InstalledApp(
            id: UUID(),
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            version: app.version,
            installedDate: Date(),
            iconFileName: app.iconFileName
        )
        apps.insert(record, at: 0)
        save()
    }

    /// Removes an installed app entry (does NOT delete the IPA).
    func remove(_ app: InstalledApp) {
        apps.removeAll { $0.id == app.id }
        save()
    }

    /// Sorted by install date, newest first.
    var sorted: [InstalledApp] {
        apps.sorted { $0.installedDate > $1.installedDate }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([InstalledApp].self, from: data) else { return }
        apps = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: file)
    }
}

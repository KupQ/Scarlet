//
//  SignedAppsManager.swift
//  Scarlet
//
//  Manages signed IPA files — saves to Documents/SignedApps/ with metadata.
//

import Foundation
import UIKit

// MARK: - Signed App Model

struct SignedApp: Identifiable, Codable {
    let id: String           // UUID
    let appName: String
    let bundleId: String
    let version: String
    let iconFileName: String? // PNG in SignedApps/Icons/
    let ipaFileName: String   // Random name in SignedApps/
    let signDate: Date
    let fileSize: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: signDate)
    }
}

// MARK: - Signed Apps Manager

class SignedAppsManager: ObservableObject {
    static let shared = SignedAppsManager()

    @Published var signedApps: [SignedApp] = []

    private let signedDir: URL
    private let iconsDir: URL
    private let jsonKey = "signed_apps_json"

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        signedDir = docs.appendingPathComponent("SignedApps")
        iconsDir = signedDir.appendingPathComponent("Icons")
        try? FileManager.default.createDirectory(at: signedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        loadApps()
    }

    // MARK: - Save Signed IPA

    /// Saves a signed IPA to persistent storage and returns the saved SignedApp.
    @discardableResult
    func saveSignedIPA(
        sourceURL: URL,
        appName: String,
        bundleId: String,
        version: String,
        iconURL: URL? = nil
    ) -> SignedApp? {
        let id = UUID().uuidString
        let ipaName = "\(id).ipa"
        let destIPA = signedDir.appendingPathComponent(ipaName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destIPA)
        } catch {
            print("[SignedAppsManager] Failed to save IPA: \(error)")
            return nil
        }

        // Save icon
        var iconName: String? = nil
        if let iconURL = iconURL, let data = try? Data(contentsOf: iconURL) {
            iconName = "\(id).png"
            let destIcon = iconsDir.appendingPathComponent(iconName!)
            try? data.write(to: destIcon)
        }

        // Get file size
        let size = (try? FileManager.default.attributesOfItem(atPath: destIPA.path)[.size] as? Int64) ?? 0

        let app = SignedApp(
            id: id,
            appName: appName,
            bundleId: bundleId,
            version: version,
            iconFileName: iconName,
            ipaFileName: ipaName,
            signDate: Date(),
            fileSize: size
        )

        signedApps.insert(app, at: 0)
        saveApps()
        return app
    }

    // MARK: - Delete

    func removeApp(_ app: SignedApp) {
        let ipaURL = signedDir.appendingPathComponent(app.ipaFileName)
        try? FileManager.default.removeItem(at: ipaURL)
        if let icon = app.iconFileName {
            try? FileManager.default.removeItem(at: iconsDir.appendingPathComponent(icon))
        }
        signedApps.removeAll { $0.id == app.id }
        saveApps()
    }

    // MARK: - URLs

    func ipaURL(for app: SignedApp) -> URL {
        signedDir.appendingPathComponent(app.ipaFileName)
    }

    func iconURL(for app: SignedApp) -> URL? {
        guard let name = app.iconFileName else { return nil }
        return iconsDir.appendingPathComponent(name)
    }

    // MARK: - Cache

    /// Total size of all signed IPAs + icons in bytes.
    var totalCacheSize: Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: signedDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    /// Deletes all signed apps.
    func clearAll() {
        try? FileManager.default.removeItem(at: signedDir)
        try? FileManager.default.createDirectory(at: signedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        signedApps.removeAll()
        saveApps()
    }

    // MARK: - Persistence

    private func loadApps() {
        guard let json = UserDefaults.standard.string(forKey: jsonKey),
              let data = json.data(using: .utf8),
              let apps = try? JSONDecoder().decode([SignedApp].self, from: data) else { return }
        signedApps = apps
    }

    private func saveApps() {
        if let data = try? JSONEncoder().encode(signedApps),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: jsonKey)
        }
    }
}

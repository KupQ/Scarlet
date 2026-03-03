//
//  SigningAssetsScanner.swift
//  Scarlet
//
//  Scans Documents/signing-assets/ for certificate folders.
//  Each subfolder may contain a .p12, .mobileprovision, and .txt
//  (password). Files are detected by extension.
//

import Foundation
import Security

/// Represents a discovered signing asset bundle.
struct SigningAsset: Identifiable {
    let id: String           // Folder name
    let p12URL: URL
    let profileURL: URL?
    let password: String
}

/// Scans the signing-assets folder and auto-imports certs.
enum SigningAssetsScanner {

    // MARK: - Well-known passwords to try before pass.txt

    private static let knownPasswords = [
        "", "1234", "123456", "password", "1", "a]S;dR%*rX\"",
        "test", "cert", "apple", "12345678", "AppleP12.com"
    ]

    // MARK: - Signing-assets directory

    static var assetsDirectory: URL {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("signing-assets")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies bundled signing-assets from the app bundle to Application Support
    /// so they become scannable. Only copies folders that don't already exist.
    static func seedBundledAssets() {
        let fm = FileManager.default
        let bundledDir = Bundle.main.bundleURL.appendingPathComponent("signing-assets")

        guard fm.fileExists(atPath: bundledDir.path) else {
            FileLogger.shared.log("SigningAssets: no bundled signing-assets folder at \(bundledDir.path)")
            return
        }

        guard let folders = try? fm.contentsOfDirectory(
            at: bundledDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let destBase = assetsDirectory

        for folder in folders where folder.hasDirectoryPath {
            let destFolder = destBase.appendingPathComponent(folder.lastPathComponent)
            if fm.fileExists(atPath: destFolder.path) { continue }

            do {
                try fm.copyItem(at: folder, to: destFolder)
                FileLogger.shared.log("SigningAssets: seeded bundled '\(folder.lastPathComponent)'")
            } catch {
                FileLogger.shared.log("SigningAssets: failed to seed '\(folder.lastPathComponent)': \(error)")
            }
        }
    }

    // MARK: - Scan

    /// Scans `Application Support/signing-assets/` and returns discovered assets.
    static func scan() -> [SigningAsset] {
        let fm = FileManager.default
        let base = assetsDirectory

        guard let folders = try? fm.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var assets: [SigningAsset] = []

        for folder in folders where folder.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Detect by extension
            let p12 = files.first { $0.pathExtension.lowercased() == "p12" }
            let profile = files.first { $0.pathExtension.lowercased() == "mobileprovision" }
            let passFile = files.first { $0.pathExtension.lowercased() == "txt" }

            guard let p12URL = p12 else { continue } // P12 is required

            // Resolve password
            let password = resolvePassword(p12URL: p12URL, passFileURL: passFile)

            let asset = SigningAsset(
                id: folder.lastPathComponent,
                p12URL: p12URL,
                profileURL: profile,
                password: password
            )
            assets.append(asset)
            FileLogger.shared.log("SigningAssets: found '\(asset.id)' — p12: \(p12URL.lastPathComponent), profile: \(profile?.lastPathComponent ?? "none"), pass: \(password.isEmpty ? "(empty)" : "***")")
        }

        return assets
    }

    // MARK: - Auto-import first discovered asset

    /// Scans and imports the first valid cert into SigningSettings.
    /// Called on app launch. Only imports if no cert is currently saved.
    @MainActor
    static func autoImportIfNeeded() {
        let settings = SigningSettings.shared
        let log = FileLogger.shared

        log.log("SigningAssets: autoImport check — hasCertificate: \(settings.hasCertificate)")

        // Don't overwrite existing cert
        if settings.hasCertificate { return }

        let assets = scan()
        log.log("SigningAssets: scan found \(assets.count) asset(s)")

        guard let first = assets.first else {
            log.log("SigningAssets: no assets to import")
            return
        }

        log.log("SigningAssets: importing '\(first.id)' with password: \(first.password.isEmpty ? "(empty)" : "***")")
        importAsset(first)
    }

    /// Imports a specific signing asset into the app's signing settings.
    @MainActor
    static func importAsset(_ asset: SigningAsset) {
        let settings = SigningSettings.shared
        let log = FileLogger.shared

        do {
            log.log("SigningAssets: importing p12 from \(asset.p12URL.path)")
            try settings.importCertificate(from: asset.p12URL)
            settings.savedCertPassword = asset.password
            log.log("SigningAssets: cert imported, savedCertName: \(settings.savedCertName ?? "nil")")

            if let profileURL = asset.profileURL {
                log.log("SigningAssets: importing profile from \(profileURL.path)")
                try settings.importProfile(from: profileURL)
                log.log("SigningAssets: profile imported, savedProfileName: \(settings.savedProfileName ?? "nil")")
            }

            // Register in local_imported_certs_json so it shows in cert picker UI
            if let certFilename = settings.savedCertName {
                let newCert = LocalImportedCert(filename: certFilename, password: asset.password)
                let key = "local_imported_certs_json"
                var existing: [LocalImportedCert] = []
                if let json = UserDefaults.standard.string(forKey: key),
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([LocalImportedCert].self, from: data) {
                    existing = decoded
                }
                if !existing.contains(where: { $0.filename == certFilename }) {
                    existing.append(newCert)
                    if let encoded = try? JSONEncoder().encode(existing),
                       let jsonStr = String(data: encoded, encoding: .utf8) {
                        UserDefaults.standard.set(jsonStr, forKey: key)
                        log.log("SigningAssets: registered '\(certFilename)' in local certs list")
                    }
                }
            }

            log.log("SigningAssets: import complete for '\(asset.id)' — hasCert: \(settings.hasCertificate), hasProfile: \(settings.hasProfile)")
        } catch {
            log.log("SigningAssets: import FAILED for '\(asset.id)' — \(error)")
        }
    }

    // MARK: - Password resolution

    /// Tries known passwords first, then reads pass.txt.
    private static func resolvePassword(p12URL: URL, passFileURL: URL?) -> String {
        // Try each known password
        if let p12Data = try? Data(contentsOf: p12URL) {
            for password in knownPasswords {
                let options: [String: Any] = [kSecImportExportPassphrase as String: password]
                var items: CFArray?
                let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
                if status == errSecSuccess {
                    FileLogger.shared.log("SigningAssets: password matched from known list")
                    return password
                }
            }
        }

        // Try password from .txt file
        if let passFileURL,
           let passContent = try? String(contentsOf: passFileURL, encoding: .utf8) {
            let password = passContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !password.isEmpty {
                // Validate it actually works
                if let p12Data = try? Data(contentsOf: p12URL) {
                    let options: [String: Any] = [kSecImportExportPassphrase as String: password]
                    var items: CFArray?
                    let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
                    if status == errSecSuccess {
                        FileLogger.shared.log("SigningAssets: password matched from pass.txt")
                        return password
                    }
                }
                // Return it anyway — user might know better
                FileLogger.shared.log("SigningAssets: using password from pass.txt (unverified)")
                return password
            }
        }

        FileLogger.shared.log("SigningAssets: no matching password found, defaulting to empty")
        return ""
    }

    // MARK: - Repo auto-load from repo.txt

    /// Reads `Documents/signing-assets/repo.txt` and adds each URL
    /// (one per line) to RepoService if not already present.
    static func loadReposFromFile() {
        let repoFile = assetsDirectory.appendingPathComponent("repo.txt")
        guard let content = try? String(contentsOf: repoFile, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }

        guard !lines.isEmpty else { return }

        let existing = RepoService.shared.defaultURLs + RepoService.shared.localURLs
        let newURLs = lines.filter { !existing.contains($0) }

        guard !newURLs.isEmpty else {
            FileLogger.shared.log("SigningAssets: repo.txt — all \(lines.count) repo(s) already added")
            return
        }

        FileLogger.shared.log("SigningAssets: repo.txt — adding \(newURLs.count) new repo(s)")
        Task {
            for url in newURLs {
                await RepoService.shared.addRepo(url: url)
                FileLogger.shared.log("SigningAssets: added repo \(url)")
            }
        }
    }
}

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

    // MARK: - Signing-assets directories

    /// Bundled assets inside the app (read-only)
    static var bundledAssetsDirectory: URL {
        Bundle.main.bundleURL.appendingPathComponent("signing-assets")
    }

    /// Copies bundled signing-assets — NO-OP, assets are read directly from bundle
    static func seedBundledAssets() {
        // Assets are read directly from the bundle, no copy needed
    }

    // MARK: - Scan

    /// Scans the app bundle's signing-assets folder and returns discovered assets.
    static func scan() -> [SigningAsset] {
        let fm = FileManager.default
        let base = bundledAssetsDirectory

        guard fm.fileExists(atPath: base.path),
              let folders = try? fm.contentsOfDirectory(
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
        }

        return assets
    }

    // MARK: - Auto-import first discovered asset

    /// Scans and imports the first valid cert into SigningSettings.
    /// Called on app launch. Only imports if no cert is currently saved.
    @MainActor
    static func autoImportIfNeeded() {
        let settings = SigningSettings.shared


        // Don't overwrite existing cert
        if settings.hasCertificate { return }

        let assets = scan()

        guard let first = assets.first else {
            return
        }

        importAsset(first)
    }

    /// Imports a specific signing asset into the app's signing settings.
    @MainActor
    static func importAsset(_ asset: SigningAsset) {
        let settings = SigningSettings.shared

        do {
            try settings.importCertificate(from: asset.p12URL)
            settings.savedCertPassword = asset.password

            if let profileURL = asset.profileURL {
                try settings.importProfile(from: profileURL)
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
                    }
                }
            }

        } catch {
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
                        return password
                    }
                }
                // Return it anyway — user might know better
                return password
            }
        }

        return ""
    }

    // MARK: - Repo auto-load from repo.txt

    /// Reads `repo.txt` from the app bundle and adds each URL
    /// (one per line) to RepoService if not already present.
    static func loadReposFromFile() {
        // Check app bundle for repo.txt
        let bundleRepoFile = Bundle.main.bundleURL.appendingPathComponent("repo.txt")
        guard let content = try? String(contentsOf: bundleRepoFile, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }

        guard !lines.isEmpty else { return }

        let existing = RepoService.shared.defaultURLs + RepoService.shared.localURLs
        let newURLs = lines.filter { !existing.contains($0) }

        guard !newURLs.isEmpty else {
            return
        }

        Task {
            for url in newURLs {
                await RepoService.shared.addRepo(url: url)
            }
        }
    }
}

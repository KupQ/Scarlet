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
        "test", "cert", "apple", "12345678"
    ]

    // MARK: - Signing-assets directory

    static var assetsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("signing-assets")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Scan

    /// Scans `Documents/signing-assets/` and returns discovered assets.
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
        // Don't overwrite existing cert
        if settings.hasCertificate { return }

        let assets = scan()
        guard let first = assets.first else { return }

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

            FileLogger.shared.log("SigningAssets: imported '\(asset.id)' as active cert")
        } catch {
            FileLogger.shared.log("SigningAssets: import failed for '\(asset.id)' — \(error.localizedDescription)")
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
}

//
//  SigningSettings.swift
//  Scarlet
//
//  Persisted signing configuration backed by UserDefaults.
//  Manages zsign options (bundle ID, version, compression)
//  and stored certificate/profile files.
//

import Foundation
import SwiftUI

// MARK: - Signing Settings

/// Singleton that persists signing preferences with `UserDefaults`.
///
/// Manages both zsign signing options (bundle ID, version, compression)
/// and stored certificate/profile files in the app's Documents directory.
@MainActor
final class SigningSettings: ObservableObject {
    static let shared = SigningSettings()

    // MARK: - zsign Options

    /// Custom bundle identifier (empty = keep original).
    @Published var bundleId: String {
        didSet { UserDefaults.standard.set(bundleId, forKey: "zsign_bundleId") }
    }

    /// Custom display name (empty = keep original).
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "zsign_displayName") }
    }

    /// Custom version (empty = keep original).
    @Published var version: String {
        didSet { UserDefaults.standard.set(version, forKey: "zsign_version") }
    }

    /// Zip compression level: 0 = store, 1–9 = deflate.
    @Published var zipCompression: Int {
        didSet { UserDefaults.standard.set(zipCompression, forKey: "zsign_zipLevel") }
    }

    /// Remove plugins/extensions from the app bundle.
    @Published var removePlugins: Bool {
        didSet { UserDefaults.standard.set(removePlugins, forKey: "zsign_removePlugins") }
    }

    // MARK: - Saved Certificate

    /// File name of the stored certificate in the certs directory.
    @Published var savedCertName: String? {
        didSet { UserDefaults.standard.set(savedCertName, forKey: "cert_name") }
    }

    /// Password for the stored certificate.
    @Published var savedCertPassword: String {
        didSet { UserDefaults.standard.set(savedCertPassword, forKey: "cert_password") }
    }

    /// File name of the stored provisioning profile.
    @Published var savedProfileName: String? {
        didSet { UserDefaults.standard.set(savedProfileName, forKey: "profile_name") }
    }

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard
        self.bundleId          = defaults.string(forKey: "zsign_bundleId") ?? ""
        self.displayName       = defaults.string(forKey: "zsign_displayName") ?? ""
        self.version           = defaults.string(forKey: "zsign_version") ?? ""
        self.zipCompression    = defaults.object(forKey: "zsign_zipLevel") as? Int ?? 0
        self.removePlugins     = defaults.bool(forKey: "zsign_removePlugins")
        self.savedCertName     = defaults.string(forKey: "cert_name")
        self.savedCertPassword = defaults.string(forKey: "cert_password") ?? ""
        self.savedProfileName  = defaults.string(forKey: "profile_name")
    }

    // MARK: - Certificate Management

    /// Directory where certificates and profiles are stored.
    var certsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Certificates")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Absolute URL for the saved certificate, or `nil` if missing.
    var savedCertURL: URL? {
        guard let name = savedCertName else { return nil }
        let url = certsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Absolute URL for the saved provisioning profile, or `nil` if missing.
    var savedProfileURL: URL? {
        guard let name = savedProfileName else { return nil }
        let url = certsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Imports a certificate file into the app's storage.
    /// - Parameter url: Source URL of the `.p12` file.
    func importCertificate(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let dest = certsDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        savedCertName = url.lastPathComponent
    }

    /// Imports a provisioning profile into the app's storage.
    /// - Parameter url: Source URL of the `.mobileprovision` file.
    func importProfile(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let dest = certsDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        savedProfileName = url.lastPathComponent
    }

    /// Removes the saved certificate and clears its password.
    func removeCertificate() {
        if let url = savedCertURL {
            try? FileManager.default.removeItem(at: url)
        }
        savedCertName = nil
        savedCertPassword = ""
    }

    /// Removes the saved provisioning profile.
    func removeProfile() {
        if let url = savedProfileURL {
            try? FileManager.default.removeItem(at: url)
        }
        savedProfileName = nil
    }

    // MARK: - Convenience

    /// Whether a certificate is currently saved.
    var hasCertificate: Bool { savedCertURL != nil }

    /// Whether a provisioning profile is currently saved.
    var hasProfile: Bool { savedProfileURL != nil }
}

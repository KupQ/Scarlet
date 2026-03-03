//
//  ImportedApp.swift
//  Scarlet
//
//  Data model for imported IPA files and singleton manager
//  that handles storage, import, deletion, and signing state.
//

import Foundation
import SwiftUI

// MARK: - ImportedApp Model

/// Represents an imported IPA file with its parsed metadata and signing state.
struct ImportedApp: Identifiable, Codable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let version: String
    let fileName: String
    let fileSize: Int64
    let importDate: Date

    /// Relative path to the icon PNG inside `Documents/ImportedApps/`.
    let iconFileName: String?

    /// Relative path to the IPA file inside `Documents/ImportedApps/`.
    let ipaFileName: String

    /// Whether this app has been successfully signed.
    var isSigned: Bool

    /// Timestamp of when the app was signed (used for sorting).
    var signedDate: Date?

    /// Whether this app was actually installed on the device.
    var isInstalled: Bool

    /// Timestamp of when the app was installed.
    var installedDate: Date?

    // MARK: Backward-Compatible Decoder

    /// Custom decoder that provides default values for fields added after
    /// the initial release, ensuring existing stored JSON remains valid.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id              = try container.decode(UUID.self,    forKey: .id)
        appName         = try container.decode(String.self,  forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        version         = try container.decode(String.self,  forKey: .version)
        fileName        = try container.decode(String.self,  forKey: .fileName)
        fileSize        = try container.decode(Int64.self,   forKey: .fileSize)
        importDate      = try container.decode(Date.self,    forKey: .importDate)
        iconFileName    = try container.decodeIfPresent(String.self, forKey: .iconFileName)
        ipaFileName     = try container.decode(String.self,  forKey: .ipaFileName)
        isSigned        = try container.decodeIfPresent(Bool.self,   forKey: .isSigned) ?? false
        signedDate      = try container.decodeIfPresent(Date.self,   forKey: .signedDate)
        isInstalled     = try container.decodeIfPresent(Bool.self,   forKey: .isInstalled) ?? false
        installedDate   = try container.decodeIfPresent(Date.self,   forKey: .installedDate)
    }

    // MARK: Memberwise Initializer

    init(
        id: UUID,
        appName: String,
        bundleIdentifier: String,
        version: String,
        fileName: String,
        fileSize: Int64,
        importDate: Date,
        iconFileName: String?,
        ipaFileName: String,
        isSigned: Bool = false,
        signedDate: Date? = nil,
        isInstalled: Bool = false,
        installedDate: Date? = nil
    ) {
        self.id              = id
        self.appName         = appName
        self.bundleIdentifier = bundleIdentifier
        self.version         = version
        self.fileName        = fileName
        self.fileSize        = fileSize
        self.importDate      = importDate
        self.iconFileName    = iconFileName
        self.ipaFileName     = ipaFileName
        self.isSigned        = isSigned
        self.signedDate      = signedDate
        self.isInstalled     = isInstalled
        self.installedDate   = installedDate
    }

    // MARK: Computed Properties

    /// Human-readable file size string (e.g., "12.4 MB").
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Absolute URL for the app icon, or `nil` if no icon was extracted.
    var iconURL: URL? {
        guard let name = iconFileName else { return nil }
        return ImportedAppsManager.appsDirectory.appendingPathComponent(name)
    }

    /// Absolute URL for the IPA file in local storage.
    var ipaURL: URL {
        ImportedAppsManager.appsDirectory.appendingPathComponent(ipaFileName)
    }
}

// MARK: - ImportedAppsManager

/// Singleton that manages the library of imported IPA files.
///
/// Handles importing, deleting, persisting, and sorting apps.
/// Data is stored as JSON in `Documents/ImportedApps/metadata.json`.
@MainActor
final class ImportedAppsManager: ObservableObject {
    static let shared = ImportedAppsManager()

    // MARK: Published State

    /// All imported apps in the library.
    @Published var apps: [ImportedApp] = []

    /// Whether an import operation is currently in progress.
    @Published var isImporting = false

    // MARK: Storage

    /// Root directory for all imported IPA files and icons.
    static let appsDirectory: URL = {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ImportedApps")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let metadataFile: URL

    private init() {
        metadataFile = Self.appsDirectory.appendingPathComponent("metadata.json")
        loadApps()
    }

    // MARK: - Import

    /// Imports an IPA file: copies it, parses metadata, extracts its icon,
    /// and adds it to the library.
    /// - Parameter url: The source URL of the IPA file to import.
    /// Name of the file currently being imported.
    @Published var importingFileName: String = ""

    func importIPA(from url: URL) {
        importingFileName = url.lastPathComponent
        isImporting = true

        let log = FileLogger.shared
        log.log("[IMP-1] importIPA called, url=\(url.path) thread=\(Thread.isMainThread ? "main" : "bg")")
        log.log("[IMP-2] file exists: \(FileManager.default.fileExists(atPath: url.path))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                log.log("[IMP-3] self is nil, aborting")
                return
            }

            log.log("[IMP-3] background thread started")

            let fm = FileManager.default
            let fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            log.log("[IMP-4] fileSize=\(fileSize)")

            // Try to parse metadata; fall back to basic info if parsing fails
            log.log("[IMP-5] starting parse...")
            let metadata: IPAMetadata
            if let parsed = IPAParser.parse(ipaURL: url) {
                metadata = parsed
                log.log("[IMP-6] parse OK: \(parsed.appName) v\(parsed.version)")
            } else {
                log.log("[IMP-6] parse FAILED, using basic metadata")
                let name = url.deletingPathExtension().lastPathComponent
                metadata = IPAMetadata(
                    appName: name,
                    bundleIdentifier: name,
                    version: "1.0",
                    iconData: nil,
                    fileSize: fileSize,
                    fileName: url.lastPathComponent
                )
            }

            let appId = UUID()
            let ipaName = "\(appId.uuidString).ipa"
            let iconName = metadata.iconData != nil ? "\(appId.uuidString).png" : nil

            let accessing = url.startAccessingSecurityScopedResource()
            let destIPA = Self.appsDirectory.appendingPathComponent(ipaName)
            log.log("[IMP-7] copying to \(destIPA.lastPathComponent)")
            do {
                try fm.copyItem(at: url, to: destIPA)
                log.log("[IMP-8] copy OK")
            } catch {
                log.log("[IMP-8] ERROR copy: \(error)")
                if accessing { url.stopAccessingSecurityScopedResource() }
                DispatchQueue.main.async { self.isImporting = false }
                return
            }
            if accessing { url.stopAccessingSecurityScopedResource() }

            if let iconData = metadata.iconData, let iconName {
                let destIcon = Self.appsDirectory.appendingPathComponent(iconName)
                try? iconData.write(to: destIcon)
                log.log("[IMP-9] icon saved")
            }

            let app = ImportedApp(
                id: appId,
                appName: metadata.appName,
                bundleIdentifier: metadata.bundleIdentifier,
                version: metadata.version,
                fileName: metadata.fileName,
                fileSize: metadata.fileSize,
                importDate: Date(),
                iconFileName: iconName,
                ipaFileName: ipaName
            )

            DispatchQueue.main.async {
                self.apps.insert(app, at: 0)
                self.saveApps()
                self.isImporting = false
                log.log("[IMP-10] import complete: \(metadata.appName)")
            }
        }
    }

    // MARK: - Delete

    /// Removes an imported app and deletes its files from storage.
    /// - Parameter app: The app to remove.
    func removeApp(_ app: ImportedApp) {
        try? FileManager.default.removeItem(at: app.ipaURL)
        if let iconURL = app.iconURL {
            try? FileManager.default.removeItem(at: iconURL)
        }
        apps.removeAll { $0.id == app.id }
        saveApps()
    }

    // MARK: - Signing

    /// Marks an app as signed and records the signing date.
    /// - Parameter app: The app that was signed.
    func markAsSigned(_ app: ImportedApp) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx].isSigned = true
        apps[idx].signedDate = Date()
        saveApps()
    }

    /// Marks an app as installed on the device.
    func markAsInstalled(_ app: ImportedApp) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx].isInstalled = true
        apps[idx].installedDate = Date()
        saveApps()
    }

    /// Removes only the installed flag (keeps the IPA for re-signing).
    func unmarkInstalled(_ app: ImportedApp) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx].isInstalled = false
        apps[idx].installedDate = nil
        saveApps()
    }

    // MARK: - Sorting

    /// Apps sorted with signed apps first (newest signed on top),
    /// then unsigned apps (newest import on top).
    var sortedApps: [ImportedApp] {
        let signed = apps.filter(\.isSigned).sorted {
            ($0.signedDate ?? .distantPast) > ($1.signedDate ?? .distantPast)
        }
        let unsigned = apps.filter { !$0.isSigned }.sorted {
            $0.importDate > $1.importDate
        }
        return signed + unsigned
    }

    // MARK: - Cache

    /// Total storage used by imported apps (IPAs + icons).
    var totalCacheSize: Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: Self.appsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    /// Deletes all imported apps and their files.
    func clearAll() {
        try? FileManager.default.removeItem(at: Self.appsDirectory)
        try? FileManager.default.createDirectory(at: Self.appsDirectory, withIntermediateDirectories: true)
        apps.removeAll()
        saveApps()
    }

    // MARK: - Persistence

    private func loadApps() {
        guard let data = try? Data(contentsOf: metadataFile),
              let decoded = try? JSONDecoder().decode([ImportedApp].self, from: data) else {
            return
        }
        // Filter out apps whose IPA files were deleted externally
        apps = decoded.filter { FileManager.default.fileExists(atPath: $0.ipaURL.path) }
    }

    private func saveApps() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: metadataFile)
    }
}

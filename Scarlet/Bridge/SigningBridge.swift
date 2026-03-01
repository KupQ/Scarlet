//
//  SigningBridge.swift
//  Scarlet
//
//  Bridge layer between Swift and the native zsign C/C++ engine.
//  Orchestrates the three-step signing pipeline:
//  ipa_extract → zsign (folder) → ipa_archive.
//

import Foundation

// MARK: - Signing Bridge

/// Bridges Swift code to the native zsign C/C++ signing engine.
///
/// The signing pipeline consists of three steps:
/// 1. **Extract** — Decompress the IPA to a temp directory
/// 2. **Sign** — Run zsign against the `.app` folder
/// 3. **Archive** — Recompress with user-specified compression level
struct SigningBridge {

    // MARK: - Error Types

    /// Errors that can occur during the signing pipeline.
    enum SigningError: LocalizedError {
        case noIPA
        case noCertificate
        case extractionFailed(String)
        case signingFailed(String)
        case archiveFailed(String)

        var errorDescription: String? {
            switch self {
            case .noIPA:                     return "No IPA file specified"
            case .noCertificate:             return "No certificate file specified"
            case .extractionFailed(let msg): return "Extraction failed: \(msg)"
            case .signingFailed(let msg):    return "Signing failed: \(msg)"
            case .archiveFailed(let msg):    return "Archiving failed: \(msg)"
            }
        }
    }

    // MARK: - Sign IPA

    /// Signs an IPA file using the three-step pipeline.
    ///
    /// - Parameters:
    ///   - ipaURL: Path to the input IPA file.
    ///   - certURL: Path to the `.p12` certificate file.
    ///   - certPassword: Password for the certificate.
    ///   - profileURL: Optional path to the `.mobileprovision` file.
    ///   - bundleId: Optional override for the bundle identifier.
    ///   - displayName: Optional override for the display name.
    ///   - compressionLevel: Zip compression level (0 = store, 1–9 = deflate).
    /// - Returns: A `Result` containing the output IPA URL on success.
    static func signIPA(
        ipaURL: URL,
        certURL: URL,
        certPassword: String,
        profileURL: URL?,
        bundleId: String? = nil,
        displayName: String? = nil,
        compressionLevel: Int = 0
    ) -> Result<URL, SigningError> {

        let log = FileLogger.shared
        log.log("=== Starting signing (3-step) ===")
        log.log("IPA: \(ipaURL.lastPathComponent)")
        log.log("Cert: \(certURL.lastPathComponent)")
        log.log("Compression: \(compressionLevel)")

        // Validate inputs
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            log.log("ERROR: IPA file not found")
            return .failure(.noIPA)
        }
        guard FileManager.default.fileExists(atPath: certURL.path) else {
            log.log("ERROR: Certificate not found")
            return .failure(.noCertificate)
        }

        // Create temp working directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scarlet_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let extractDir = tempDir.appendingPathComponent("extracted").path

        // Step 1: Extract IPA
        log.log("Step 1: Extracting IPA...")
        let extractResult = ipa_extract(ipaURL.path, extractDir)
        log.log("Extract result: \(extractResult)")

        if extractResult != 0 {
            return .failure(.extractionFailed("ipa_extract returned \(extractResult)"))
        }

        // Locate the .app folder inside extracted/Payload/
        let payloadDir = "\(extractDir)/Payload"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: payloadDir),
              let appFolder = contents.first(where: { $0.hasSuffix(".app") }) else {
            log.log("ERROR: No .app found in Payload")
            return .failure(.signingFailed("No .app found in Payload"))
        }

        let appPath = "\(payloadDir)/\(appFolder)"
        log.log("App folder: \(appFolder)")

        // Step 2: Sign the .app folder with zsign
        log.log("Step 2: Signing...")
        let signResult = zsign(
            appPath,
            certURL.path,
            certURL.path,        // pKeyFile — same as cert for P12
            profileURL?.path,
            certPassword,
            bundleId,
            displayName
        )
        log.log("zsign returned: \(signResult)")

        if signResult != 0 {
            return .failure(.signingFailed("zsign returned error code \(signResult)"))
        }

        // Step 3: Re-archive with user's compression level
        let outputPath = tempDir.appendingPathComponent("signed.ipa").path
        log.log("Step 3: Archiving (compression: \(compressionLevel))...")
        let archiveResult = ipa_archive(extractDir, outputPath,
                                        Int32(compressionLevel))
        log.log("Archive result: \(archiveResult)")

        if archiveResult != 0 {
            return .failure(.archiveFailed("ipa_archive returned \(archiveResult)"))
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            return .failure(.archiveFailed("Output IPA not found"))
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        log.log("=== Signing complete: \(outputURL.lastPathComponent) ===")
        return .success(outputURL)
    }
}

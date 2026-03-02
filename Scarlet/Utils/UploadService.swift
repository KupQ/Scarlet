//
//  UploadService.swift
//  Scarlet
//
//  Local HTTPS server for OTA app installation using backloop.dev certs.
//  *.backloop.dev resolves to 127.0.0.1 with a valid Let's Encrypt SSL cert.
//  This allows itms-services:// to work without uploading the IPA anywhere.
//

import Foundation
import Network
import UIKit
import Security

// MARK: - Install Status

/// Tracks the OTA installation progress through each phase.
enum InstallStatus: Equatable {
    case idle
    case serverReady
    case sendingManifest
    case sendingPayload
    case installing(progress: Double)
    case completed
    case failed(String)
}

// MARK: - Local HTTPS IPA Server

/// HTTPS server that serves the signed IPA locally using backloop.dev certificates.
///
/// Flow:
/// 1. Load backloop.dev P12 identity → create TLS-enabled NWListener
/// 2. Serve manifest plist at `/<uuid>.plist`
/// 3. Serve IPA at `/<uuid>.ipa`
/// 4. `UIApplication.shared.open(itms-services://...)` triggers install directly
/// 5. Track install progress via LSApplicationWorkspace
///
/// No Safari, no uploads, no external servers.
final class LocalIPAServer: ObservableObject {
    private var listener: NWListener?
    private var ipaURL: URL?
    private var iconData: Data?
    private var manifestData: Data?
    private let uuid = UUID().uuidString
    private(set) var port: UInt16 = 0

    /// The backloop.dev hostname for this server.
    private let hostname = "scarlet.backloop.dev"

    /// Current installation status, observed by the UI.
    @Published var status: InstallStatus = .idle

    /// Whether the server is currently running.
    var isRunning: Bool { listener != nil }

    /// The itms-services:// URL to trigger installation directly.
    var iTunesLink: URL? {
        guard port > 0 else { return nil }
        let plistURL = "https://\(hostname):\(port)/\(uuid).plist"
        return URL(string: "itms-services://?action=download-manifest&url=\(plistURL)")
    }

    // MARK: - Start

    /// Starts the local HTTPS server with backloop.dev TLS certificates.
    func start(
        servingIPA ipaURL: URL,
        bundleId: String,
        version: String,
        appName: String,
        iconData: Data? = nil
    ) throws {
        self.ipaURL = ipaURL
        self.iconData = iconData

        // Build manifest plist
        buildManifest(bundleId: bundleId, version: version, appName: appName)

        // Load TLS identity from bundled P12
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions
        // Explicitly set TLS 1.2+ for iOS 16.x compatibility
        sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(secOptions, .TLSv13)
        if let identity = loadIdentity() {
            sec_protocol_options_set_local_identity(secOptions, identity)
        } else {
            FileLogger.shared.log("WARNING: Could not load TLS identity, falling back to plain HTTP")
        }

        let params = NWParameters(tls: tlsOptions)
        let listener = try NWListener(using: params)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let assignedPort = listener.port?.rawValue {
                    self.port = assignedPort
                    FileLogger.shared.log("HTTPS server ready on port \(assignedPort)")
                    DispatchQueue.main.async {
                        self.status = .serverReady
                    }
                }
            case .failed(let error):
                FileLogger.shared.log("Server failed: \(error)")
                DispatchQueue.main.async {
                    self.status = .failed(error.localizedDescription)
                }
                self.stop()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    // MARK: - Stop

    /// Stops the server and releases resources.
    func stop() {
        listener?.cancel()
        listener = nil
        ipaURL = nil
        iconData = nil
        manifestData = nil
        port = 0
        status = .idle
        FileLogger.shared.log("Server stopped")
    }

    // MARK: - TLS Identity

    /// Loads the backloop.dev PKCS12 identity from the app bundle.
    private func loadIdentity() -> sec_identity_t? {
        guard let p12URL = Bundle.main.url(forResource: "server", withExtension: "p12"),
              let p12Data = try? Data(contentsOf: p12URL) else {
            FileLogger.shared.log("ERROR: server.p12 not found in bundle")
            return nil
        }

        let options: [String: Any] = [kSecImportExportPassphrase as String: "backloop"]
        var items: CFArray?

        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else {
            FileLogger.shared.log("ERROR: Failed to import P12 (status: \(status))")
            return nil
        }

        // swiftlint:disable:next force_cast
        let secIdentity = identity as! SecIdentity
        return sec_identity_create(secIdentity)
    }

    // MARK: - Build Manifest

    /// Builds the OTA manifest plist pointing to the local IPA endpoint.
    private func buildManifest(bundleId: String, version: String, appName: String) {
        let ipaEndpoint = "https://\(hostname):\(port == 0 ? 0 : port)/\(uuid).ipa"
        let iconEndpoint = "https://\(hostname):\(port == 0 ? 0 : port)/icon.png"

        var assets: [[String: String]] = [
            ["kind": "software-package", "url": ipaEndpoint]
        ]
        if iconData != nil {
            assets.append(["kind": "display-image", "needs-shine": "false", "url": iconEndpoint])
            assets.append(["kind": "full-size-image", "needs-shine": "false", "url": iconEndpoint])
        }

        let manifest: [String: Any] = [
            "items": [[
                "assets": assets,
                "metadata": [
                    "bundle-identifier": bundleId,
                    "bundle-version": version,
                    "kind": "software",
                    "title": appName
                ]
            ]]
        ]

        manifestData = try? PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: .zero
        )
    }

    /// Rebuilds manifest with the actual port once known (called externally).
    func rebuildManifest(bundleId: String, version: String, appName: String) {
        let ipaEndpoint = "https://\(hostname):\(port)/\(uuid).ipa"
        let iconEndpoint = "https://\(hostname):\(port)/icon.png"

        var assets: [[String: String]] = [
            ["kind": "software-package", "url": ipaEndpoint]
        ]
        if iconData != nil {
            assets.append(["kind": "display-image", "needs-shine": "false", "url": iconEndpoint])
            assets.append(["kind": "full-size-image", "needs-shine": "false", "url": iconEndpoint])
        }

        let manifest: [String: Any] = [
            "items": [[
                "assets": assets,
                "metadata": [
                    "bundle-identifier": bundleId,
                    "bundle-version": version,
                    "kind": "software",
                    "title": appName
                ]
            ]]
        ]

        manifestData = try? PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: .zero
        )
    }

    // MARK: - Connection Handler

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let log = FileLogger.shared

            if request.contains("GET /\(self.uuid).ipa") {
                log.log("iOS requesting IPA — streaming payload")
                DispatchQueue.main.async { self.status = .sendingPayload }
                self.streamIPA(connection: connection)
                return
            } else if request.contains("GET /\(self.uuid).plist") {
                log.log("iOS requesting manifest plist")
                DispatchQueue.main.async { self.status = .sendingManifest }
                let response = self.buildManifestResponse()
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if request.contains("GET /icon.png") {
                log.log("iOS requesting app icon")
                let response = self.buildIconResponse()
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                connection.send(content: self.build404Response(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: - Stream IPA (for 4GB+ files)

    private func streamIPA(connection: NWConnection) {
        guard let ipaURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: ipaURL.path),
              let fileSize = attrs[.size] as? Int else {
            connection.send(content: build404Response(), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/octet-stream",
            "Content-Length: \(fileSize)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else { connection.cancel(); return }
            self?.streamFileChunks(connection: connection, fileURL: ipaURL, offset: 0, totalSize: fileSize)
        })
    }

    private func streamFileChunks(connection: NWConnection, fileURL: URL, offset: Int, totalSize: Int) {
        let chunkSize = 512 * 1024
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            connection.cancel()
            return
        }

        handle.seek(toFileOffset: UInt64(offset))
        let data = handle.readData(ofLength: min(chunkSize, totalSize - offset))
        handle.closeFile()

        guard !data.isEmpty else {
            FileLogger.shared.log("IPA streaming complete (\(totalSize) bytes)")
            DispatchQueue.main.async { self.status = .installing(progress: 0) }
            connection.send(content: nil, contentContext: .finalMessage, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let newOffset = offset + data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error == nil else { connection.cancel(); return }
            self?.streamFileChunks(connection: connection, fileURL: fileURL, offset: newOffset, totalSize: totalSize)
        })
    }

    // MARK: - HTTP Responses

    private func buildManifestResponse() -> Data {
        guard let manifestData else { return build404Response() }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/xml",
            "Content-Length: \(manifestData.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(manifestData)
        return response
    }

    private func buildIconResponse() -> Data {
        guard let iconData else { return build404Response() }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: image/png",
            "Content-Length: \(iconData.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(iconData)
        return response
    }

    private func build404Response() -> Data {
        let body = "Not Found"
        let header = [
            "HTTP/1.1 404 Not Found",
            "Content-Type: text/plain",
            "Content-Length: \(body.count)",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(Data(body.utf8))
        return response
    }
}

// MARK: - Install Progress Polling

/// Polls iOS for install progress using LSApplicationWorkspace (private API).
enum InstallProgressPoller {

    /// Returns the current install progress for a bundle ID (0.0–1.0).
    static func progress(for bundleId: String) -> Double? {
        // LSApplicationWorkspace
        guard let clsData = Data(base64Encoded: "TFNBcHBsaWNhdGlvbldvcmtzcGFjZQ=="),
              let cls = String(data: clsData, encoding: .utf8),
              let defData = Data(base64Encoded: "ZGVmYXVsdFdvcmtzcGFjZQ=="),
              let defSel = String(data: defData, encoding: .utf8),
              // installProgressForBundleID:makeSynchronous:
              let progData = Data(base64Encoded: "aW5zdGFsbFByb2dyZXNzRm9yQnVuZGxlSUQ6bWFrZVN5bmNocm9ub3VzOg=="),
              let progSel = String(data: progData, encoding: .utf8)
        else { return nil }

        guard let workspaceClass = NSClassFromString(cls) as? NSObject.Type,
              let workspace = workspaceClass.perform(NSSelectorFromString(defSel))?.takeUnretainedValue()
        else { return nil }

        let result = workspace.perform(
            NSSelectorFromString(progSel),
            with: bundleId,
            with: true
        )?.takeUnretainedValue()

        if let progress = result as? Progress {
            return progress.fractionCompleted
        }

        return nil
    }

    /// Opens an installed app by its bundle ID.
    static func openApp(bundleId: String) {
        // LSApplicationWorkspace → openApplicationWithBundleID:
        guard let clsData = Data(base64Encoded: "TFNBcHBsaWNhdGlvbldvcmtzcGFjZQ=="),
              let cls = String(data: clsData, encoding: .utf8),
              let defData = Data(base64Encoded: "ZGVmYXVsdFdvcmtzcGFjZQ=="),
              let defSel = String(data: defData, encoding: .utf8),
              let openData = Data(base64Encoded: "b3BlbkFwcGxpY2F0aW9uV2l0aEJ1bmRsZUlEOg=="),
              let openSel = String(data: openData, encoding: .utf8)
        else { return }

        guard let workspaceClass = NSClassFromString(cls) as? NSObject.Type,
              let workspace = workspaceClass.perform(NSSelectorFromString(defSel))?.takeUnretainedValue()
        else { return }

        _ = workspace.perform(NSSelectorFromString(openSel), with: bundleId)
    }
}

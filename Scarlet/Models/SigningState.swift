//
//  SigningState.swift
//  Scarlet
//
//  Observable state machine for the IPA signing workflow.
//  Tracks selected files, signing phase, and triggers the signing bridge.
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Signing Phase

/// Represents each stage of the signing workflow.
enum SigningPhase: Equatable {
    case idle
    case selectingFiles
    case readyToSign
    case signing
    case success(outputURL: URL)
    case failure(message: String)
}

// MARK: - Selected File

/// Represents a user-selected file with basic metadata.
struct SelectedFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64

    /// Human-readable file size string.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Signing State

/// Observable state for the signing workflow.
///
/// Manages file selection, readiness checks, and dispatches
/// the actual signing operation via ``SigningBridge``.
@MainActor
final class SigningState: ObservableObject {

    // MARK: Published Properties

    @Published var phase: SigningPhase = .idle
    @Published var ipaFile: SelectedFile?
    @Published var certFile: SelectedFile?
    @Published var profileFile: SelectedFile?
    @Published var certPassword: String = ""

    // MARK: OTA Install

    /// Remote install URL generated after OTA upload completes.
    @Published var installURL: URL?

    /// Current install status — observed directly by the UI.
    @Published var installStatus: InstallStatus = .idle

    /// Whether OTA upload is in progress.
    @Published var isUploading = false

    // MARK: Readiness Checks

    /// Whether all required files are selected and ready to sign.
    var isReadyToSign: Bool {
        ipaFile != nil && hasCert && hasPassword
    }

    /// Certificate is available (from picker OR from saved settings).
    var hasCert: Bool {
        certFile != nil || SigningSettings.shared.hasCertificate
    }

    /// Password is available (from text field OR from saved settings).
    var hasPassword: Bool {
        !certPassword.isEmpty || !SigningSettings.shared.savedCertPassword.isEmpty
    }

    // MARK: - Actions

    /// Resets the state for a new signing session.
    func reset() {
        phase = .idle
        ipaFile = nil
        certFile = nil
        profileFile = nil
        certPassword = ""
        installURL = nil
        installStatus = .idle
        isUploading = false
    }

    /// Executes the signing operation on a background thread.
    ///
    /// Uses the selected IPA file along with either the picker-selected
    /// or saved certificate, password, and provisioning profile.
    func startSigning() {
        guard let ipa = ipaFile else { return }
        phase = .signing

        let settings = SigningSettings.shared

        // Resolve certificate URL (picker takes priority over saved)
        let certURL = certFile?.url ?? settings.savedCertURL
        guard let certURL else {
            phase = .failure(message: "No certificate available")
            return
        }

        // Resolve password (picker field takes priority over saved)
        let password = !certPassword.isEmpty ? certPassword : settings.savedCertPassword

        // Resolve provisioning profile (picker takes priority over saved)
        let profileURL = profileFile?.url ?? settings.savedProfileURL

        // zsign options from settings
        let bundleId = settings.bundleId.isEmpty ? nil : settings.bundleId
        let displayName = settings.displayName.isEmpty ? nil : settings.displayName
        let compressionLevel = settings.zipCompression

        Task.detached { [weak self] in
            // Request extra background execution time so signing
            // completes even if the user switches away.
            var bgTaskId: UIBackgroundTaskIdentifier = .invalid
            bgTaskId = await UIApplication.shared.beginBackgroundTask(withName: "Signing") {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }

            let result = SigningBridge.signIPA(
                ipaURL: ipa.url,
                certURL: certURL,
                certPassword: password,
                profileURL: profileURL,
                bundleId: bundleId,
                displayName: displayName,
                compressionLevel: compressionLevel
            )

            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let outputURL):
                    self.phase = .success(outputURL: outputURL)
                case .failure(let error):
                    self.phase = .failure(message: error.localizedDescription)
                }
            }

            if bgTaskId != .invalid {
                await UIApplication.shared.endBackgroundTask(bgTaskId)
            }
        }
    }

    // MARK: - OTA Install (Local HTTPS Server)

    /// The local HTTPS server that serves the signed IPA.
    private var localServer: LocalIPAServer?

    /// Combine subscription for forwarding server status.
    private var statusCancellable: AnyCancellable?

    /// The bundle ID of the app being installed (for progress tracking).
    private(set) var installingBundleId: String = ""

    /// Install progress polling task.
    private var progressTask: Task<Void, Never>?

    /// Starts a local HTTPS server and triggers OTA installation.
    ///
    /// Uses backloop.dev certs for TLS, then calls
    /// `UIApplication.shared.open(itms-services://...)` directly.
    func prepareInstall(app: ImportedApp, outputURL: URL) {
        isUploading = true
        installURL = nil

        let log = FileLogger.shared
        log.log("Preparing local OTA install...")

        let settings = SigningSettings.shared
        let bundleId = settings.bundleId.isEmpty ? app.bundleIdentifier : settings.bundleId
        let version = settings.version.isEmpty ? app.version : settings.version
        let appName = settings.displayName.isEmpty ? app.appName : settings.displayName
        self.installingBundleId = bundleId

        // Load app icon for OTA manifest
        var appIconData: Data? = nil
        if let iconURL = app.iconURL {
            appIconData = try? Data(contentsOf: iconURL)
        }

        let server = LocalIPAServer()
        do {
            try server.start(
                servingIPA: outputURL,
                bundleId: bundleId,
                version: version,
                appName: appName,
                iconData: appIconData
            )
            self.localServer = server

            // Forward server status changes to our @Published installStatus
            self.statusCancellable = server.$status
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newStatus in
                    self?.installStatus = newStatus
                    // Auto-start progress polling when payload is sent
                    if case .installing = newStatus {
                        self?.startProgressPolling(bundleId: bundleId)
                    }
                }
        } catch {
            log.log("ERROR: Failed to start local server: \(error)")
            isUploading = false
            return
        }

        // Poll for server readiness, then trigger install
        pollForServerReady(server: server, bundleId: bundleId, version: version, appName: appName, attempts: 0)
    }

    private func pollForServerReady(server: LocalIPAServer, bundleId: String, version: String, appName: String, attempts: Int) {
        if server.port > 0 {
            // Rebuild manifest with actual port
            server.rebuildManifest(bundleId: bundleId, version: version, appName: appName)

            if let url = server.iTunesLink {
                installURL = url
                isUploading = false
                FileLogger.shared.log("HTTPS ready, triggering install")

                // Trigger install directly — no Safari needed!
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
            return
        }

        if attempts > 20 {
            FileLogger.shared.log("ERROR: Server port not assigned after 10s")
            isUploading = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollForServerReady(server: server, bundleId: bundleId, version: version, appName: appName, attempts: attempts + 1)
        }
    }

    /// Starts polling iOS for install progress after the IPA is sent.
    func startProgressPolling(bundleId: String) {
        guard progressTask == nil else { return }

        progressTask = Task.detached(priority: .background) { [weak self] in
            var hasStarted = false

            while !Task.isCancelled {
                let raw = InstallProgressPoller.progress(for: bundleId) ?? 0.0

                if raw > 0 { hasStarted = true }

                let normalized = hasStarted ? min(1.0, max(0.0, (raw - 0.6) / 0.3)) : 0.0

                await MainActor.run {
                    self?.installStatus = .installing(progress: normalized)
                }

                // Install complete: progress went back to 0 after starting
                if hasStarted && raw == 0 {
                    await MainActor.run {
                        self?.installStatus = .completed
                    }
                    break
                }

                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }

    /// Stops the local server and progress polling.
    func stopLocalServer() {
        progressTask?.cancel()
        progressTask = nil
        statusCancellable?.cancel()
        statusCancellable = nil
        localServer?.stop()
        localServer = nil
    }

    /// Full cancel — stops server, resets all state.
    func cancelAll() {
        stopLocalServer()
        reset()
    }

    /// Resets install status when stuck on sendingManifest (user cancelled iOS dialog).
    func resetStuckInstall() {
        installStatus = .serverReady
        isUploading = false
    }
}

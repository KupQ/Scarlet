//
//  CertificatesView.swift
//  Scarlet
//
//  Displays certificates fetched from the API for the current device.
//  Users can select a certificate to use for signing, or import their own.
//

import SwiftUI

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared
    @ObservedObject private var settings = SigningSettings.shared

    // Import flow state
    @State private var importStep: ImportStep = .idle
    @State private var importedP12URL: URL?
    @State private var importedP12Name: String = ""
    @State private var importPassword: String = ""
    @State private var passwordError: String?
    @State private var showFilePicker = false
    @State private var filePickerType: FilePickerType = .p12

    enum ImportStep { case idle, pickProfile, enterPassword }
    enum FilePickerType { case p12, profile }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Certificates")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        if let udid = certService.deviceUDID {
                            Text(udid)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    // Import button
                    Button {
                        filePickerType = .p12
                        showFilePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

                // Error
                if let error = certService.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.scarletRed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.scarletRed.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Content
                ScrollView(showsIndicators: false) {
                    if certService.isLoading && certService.certificates.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(.scarletRed)
                                .scaleEffect(1.1)
                            Text("Loading...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else if certService.certificates.isEmpty {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.scarletRed.opacity(0.1))
                                    .frame(width: 70, height: 70)
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 28))
                                    .foregroundColor(.scarletRed.opacity(0.6))
                            }
                            Text("No Certificates")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Import your own using the\n+ button above.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.25))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(certService.certificates) { cert in
                                let inUse = settings.savedCertName == "\(cert.id).p12"
                                CertCard(
                                    cert: cert,
                                    isInUse: inUse,
                                    onUse: {
                                        certService.useCertificate(cert)
                                        settings.objectWillChange.send()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task {
            await certService.fetchCertificates()
        }
        .sheet(isPresented: $showFilePicker) {
            if filePickerType == .p12 {
                DocumentPicker(contentTypes: [.p12]) { url in
                    handleP12Picked(url)
                }
            } else {
                DocumentPicker(contentTypes: [.mobileprovision]) { url in
                    handleProfilePicked(url)
                }
            }
        }
        .alert("Enter Certificate Password", isPresented: Binding(
            get: { importStep == .enterPassword },
            set: { if !$0 { importStep = .idle } }
        )) {
            SecureField("Password", text: $importPassword)
            Button("Cancel", role: .cancel) {
                importStep = .idle
                importPassword = ""
            }
            Button("Add") {
                validateAndImport()
            }
        } message: {
            Text(passwordError ?? "Enter the password for \(importedP12Name)")
        }
        .onChange(of: importStep) { step in
            if step == .pickProfile {
                filePickerType = .profile
                showFilePicker = true
            }
        }
    }

    // MARK: - Import Flow

    private func handleP12Picked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Copy to temp
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)

        importedP12URL = dest
        importedP12Name = url.lastPathComponent

        // Next: pick mobileprovision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            importStep = .pickProfile
        }
    }

    private func handleProfilePicked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Import profile
        try? settings.importProfile(from: url)

        // Next: ask for password
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            importPassword = ""
            passwordError = nil
            importStep = .enterPassword
        }
    }

    private func validateAndImport() {
        guard let p12URL = importedP12URL else {
            importStep = .idle
            return
        }

        // Validate the password by trying to read the PKCS12
        guard let p12Data = try? Data(contentsOf: p12URL) else {
            passwordError = "Could not read P12 file"
            importStep = .enterPassword
            return
        }

        var items: CFArray?
        let options: NSDictionary = [kSecImportExportPassphrase: importPassword]
        let status = SecPKCS12Import(p12Data as CFData, options, &items)

        if status == errSecSuccess {
            // Password valid — save the cert
            let dest = settings.certsDirectory.appendingPathComponent(importedP12Name)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: p12URL, to: dest)
            settings.savedCertName = importedP12Name
            settings.savedCertPassword = importPassword

            importStep = .idle
            importPassword = ""
            passwordError = nil
        } else {
            // Wrong password — re-prompt
            passwordError = "Invalid password. Please try again."
            importPassword = ""
            // Keep in .enterPassword so alert re-shows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                importStep = .enterPassword
            }
        }
    }
}

// MARK: - Certificate Card

struct CertCard: View {

    let cert: RemoteCertificate
    let isInUse: Bool
    let onUse: () -> Void
    @State private var applied = false

    private var isActive: Bool { !cert.isExpired }

    private var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
    }

    private var isDev: Bool {
        (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.scarletRed.opacity(isInUse ? 0.2 : 0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.scarletRed)
            }

            // Name + badges
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(cert.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if isInUse {
                        Text("IN USE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.scarletRed)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.scarletRed.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.scarletRed.opacity(0.3), lineWidth: 0.5))
                            )
                    }
                }

                HStack(spacing: 6) {
                    // Type
                    Text(isDev ? "Development" : "Distribution")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundColor(.scarletRed.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.scarletRed.opacity(0.1)))

                    // PPQ
                    Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }

                // Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive
                              ? Color(red: 0.2, green: 0.65, blue: 0.3).opacity(0.7)
                              : Color.scarletRed.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(isActive ? "Active · \(daysRemaining) days" : "Expired")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Spacer()

            // Use button
            if !isInUse {
                Button {
                    onUse()
                    withAnimation(.easeInOut(duration: 0.2)) { applied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) { applied = false }
                    }
                } label: {
                    ZStack {
                        if applied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.scarletRed)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("Use")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.scarletRed)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 48, height: 30)
                    .background(Capsule().fill(Color.scarletRed.opacity(0.1)))
                }
                .disabled(!isActive)
                .opacity(isActive ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(isInUse ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isInUse ? Color.scarletRed.opacity(0.2) : Color.white.opacity(0.06),
                            lineWidth: isInUse ? 1 : 0.5
                        )
                )
        )
    }
}

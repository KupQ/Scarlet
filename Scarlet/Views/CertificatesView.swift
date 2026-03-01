//
//  CertificatesView.swift
//  Scarlet
//
//  Premium certificate management with Apple Wallet-inspired design.
//

import SwiftUI
import Security

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared
    @ObservedObject private var settings = SigningSettings.shared

    // Import flow
    @State private var importStep: ImportStep = .idle
    @State private var importedP12URL: URL?
    @State private var importedP12Data: Data?
    @State private var importedP12Name: String = ""
    @State private var importPassword: String = ""
    @State private var passwordError: String?
    @State private var showFilePicker = false
    @State private var filePickerType: FilePickerType = .p12

    enum ImportStep { case idle, pickProfile, enterPassword }
    enum FilePickerType { case p12, profile }

    private var activeCert: RemoteCertificate? {
        certService.certificates.first { settings.savedCertName == "\($0.id).p12" }
    }
    private var otherCerts: [RemoteCertificate] {
        certService.certificates.filter { settings.savedCertName != "\($0.id).p12" }
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    if certService.isLoading && certService.certificates.isEmpty {
                        loadingSection
                    } else if certService.certificates.isEmpty {
                        emptySection
                    } else {
                        certContent
                    }
                }
            }
        }
        .task { await certService.fetchCertificates() }
        .sheet(isPresented: $showFilePicker) {
            if filePickerType == .p12 {
                DocumentPicker(contentTypes: [.p12]) { handleP12Picked($0) }
            } else {
                DocumentPicker(contentTypes: [.mobileprovision]) { handleProfilePicked($0) }
            }
        }
        .alert("Certificate Password", isPresented: Binding(
            get: { importStep == .enterPassword },
            set: { if !$0 { importStep = .idle } }
        )) {
            SecureField("Password", text: $importPassword)
            Button("Cancel", role: .cancel) { importStep = .idle; importPassword = "" }
            Button("Import") { validateAndImport() }
        } message: {
            Text(passwordError ?? "Enter the password for \(importedP12Name)")
        }
        .onChange(of: importStep) { step in
            if step == .pickProfile {
                filePickerType = .profile
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Certificates")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            if let udid = certService.deviceUDID {
                Text(udid)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    // MARK: - Certificate Content

    private var certContent: some View {
        VStack(spacing: 24) {
            if let cert = activeCert {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACTIVE CERTIFICATE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(.scarletRed.opacity(0.6))
                        .padding(.horizontal, 20)

                    HeroCard(cert: cert)
                        .padding(.horizontal, 20)
                }
            }

            if !otherCerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AVAILABLE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        ForEach(otherCerts) { cert in
                            CompactCard(cert: cert)
                                .onTapGesture { selectCert(cert) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Import card
            Button {
                filePickerType = .p12
                showFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                    Text("Import Certificate")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundColor(.white.opacity(0.08))
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Selection

    private func selectCert(_ cert: RemoteCertificate) {
        guard !cert.isExpired else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        certService.useCertificate(cert)
        settings.objectWillChange.send()
    }

    // MARK: - Empty / Loading

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.scarletRed).scaleEffect(1.2)
            Text("Loading certificates...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    private var emptySection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.scarletRed.opacity(0.15), .clear],
                                         center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 100, height: 100)
                Image(systemName: "lock.shield")
                    .font(.system(size: 34))
                    .foregroundColor(.scarletRed.opacity(0.5))
            }
            Text("No Certificates")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text("Tap Import Certificate below")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.2))

            // Import button in empty state too
            Button {
                filePickerType = .p12
                showFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                    Text("Import Certificate")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.scarletRed)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Color.scarletRed.opacity(0.12))
                )
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: - Import Flow

    private func handleP12Picked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        // Read data into memory immediately while we have access
        guard let data = try? Data(contentsOf: url) else { return }
        importedP12Data = data
        importedP12Name = url.lastPathComponent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { importStep = .pickProfile }
    }

    private func handleProfilePicked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try? settings.importProfile(from: url)

        // Auto-try common passwords
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            tryCommonPasswords()
        }
    }

    private static let commonPasswords = ["", "1", "password", "1234", "123", "123456789"]

    private func tryCommonPasswords() {
        guard let p12Data = importedP12Data else { return }

        for pwd in Self.commonPasswords {
            var items: CFArray?
            let opts: NSDictionary = [kSecImportExportPassphrase: pwd]
            if SecPKCS12Import(p12Data as CFData, opts, &items) == errSecSuccess {
                // Found matching password — save
                saveCert(password: pwd)
                return
            }
        }

        // None matched — ask user
        importPassword = ""
        passwordError = nil
        importStep = .enterPassword
    }

    private func validateAndImport() {
        guard let p12Data = importedP12Data else {
            passwordError = "Could not read P12 file"; return
        }

        var items: CFArray?
        let opts: NSDictionary = [kSecImportExportPassphrase: importPassword]
        let status = SecPKCS12Import(p12Data as CFData, opts, &items)

        if status == errSecSuccess {
            saveCert(password: importPassword)
        } else if status == errSecAuthFailed {
            passwordError = "Wrong password. Please try again."
            importPassword = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { importStep = .idle }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importStep = .enterPassword }
        } else {
            // Other error — save anyway, zsign will catch later
            saveCert(password: importPassword)
        }
    }

    private func saveCert(password: String) {
        guard let data = importedP12Data else { return }
        let dest = settings.certsDirectory.appendingPathComponent(importedP12Name)
        try? FileManager.default.removeItem(at: dest)
        try? data.write(to: dest)
        settings.savedCertName = importedP12Name
        settings.savedCertPassword = password
        importStep = .idle
        importPassword = ""
        importedP12Data = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Hero Card (Active Certificate)

struct HeroCard: View {
    let cert: RemoteCertificate

    private var days: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
    }
    private var isDev: Bool {
        (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
    }
    private var progress: Double { min(1, Double(days) / 365.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.scarletRed)
                            .frame(width: 8, height: 8)
                        Text("SCARLET")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.scarletRed.opacity(0.7))
                    }
                    Text(cert.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 3)
                        .frame(width: 50, height: 50)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(colors: [.scarletRed, .scarletPink],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(days)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("days")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.scarletRed.opacity(0.2), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.5)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                        .font(.system(size: 9))
                    Text(isDev ? "Development" : "Distribution")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.45))

                Spacer()

                Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.65, blue: 0.3).opacity(0.7))
                        .frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color.scarletRed.opacity(0.08),
                                 Color(red: 0.08, green: 0.08, blue: 0.1),
                                 Color(red: 0.06, green: 0.06, blue: 0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 18)
                    .stroke(LinearGradient(
                        colors: [Color.scarletRed.opacity(0.3), Color.scarletRed.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        )
        .shadow(color: Color.scarletRed.opacity(0.08), radius: 20, y: 8)
    }
}

// MARK: - Compact Card (Available Certificate)

struct CompactCard: View {
    let cert: RemoteCertificate

    private var isActive: Bool { !cert.isExpired }
    private var days: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
    }
    private var isDev: Bool {
        (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.scarletRed.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.scarletRed.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cert.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(isDev ? "Development" : "Distribution")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.scarletRed.opacity(0.7))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isActive
                                  ? Color(red: 0.2, green: 0.65, blue: 0.3).opacity(0.7)
                                  : Color.scarletRed.opacity(0.5))
                            .frame(width: 4, height: 4)
                        Text(isActive ? "\(days)d" : "Exp")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .opacity(isActive ? 1 : 0.4)
    }
}

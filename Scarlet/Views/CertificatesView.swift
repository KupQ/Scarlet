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
    @State private var importedP12Name: String = ""
    @State private var importPassword: String = ""
    @State private var passwordError: String?
    @State private var showFilePicker = false
    @State private var filePickerType: FilePickerType = .p12

    enum ImportStep { case idle, pickProfile, enterPassword }
    enum FilePickerType { case p12, profile }

    // Active cert
    private var activeCert: RemoteCertificate? {
        certService.certificates.first { settings.savedCertName == "\($0.id).p12" }
    }
    private var otherCerts: [RemoteCertificate] {
        certService.certificates.filter { settings.savedCertName != "\($0.id).p12" }
    }

    var body: some View {
        ZStack {
            // Deep dark background
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
        HStack(alignment: .center) {
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
            Spacer()
            Button {
                filePickerType = .p12
                showFilePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.scarletRed)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.scarletRed.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    // MARK: - Active Certificate (Hero Card)

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
                            CompactCard(cert: cert) {
                                certService.useCertificate(cert)
                                settings.objectWillChange.send()
                            }
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

    // MARK: - Empty / Loading

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.scarletRed).scaleEffect(1.2)
            Text("Loading certificates...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var emptySection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [Color.scarletRed.opacity(0.15), .clear],
                                       center: .center, startRadius: 0, endRadius: 50)
                    )
                    .frame(width: 100, height: 100)
                Image(systemName: "lock.shield")
                    .font(.system(size: 34))
                    .foregroundColor(.scarletRed.opacity(0.5))
            }
            Text("No Certificates")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text("Tap + to import your own")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Import Flow

    private func handleP12Picked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        importedP12URL = dest
        importedP12Name = url.lastPathComponent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { importStep = .pickProfile }
    }

    private func handleProfilePicked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try? settings.importProfile(from: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            importPassword = ""; passwordError = nil; importStep = .enterPassword
        }
    }

    private func validateAndImport() {
        guard let p12URL = importedP12URL,
              let p12Data = try? Data(contentsOf: p12URL) else {
            passwordError = "Could not read P12 file"; return
        }
        var items: CFArray?
        let opts: NSDictionary = [kSecImportExportPassphrase: importPassword]
        if SecPKCS12Import(p12Data as CFData, opts, &items) == errSecSuccess {
            let dest = settings.certsDirectory.appendingPathComponent(importedP12Name)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: p12URL, to: dest)
            settings.savedCertName = importedP12Name
            settings.savedCertPassword = importPassword
            importStep = .idle; importPassword = ""
        } else {
            passwordError = "Invalid password. Try again."
            importPassword = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { importStep = .enterPassword }
        }
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
    private var progress: Double {
        min(1, Double(days) / 365.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Scarlet logo placeholder
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
                // Days ring
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

            // Divider
            Rectangle()
                .fill(
                    LinearGradient(colors: [.clear, Color.scarletRed.opacity(0.2), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 0.5)

            // Bottom info row
            HStack {
                // Type
                HStack(spacing: 4) {
                    Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                        .font(.system(size: 9))
                    Text(isDev ? "Development" : "Distribution")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.45))

                Spacer()

                // PPQ
                Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                // Status
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.scarletRed.opacity(0.08),
                                Color(red: 0.08, green: 0.08, blue: 0.1),
                                Color(red: 0.06, green: 0.06, blue: 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [Color.scarletRed.opacity(0.3), Color.scarletRed.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.scarletRed.opacity(0.08), radius: 20, y: 8)
    }
}

// MARK: - Compact Card (Available Certificate)

struct CompactCard: View {
    let cert: RemoteCertificate
    let onUse: () -> Void
    @State private var applied = false

    private var isActive: Bool { !cert.isExpired }
    private var days: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
    }
    private var isDev: Bool {
        (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
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

                    Text("·")
                        .foregroundColor(.white.opacity(0.15))

                    Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))

                    Text("·")
                        .foregroundColor(.white.opacity(0.15))

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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.scarletRed)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Use")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.scarletRed)
                            .transition(.opacity)
                    }
                }
                .frame(width: 44, height: 28)
                .background(Capsule().fill(Color.scarletRed.opacity(0.1)))
            }
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.3)
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
    }
}

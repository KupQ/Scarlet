//
//  CertificatesView.swift
//  Scarlet
//
//  Certificate management with clear valid/revoked status.
//  Supports multiple locally imported certs.
//

import SwiftUI
import Security

/// Persisted info about a locally imported cert
struct LocalImportedCert: Codable, Identifiable, Equatable {
    let filename: String   // e.g. "local_cert.p12"
    let password: String
    var id: String { filename }
}

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared
    @ObservedObject private var settings = SigningSettings.shared
    @ObservedObject private var localChecker = LocalCertChecker.shared

    // Multiple local certs persisted as JSON
    @AppStorage("local_imported_certs_json") private var localCertsJSON: String = "[]"

    // Import flow
    @State private var importStep: ImportStep = .idle
    @State private var importedP12URL: URL?
    @State private var importedP12Data: Data?
    @State private var importedP12Name: String = ""
    @State private var importPassword: String = ""
    @State private var passwordError: String?
    @State private var showFilePicker = false
    @State private var filePickerType: FilePickerType = .p12
    @State private var certToDelete: LocalImportedCert?
    @State private var showDeleteConfirm = false

    enum ImportStep { case idle, pickProfile, enterPassword }
    enum FilePickerType { case p12, profile }

    // MARK: - Local Cert Storage

    private var localCerts: [LocalImportedCert] {
        guard let data = localCertsJSON.data(using: .utf8),
              let certs = try? JSONDecoder().decode([LocalImportedCert].self, from: data) else { return [] }
        return certs
    }

    private func addLocalCert(_ cert: LocalImportedCert) {
        var certs = localCerts.filter { $0.filename != cert.filename }
        certs.insert(cert, at: 0)
        if let data = try? JSONEncoder().encode(certs), let json = String(data: data, encoding: .utf8) {
            localCertsJSON = json
        }
    }

    private func deleteLocalCert(_ cert: LocalImportedCert) {
        // Remove from JSON storage
        var certs = localCerts.filter { $0.filename != cert.filename }
        if let data = try? JSONEncoder().encode(certs), let json = String(data: data, encoding: .utf8) {
            localCertsJSON = json
        }
        // Delete file from disk
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent(cert.filename)
        try? FileManager.default.removeItem(at: fileURL)
        // Clear active cert if it was the deleted one
        if settings.savedCertName == cert.filename {
            settings.savedCertName = ""
            settings.savedCertPassword = ""
            settings.objectWillChange.send()
        }
    }

    // MARK: - Computed

    private var activeCert: RemoteCertificate? {
        certService.certificates.first { settings.savedCertName == "\($0.id).p12" }
    }

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                headerSection

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if certService.isLoading && certService.certificates.isEmpty && localCerts.isEmpty {
                            loadingSection
                        } else if certService.certificates.isEmpty && localCerts.isEmpty {
                            emptySection
                        } else {
                            certContent
                        }
                    }
                }
                .refreshable {
                    await certService.fetchCertificates()
                    await localChecker.forceCheckAPICerts(certService.certificates)
                }
            }
        }
        .task {
            await certService.fetchCertificates()
            // Check API certs only once per session
            await localChecker.checkAPICertsIfNeeded(certService.certificates)
            // Check local certs only if not already checked
            let pairs = localCerts.map { (name: $0.filename, password: $0.password) }
            await localChecker.checkAllLocalCerts(certs: pairs)
        }
        .sheet(isPresented: $showFilePicker) {
            if filePickerType == .p12 {
                DocumentPicker(contentTypes: [.p12]) { handleP12Picked($0) }
            } else {
                DocumentPicker(contentTypes: [.mobileprovision]) { handleProfilePicked($0) }
            }
        }
        .alert(L("Certificate Password"), isPresented: Binding(
            get: { importStep == .enterPassword },
            set: { if !$0 { importStep = .idle } }
        )) {
            SecureField(L("Password"), text: $importPassword)
            Button(L("Cancel"), role: .cancel) { importStep = .idle; importPassword = "" }
            Button(L("Import")) { validateAndImport() }
        } message: {
            Text(passwordError ?? "Enter the password for \(importedP12Name)")
        }
        .alert(L("Delete Certificate"), isPresented: $showDeleteConfirm) {
            Button(L("Cancel"), role: .cancel) { certToDelete = nil }
            Button(L("Delete"), role: .destructive) {
                if let cert = certToDelete {
                    deleteLocalCert(cert)
                    certToDelete = nil
                }
            }
        } message: {
            Text(L("Are you sure you want to delete") + " " + (certToDelete?.filename.replacingOccurrences(of: "local_", with: "").replacingOccurrences(of: ".p12", with: "") ?? L("this certificate")) + "?")
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Certificates"))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.scarletRed.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Certificate Content

    private var certContent: some View {
        VStack(spacing: 16) {
            // ── Local cert cards ──
            if !localCerts.isEmpty {
                ForEach(localCerts) { cert in
                    localCertCard(cert)
                        .contextMenu {
                            Button(role: .destructive) {
                                certToDelete = cert
                                showDeleteConfirm = true
                            } label: {
                                Label(L("Delete Certificate"), systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, 20)
                }
            }

            // ── API certs ──
            if !certService.certificates.isEmpty {
                ForEach(certService.certificates) { cert in
                    apiCertCard(cert)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 30)
    }

    // MARK: - API Certificate Card

    private func apiCertCard(_ cert: RemoteCertificate) -> some View {
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
        let isDev = (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
        let isActive = settings.savedCertName == "\(cert.id).p12"
        let ocspStatus = localChecker.statusFor(cert.id)
        let (_, statusClr) = statusIconAndColor(ocspStatus)

        return Button {
            selectCert(cert)
        } label: {
            ZStack {
                if isActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Circle()
                            .fill(RadialGradient(
                                colors: [statusClr.opacity(0.15), .clear],
                                center: .center, startRadius: 5, endRadius: 80
                            ))
                            .frame(width: 160, height: 160)
                            .offset(
                                x: CGFloat(sin(t * 0.5)) * 60 + 40,
                                y: CGFloat(cos(t * 0.4)) * 30 - 10
                            )
                            .blur(radius: 20)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(statusClr.opacity(0.08))
                                .frame(width: 44, height: 44)
                            Image(systemName: statusIconName(ocspStatus))
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(statusClr.opacity(0.6))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cert.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(cert.pname)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(statusClr)
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle()
                                            .fill(statusClr.opacity(0.3))
                                            .frame(width: 14, height: 14)
                                            .opacity(isActive ? 1 : 0)
                                    )
                                Text(ocspStatus.label)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(statusClr)
                            }
                            if isActive {
                                Text(L("ACTIVE"))
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundColor(.white.opacity(0.35))
                                    .tracking(2)
                            }
                        }
                    }
                    .padding(16)

                    Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)

                    HStack(spacing: 8) {
                        certChip(icon: isDev ? "hammer" : "building.2", text: isDev ? L("Development") : L("Distribution"))
                        certChip(icon: cert.isPPQEnabled ? "lock.fill" : "lock.open", text: cert.isPPQEnabled ? "PPQ" : "PPQless")
                        certChip(icon: "calendar", text: cert.isExpired ? L("Expired") : "\(days)d", highlight: cert.isExpired)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(isActive ? 0.04 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isActive
                                    ? LinearGradient(colors: [statusClr.opacity(0.3), statusClr.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: isActive ? 1 : 0.5
                            )
                    )
                    .shadow(color: isActive ? statusClr.opacity(0.12) : .clear, radius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Local Certificate Card

    private func localCertCard(_ cert: LocalImportedCert) -> some View {
        let info = localChecker.localCertInfos[cert.filename]
        let ocspStatus = info?.status ?? .checking
        let certName = info?.commonName ?? cert.filename.replacingOccurrences(of: ".p12", with: "").replacingOccurrences(of: "local_", with: "")
        let isActive = settings.savedCertName == cert.filename
        let daysLeft = info?.daysLeft ?? 0
        let (_, statusClr) = statusIconAndColor(ocspStatus)
        let isDev = certName.localizedCaseInsensitiveContains("Development")

        return Button {
            if !isActive {
                settings.savedCertName = cert.filename
                settings.savedCertPassword = cert.password
                settings.objectWillChange.send()
            }
        } label: {
            ZStack {
                if isActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Circle()
                            .fill(RadialGradient(
                                colors: [statusClr.opacity(0.15), .clear],
                                center: .center, startRadius: 5, endRadius: 80
                            ))
                            .frame(width: 160, height: 160)
                            .offset(
                                x: CGFloat(cos(t * 0.45)) * 55 - 30,
                                y: CGFloat(sin(t * 0.55)) * 25 + 5
                            )
                            .blur(radius: 20)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(statusClr.opacity(0.08))
                                .frame(width: 44, height: 44)
                            Image(systemName: statusIconName(ocspStatus))
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(statusClr.opacity(0.6))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(certName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(L("Local Certificate"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.2))
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(statusClr)
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle()
                                            .fill(statusClr.opacity(0.3))
                                            .frame(width: 14, height: 14)
                                            .opacity(isActive ? 1 : 0)
                                    )
                                Text(ocspStatus.label)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(statusClr)
                            }
                            if isActive {
                                Text(L("ACTIVE"))
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundColor(.white.opacity(0.35))
                                    .tracking(2)
                            }
                        }
                    }
                    .padding(16)

                    Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)

                    HStack(spacing: 8) {
                        certChip(icon: isDev ? "hammer" : "building.2", text: isDev ? L("Development") : L("Distribution"))
                        certChip(icon: "lock.open", text: "PPQless")
                        certChip(icon: "calendar", text: daysLeft > 0 ? "\(daysLeft)d" : L("Expired"), highlight: daysLeft <= 0)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(isActive ? 0.04 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isActive
                                    ? LinearGradient(colors: [statusClr.opacity(0.3), statusClr.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: isActive ? 1 : 0.5
                            )
                    )
                    .shadow(color: isActive ? statusClr.opacity(0.12) : .clear, radius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Card Components

    private func chipView(icon: String, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(color ?? .white.opacity(0.3))
    }

    private func certChip(icon: String, text: String, highlight: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(highlight ? .orange : .white.opacity(0.45))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(highlight ? Color.orange.opacity(0.08) : Color.white.opacity(0.04))
                .overlay(
                    Capsule()
                        .stroke(highlight ? Color.orange.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func statusIconAndColor(_ status: LocalCertInfo.CertStatus) -> (String, Color) {
        switch status {
        case .valid:    return ("checkmark.shield.fill", Color(red: 0.2, green: 0.75, blue: 0.4))
        case .revoked:  return ("xmark.shield.fill", Color(red: 0.95, green: 0.25, blue: 0.25))
        case .expired:  return ("clock.badge.exclamationmark", .orange)
        case .checking: return ("shield.lefthalf.filled", .yellow)
        case .error:    return ("exclamationmark.triangle.fill", .gray)
        }
    }

    private func statusIconName(_ status: LocalCertInfo.CertStatus) -> String {
        switch status {
        case .valid:    return "checkmark.shield"
        case .revoked:  return "xmark.shield"
        case .expired:  return "clock.badge.xmark"
        case .checking: return "arrow.triangle.2.circlepath"
        case .error:    return "exclamationmark.triangle"
        }
    }

    private func statItem(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.35))
    }

    // MARK: - Selection

    private func selectCert(_ cert: RemoteCertificate) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        certService.useCertificate(cert)
        settings.objectWillChange.send()
    }

    // MARK: - Empty / Loading

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.scarletRed).scaleEffect(1.2)
            Text(L("Loading certificates..."))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    private var emptySection: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.scarletRed.opacity(0.12), .clear],
                                         center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 120, height: 120)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.scarletRed.opacity(0.5), .scarletPink.opacity(0.3)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
            VStack(spacing: 8) {
                Text(L("No Certificates Yet"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Text(L("Import a P12 certificate to get started"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
            }

            Button {
                filePickerType = .p12
                showFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(L("Import Certificate"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.scarletRed, .scarletDark],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                )
                .shadow(color: .scarletRed.opacity(0.3), radius: 12, y: 6)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    // MARK: - Import Flow

    private func handleP12Picked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        importedP12Data = data
        importedP12Name = url.lastPathComponent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { importStep = .pickProfile }
    }

    private func handleProfilePicked(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try? settings.importProfile(from: url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            tryCommonPasswords()
        }
    }

    private static let commonPasswords = ["", "1", "password", "1234", "123", "123456789", "AppleP12.com"]

    private func tryCommonPasswords() {
        guard let p12Data = importedP12Data else { return }

        for pwd in Self.commonPasswords {
            if PKCS12Validator.validate(data: p12Data, password: pwd) {
                saveCert(password: pwd)
                return
            }
        }

        importPassword = ""
        passwordError = nil
        importStep = .enterPassword
    }

    private func validateAndImport() {
        guard let p12Data = importedP12Data else {
            passwordError = "Could not read P12 file"; return
        }

        if PKCS12Validator.validate(data: p12Data, password: importPassword) {
            saveCert(password: importPassword)
        } else {
            passwordError = L("Wrong password. Please try again.")
            importPassword = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { importStep = .idle }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importStep = .enterPassword }
        }
    }

    private func saveCert(password: String) {
        guard let data = importedP12Data else { return }
        let localName = "local_\(importedP12Name)"
        let dest = settings.certsDirectory.appendingPathComponent(localName)
        try? FileManager.default.removeItem(at: dest)
        try? data.write(to: dest)

        // Set as active cert
        settings.savedCertName = localName
        settings.savedCertPassword = password

        // Add to local certs list
        addLocalCert(LocalImportedCert(filename: localName, password: password))

        importStep = .idle
        importPassword = ""
        importedP12Data = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Check this specific cert via OCSP
        Task { await localChecker.checkLocalCert(name: localName, password: password) }
    }
}

// MARK: - PKCS12 Password Validator (no keychain entitlements needed)

import CommonCrypto

/// Validates a PKCS12 password by verifying the MAC in the file header.
/// Works on sideloaded apps where SecPKCS12Import fails.
enum PKCS12Validator {

    // SHA OIDs
    private static let sha1OID:   [UInt8] = [0x2B, 0x0E, 0x03, 0x02, 0x1A]
    private static let sha256OID: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]

    static func validate(data: Data, password: String) -> Bool {
        let bmpPassword = bmpEncode(password)
        let bytes = [UInt8](data)

        guard let parsed = parseP12(bytes) else { return false }

        let useSHA256 = parsed.algoOID == sha256OID
        let hashLen = useSHA256 ? 32 : 20

        let derivedKey = pkcs12KDF(
            password: bmpPassword, salt: parsed.salt,
            iterations: parsed.iterations, keyLen: hashLen,
            id: 3, useSHA256: useSHA256
        )

        var hmacOut = [UInt8](repeating: 0, count: hashLen)
        let algo = useSHA256 ? CCHmacAlgorithm(kCCHmacAlgSHA256) : CCHmacAlgorithm(kCCHmacAlgSHA1)
        CCHmac(algo, derivedKey, derivedKey.count,
               parsed.authSafeContent, parsed.authSafeContent.count, &hmacOut)

        return hmacOut == parsed.expectedDigest
    }

    // MARK: - Internal types

    private struct P12Info {
        let expectedDigest: [UInt8]
        let algoOID: [UInt8]
        let salt: [UInt8]
        let iterations: Int
        let authSafeContent: [UInt8]
    }

    private struct TLV {
        let contentOffset: Int
        let contentLength: Int
    }

    // MARK: - P12 Parser

    private static func parseP12(_ bytes: [UInt8]) -> P12Info? {
        guard bytes.first == 0x30, let outer = tlv(bytes, 0) else { return nil }
        var pos = outer.contentOffset

        guard let ver = tlv(bytes, pos) else { return nil }
        pos = ver.contentOffset + ver.contentLength

        guard pos < bytes.count, bytes[pos] == 0x30, let ciTag = tlv(bytes, pos) else { return nil }
        let ciEnd = ciTag.contentOffset + ciTag.contentLength

        var ci = ciTag.contentOffset
        guard let oid = tlv(bytes, ci) else { return nil }
        ci = oid.contentOffset + oid.contentLength

        guard ci < bytes.count, bytes[ci] == 0xA0, let expl = tlv(bytes, ci) else { return nil }

        guard expl.contentOffset < bytes.count, bytes[expl.contentOffset] == 0x04,
              let oct = tlv(bytes, expl.contentOffset) else { return nil }
        let authSafeContent = Array(bytes[oct.contentOffset..<(oct.contentOffset + oct.contentLength)])

        pos = ciEnd

        guard pos < bytes.count, bytes[pos] == 0x30, let macSeq = tlv(bytes, pos) else { return nil }
        var mp = macSeq.contentOffset

        guard mp < bytes.count, bytes[mp] == 0x30, let diSeq = tlv(bytes, mp) else { return nil }
        let diEnd = diSeq.contentOffset + diSeq.contentLength
        let diBytes = Array(bytes[diSeq.contentOffset..<diEnd])

        var dp = 0
        guard dp < diBytes.count, diBytes[dp] == 0x30, let algSeq = tlv(diBytes, dp) else { return nil }
        let algBytes = Array(diBytes[algSeq.contentOffset..<(algSeq.contentOffset + algSeq.contentLength)])
        guard !algBytes.isEmpty, algBytes[0] == 0x06, let oidT = tlv(algBytes, 0) else { return nil }
        let algoOID = Array(algBytes[oidT.contentOffset..<(oidT.contentOffset + oidT.contentLength)])

        dp = algSeq.contentOffset + algSeq.contentLength
        guard dp < diBytes.count, diBytes[dp] == 0x04, let digTag = tlv(diBytes, dp) else { return nil }
        let expectedDigest = Array(diBytes[digTag.contentOffset..<(digTag.contentOffset + digTag.contentLength)])

        mp = diEnd

        guard mp < bytes.count, bytes[mp] == 0x04, let saltTag = tlv(bytes, mp) else { return nil }
        let salt = Array(bytes[saltTag.contentOffset..<(saltTag.contentOffset + saltTag.contentLength)])
        mp = saltTag.contentOffset + saltTag.contentLength

        var iterations = 1
        if mp < bytes.count && bytes[mp] == 0x02, let itTag = tlv(bytes, mp) {
            iterations = 0
            for i in 0..<itTag.contentLength {
                iterations = (iterations << 8) | Int(bytes[itTag.contentOffset + i])
            }
        }

        return P12Info(expectedDigest: expectedDigest, algoOID: algoOID,
                       salt: salt, iterations: iterations, authSafeContent: authSafeContent)
    }

    // MARK: - BMP Encoding

    private static func bmpEncode(_ str: String) -> [UInt8] {
        var r = [UInt8]()
        for s in str.unicodeScalars {
            r.append(UInt8(UInt16(s.value) >> 8))
            r.append(UInt8(UInt16(s.value) & 0xFF))
        }
        r += [0, 0]
        return r
    }

    // MARK: - PKCS12 KDF (RFC 7292 Appendix B)

    private static func pkcs12KDF(password: [UInt8], salt: [UInt8], iterations: Int,
                                   keyLen: Int, id: UInt8, useSHA256: Bool) -> [UInt8] {
        let hashLen = useSHA256 ? 32 : 20
        let v = 64
        let D = [UInt8](repeating: id, count: v)
        let S = pad(salt, v); let P = pad(password, v)
        var I = S + P
        var result = [UInt8]()

        while result.count < keyLen {
            var A = D + I
            for _ in 0..<iterations {
                var d = [UInt8](repeating: 0, count: hashLen)
                if useSHA256 { CC_SHA256(A, CC_LONG(A.count), &d) }
                else         { CC_SHA1(A, CC_LONG(A.count), &d) }
                A = d
            }
            result += A
            if result.count >= keyLen { break }
            let B = pad(A, v)
            var nI = [UInt8]()
            for j in stride(from: 0, to: I.count, by: v) {
                nI += add1(Array(I[j..<min(j+v, I.count)]), B)
            }
            I = nI
        }
        return Array(result.prefix(keyLen))
    }

    private static func pad(_ d: [UInt8], _ v: Int) -> [UInt8] {
        guard !d.isEmpty else { return [] }
        let n = ((d.count + v - 1) / v) * v
        return (0..<n).map { d[$0 % d.count] }
    }

    private static func add1(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: a.count)
        var c: UInt16 = 1
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            let s = UInt16(a[i]) + UInt16(b[i % b.count]) + c
            r[i] = UInt8(s & 0xFF); c = s >> 8
        }
        return r
    }

    // MARK: - ASN1 TLV

    private static func tlv(_ b: [UInt8], _ off: Int) -> TLV? {
        guard off + 1 < b.count else { return nil }
        var p = off + 1
        if b[p] & 0x80 == 0 {
            return TLV(contentOffset: p + 1, contentLength: Int(b[p]))
        }
        let n = Int(b[p] & 0x7F); p += 1
        var len = 0
        for _ in 0..<n { guard p < b.count else { return nil }; len = (len << 8) | Int(b[p]); p += 1 }
        return TLV(contentOffset: p, contentLength: len)
    }
}

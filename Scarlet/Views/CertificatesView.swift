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
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .background(Color.bgPrimary)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if certService.isLoading && certService.certificates.isEmpty {
                            loadingSection
                        } else if certService.certificates.isEmpty {
                            emptySection
                        } else {
                            certContent
                        }
                    }
                }
                .refreshable {
                    await certService.fetchCertificates()
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
            if PKCS12Validator.validate(data: p12Data, password: pwd) {
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

        if PKCS12Validator.validate(data: p12Data, password: importPassword) {
            saveCert(password: importPassword)
        } else {
            passwordError = "Wrong password. Please try again."
            importPassword = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { importStep = .idle }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importStep = .enterPassword }
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

        // 1. Version INTEGER
        guard let ver = tlv(bytes, pos) else { return nil }
        pos = ver.contentOffset + ver.contentLength

        // 2. AuthSafe ContentInfo SEQUENCE
        guard pos < bytes.count, bytes[pos] == 0x30, let ciTag = tlv(bytes, pos) else { return nil }
        let ciEnd = ciTag.contentOffset + ciTag.contentLength

        // Inside ContentInfo: contentType OID + [0] EXPLICIT { OCTET STRING }
        var ci = ciTag.contentOffset
        guard let oid = tlv(bytes, ci) else { return nil }
        ci = oid.contentOffset + oid.contentLength

        // [0] EXPLICIT (tag 0xA0)
        guard ci < bytes.count, bytes[ci] == 0xA0, let expl = tlv(bytes, ci) else { return nil }

        // OCTET STRING inside [0] — THIS is what gets HMACed
        guard expl.contentOffset < bytes.count, bytes[expl.contentOffset] == 0x04,
              let oct = tlv(bytes, expl.contentOffset) else { return nil }
        let authSafeContent = Array(bytes[oct.contentOffset..<(oct.contentOffset + oct.contentLength)])

        pos = ciEnd

        // 3. MacData SEQUENCE
        guard pos < bytes.count, bytes[pos] == 0x30, let macSeq = tlv(bytes, pos) else { return nil }
        var mp = macSeq.contentOffset

        // DigestInfo SEQUENCE
        guard mp < bytes.count, bytes[mp] == 0x30, let diSeq = tlv(bytes, mp) else { return nil }
        let diEnd = diSeq.contentOffset + diSeq.contentLength
        let diBytes = Array(bytes[diSeq.contentOffset..<diEnd])

        // Parse DigestInfo internals
        var dp = 0
        // AlgorithmIdentifier SEQUENCE
        guard dp < diBytes.count, diBytes[dp] == 0x30, let algSeq = tlv(diBytes, dp) else { return nil }
        let algBytes = Array(diBytes[algSeq.contentOffset..<(algSeq.contentOffset + algSeq.contentLength)])
        // OID inside AlgorithmIdentifier
        guard !algBytes.isEmpty, algBytes[0] == 0x06, let oidT = tlv(algBytes, 0) else { return nil }
        let algoOID = Array(algBytes[oidT.contentOffset..<(oidT.contentOffset + oidT.contentLength)])

        dp = algSeq.contentOffset + algSeq.contentLength
        // Digest OCTET STRING
        guard dp < diBytes.count, diBytes[dp] == 0x04, let digTag = tlv(diBytes, dp) else { return nil }
        let expectedDigest = Array(diBytes[digTag.contentOffset..<(digTag.contentOffset + digTag.contentLength)])

        mp = diEnd

        // macSalt OCTET STRING
        guard mp < bytes.count, bytes[mp] == 0x04, let saltTag = tlv(bytes, mp) else { return nil }
        let salt = Array(bytes[saltTag.contentOffset..<(saltTag.contentOffset + saltTag.contentLength)])
        mp = saltTag.contentOffset + saltTag.contentLength

        // iterations INTEGER (optional, default 1)
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
                    HStack(spacing: 5) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.scarletRed.opacity(0.5))
                        Text("CERTIFICATE")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.2))
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
                                 Color(red: 0.11, green: 0.11, blue: 0.13)],
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

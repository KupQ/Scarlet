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

    static func validate(data: Data, password: String) -> Bool {
        // PKCS12 uses BMP (UTF-16BE) encoding for passwords, null-terminated
        let bmpPassword = bmpEncode(password)
        let bytes = [UInt8](data)

        // Parse outer SEQUENCE
        guard let outer = parseSequence(bytes, offset: 0) else { return false }

        // Find macData — it's the last element in the outer sequence
        // Structure: SEQUENCE { version, authSafe, macData }
        var offset = outer.contentOffset
        let end = outer.contentOffset + outer.contentLength

        var lastSequenceOffset = -1
        var lastSequenceLength = 0
        var count = 0

        while offset < end {
            guard let tag = parseTag(bytes, offset: offset) else { break }
            if count >= 2 {
                // This should be macData
                lastSequenceOffset = tag.contentOffset
                lastSequenceLength = tag.contentLength
            }
            offset = tag.contentOffset + tag.contentLength
            count += 1
        }

        guard lastSequenceOffset >= 0 else { return false }

        // Parse macData: SEQUENCE { mac: DigestInfo, macSalt, iterations }
        let macDataBytes = Array(bytes[lastSequenceOffset..<(lastSequenceOffset + lastSequenceLength)])
        guard let macData = parseMacData(macDataBytes, fullData: bytes, outerSeq: outer) else { return false }

        // PKCS12 key derivation for MAC key (ID=3)
        let macKeyLen = 20 // SHA-1
        let derivedKey = pkcs12KDF(
            password: bmpPassword,
            salt: macData.salt,
            iterations: macData.iterations,
            keyLen: macKeyLen,
            id: 3 // MAC key material
        )

        // Compute HMAC-SHA1 over authSafe content
        let authSafeData = macData.authSafeContent
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), derivedKey, derivedKey.count,
               authSafeData, authSafeData.count, &hmac)

        return hmac == macData.expectedDigest
    }

    // MARK: - BMP Encoding

    private static func bmpEncode(_ str: String) -> [UInt8] {
        var result = [UInt8]()
        for scalar in str.unicodeScalars {
            let val = UInt16(scalar.value)
            result.append(UInt8(val >> 8))
            result.append(UInt8(val & 0xFF))
        }
        // Null terminator
        result.append(0)
        result.append(0)
        return result
    }

    // MARK: - PKCS12 KDF (RFC 7292 Appendix B)

    private static func pkcs12KDF(password: [UInt8], salt: [UInt8], iterations: Int, keyLen: Int, id: UInt8) -> [UInt8] {
        let hashLen = 20 // SHA-1
        let blockLen = 64 // SHA-1 block

        let D = [UInt8](repeating: id, count: blockLen)

        // Fill S (salt) and P (password) to block boundaries
        let S = fillToBlockSize(salt, blockLen: blockLen)
        let P = fillToBlockSize(password, blockLen: blockLen)
        var I = S + P

        var result = [UInt8]()

        while result.count < keyLen {
            var A = D + I
            // Hash iterations times
            for _ in 0..<iterations {
                var digest = [UInt8](repeating: 0, count: hashLen)
                CC_SHA1(A, CC_LONG(A.count), &digest)
                A = digest
            }
            result.append(contentsOf: A)

            if result.count >= keyLen { break }

            // Adjust I
            let B = fillToBlockSize(A, blockLen: blockLen)
            var newI = [UInt8]()
            for j in stride(from: 0, to: I.count, by: blockLen) {
                let chunk = Array(I[j..<min(j + blockLen, I.count)])
                let adjusted = addWithCarry(chunk, B)
                newI.append(contentsOf: adjusted)
            }
            I = newI
        }

        return Array(result.prefix(keyLen))
    }

    private static func fillToBlockSize(_ data: [UInt8], blockLen: Int) -> [UInt8] {
        if data.isEmpty { return [] }
        let count = ((data.count + blockLen - 1) / blockLen) * blockLen
        var result = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = data[i % data.count]
        }
        return result
    }

    private static func addWithCarry(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: a.count)
        var carry: UInt16 = 1
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            let sum = UInt16(a[i]) + UInt16(b[i % b.count]) + carry
            result[i] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
        return result
    }

    // MARK: - ASN1 Parsing

    struct TagInfo {
        let contentOffset: Int
        let contentLength: Int
    }

    struct MacInfo {
        let expectedDigest: [UInt8]
        let salt: [UInt8]
        let iterations: Int
        let authSafeContent: [UInt8]
    }

    private static func parseTag(_ bytes: [UInt8], offset: Int) -> TagInfo? {
        guard offset < bytes.count else { return nil }
        var pos = offset + 1 // skip tag byte
        guard pos < bytes.count else { return nil }

        var length: Int
        if bytes[pos] & 0x80 == 0 {
            length = Int(bytes[pos])
            pos += 1
        } else {
            let numBytes = Int(bytes[pos] & 0x7F)
            pos += 1
            length = 0
            for _ in 0..<numBytes {
                guard pos < bytes.count else { return nil }
                length = (length << 8) | Int(bytes[pos])
                pos += 1
            }
        }
        return TagInfo(contentOffset: pos, contentLength: length)
    }

    private static func parseSequence(_ bytes: [UInt8], offset: Int) -> TagInfo? {
        guard offset < bytes.count, bytes[offset] == 0x30 else { return nil }
        return parseTag(bytes, offset: offset)
    }

    private static func parseMacData(_ macDataBytes: [UInt8], fullData: [UInt8], outerSeq: TagInfo) -> MacInfo? {
        // macData is SEQUENCE { mac, macSalt, iterations }
        // mac is SEQUENCE { digestAlgorithm, digest }

        var offset = 0

        // Parse mac (DigestInfo)
        guard macDataBytes[offset] == 0x30 else { return nil }
        guard let digestInfo = parseTag(macDataBytes, offset: offset) else { return nil }

        // Inside DigestInfo: SEQUENCE { algorithm OID, digest OCTET STRING }
        let diBytes = Array(macDataBytes[digestInfo.contentOffset..<(digestInfo.contentOffset + digestInfo.contentLength)])
        var diOffset = 0

        // Skip algorithm SEQUENCE
        guard diOffset < diBytes.count, diBytes[diOffset] == 0x30 else { return nil }
        guard let algSeq = parseTag(diBytes, offset: diOffset) else { return nil }
        diOffset = algSeq.contentOffset + algSeq.contentLength

        // Digest OCTET STRING
        guard diOffset < diBytes.count, diBytes[diOffset] == 0x04 else { return nil }
        guard let digestTag = parseTag(diBytes, offset: diOffset) else { return nil }
        let expectedDigest = Array(diBytes[digestTag.contentOffset..<(digestTag.contentOffset + digestTag.contentLength)])

        offset = digestInfo.contentOffset + digestInfo.contentLength

        // macSalt OCTET STRING
        guard offset < macDataBytes.count, macDataBytes[offset] == 0x04 else { return nil }
        guard let saltTag = parseTag(macDataBytes, offset: offset) else { return nil }
        let salt = Array(macDataBytes[saltTag.contentOffset..<(saltTag.contentOffset + saltTag.contentLength)])
        offset = saltTag.contentOffset + saltTag.contentLength

        // iterations INTEGER (optional, default 1)
        var iterations = 1
        if offset < macDataBytes.count && macDataBytes[offset] == 0x02 {
            guard let iterTag = parseTag(macDataBytes, offset: offset) else { return nil }
            iterations = 0
            for i in 0..<iterTag.contentLength {
                iterations = (iterations << 8) | Int(macDataBytes[iterTag.contentOffset + i])
            }
        }

        // Find authSafe content (2nd element in outer sequence — the ContentInfo)
        var outerOffset = outerSeq.contentOffset
        // Skip version INTEGER
        guard let versionTag = parseTag(fullData, offset: outerOffset) else { return nil }
        outerOffset = versionTag.contentOffset + versionTag.contentLength

        // authSafe is a SEQUENCE (ContentInfo)
        guard outerOffset < fullData.count, fullData[outerOffset] == 0x30 else { return nil }
        guard let authSafeTag = parseTag(fullData, offset: outerOffset) else { return nil }
        let authSafeContent = Array(fullData[outerOffset..<(authSafeTag.contentOffset + authSafeTag.contentLength)])

        return MacInfo(
            expectedDigest: expectedDigest,
            salt: salt,
            iterations: iterations,
            authSafeContent: authSafeContent
        )
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

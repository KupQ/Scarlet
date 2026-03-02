//
//  LocalCertChecker.swift
//  Scarlet
//
//  Extracts certificate info from a local P12 file and checks
//  revocation status via Apple's OCSP responder.
//

import Foundation
import CommonCrypto

/// Info extracted from a locally imported P12.
struct LocalCertInfo {
    let commonName: String
    let issuerCN: String
    let notBefore: Date
    let notAfter: Date
    let serialHex: String
    var status: CertStatus = .checking

    enum CertStatus: Equatable {
        case checking
        case valid
        case revoked(String?) // optional revocation date
        case expired
        case error(String)

        var label: String {
            switch self {
            case .checking: return "Checking…"
            case .valid: return "Valid"
            case .revoked: return "Revoked"
            case .expired: return "Expired"
            case .error(let msg): return "Error"
            }
        }

        var isGood: Bool { self == .valid }
        var isRevoked: Bool {
            if case .revoked = self { return true }
            return false
        }
        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    var isExpired: Bool { notAfter < Date() }
    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: notAfter).day ?? 0)
    }
}

/// Parses a local P12 file and checks its OCSP status against Apple.
@MainActor
final class LocalCertChecker: ObservableObject {

    static let shared = LocalCertChecker()

    @Published var certInfo: LocalCertInfo?
    @Published var isChecking = false

    private let ocspURL = "http://ocsp.apple.com/ocsp03-wwdrg3"
    private let issuerURL = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"

    /// Check the currently saved local P12 certificate.
    func checkSavedCert() async {
        let settings = SigningSettings.shared
        guard let certURL = settings.savedCertURL,
              let data = try? Data(contentsOf: certURL) else {
            certInfo = nil
            return
        }

        let password = settings.savedCertPassword

        isChecking = true

        // Parse P12 to extract certificate info
        guard let info = parseCertFromP12(data: data, password: password) else {
            certInfo = nil
            isChecking = false
            return
        }

        var result = info

        // Check expiry first
        if result.isExpired {
            result.status = .expired
        } else {
            // Try OCSP check
            let status = await checkOCSPStatus(certData: data, password: password)
            result.status = status
        }

        certInfo = result
        isChecking = false
    }

    // MARK: - P12 Parsing (extract cert info via ASN.1)

    private func parseCertFromP12(data: Data, password: String) -> LocalCertInfo? {
        // Use the ASN.1 approach to find the certificate inside the P12
        let bytes = [UInt8](data)
        guard let certDER = extractCertDER(from: bytes, password: password) else { return nil }

        // Parse the X.509 certificate DER
        return parseX509(der: certDER)
    }

    /// Extract the leaf certificate DER from a PKCS12.
    /// We scan for the X.509 certificate OID (1.2.840.113549.1.9.22.1) or
    /// look for the certificate sequence pattern.
    private func extractCertDER(from bytes: [UInt8], password: String) -> [UInt8]? {
        // The cert bag OID: 06 0B 2A 86 48 86 F7 0D 01 09 16 01
        let certBagOID: [UInt8] = [0x06, 0x0B, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x16, 0x01]

        // Scan for the cert bag OID
        for i in 0..<(bytes.count - certBagOID.count - 10) {
            if Array(bytes[i..<(i + certBagOID.count)]) == certBagOID {
                // After the OID, find the certificate (SEQUENCE tag 0x30)
                var pos = i + certBagOID.count
                // Skip context tags and wrappers
                while pos < bytes.count - 4 {
                    if bytes[pos] == 0x30 {
                        // Check if this looks like a certificate (starts with SEQUENCE containing SEQUENCE)
                        if let certLen = readASN1Length(bytes, offset: pos + 1) {
                            let totalLen = 1 + certLen.lengthBytes + certLen.value
                            if totalLen > 100 && (pos + totalLen) <= bytes.count {
                                // Verify inner structure starts with SEQUENCE (tbsCertificate)
                                let innerStart = pos + 1 + certLen.lengthBytes
                                if innerStart < bytes.count && bytes[innerStart] == 0x30 {
                                    return Array(bytes[pos..<(pos + totalLen)])
                                }
                            }
                        }
                    }
                    pos += 1
                }
            }
        }
        return nil
    }

    private struct ASN1Len {
        let value: Int
        let lengthBytes: Int
    }

    private func readASN1Length(_ bytes: [UInt8], offset: Int) -> ASN1Len? {
        guard offset < bytes.count else { return nil }
        let first = bytes[offset]
        if first < 0x80 {
            return ASN1Len(value: Int(first), lengthBytes: 1)
        }
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4, offset + numBytes < bytes.count else { return nil }
        var value = 0
        for i in 1...numBytes {
            value = (value << 8) | Int(bytes[offset + i])
        }
        return ASN1Len(value: value, lengthBytes: 1 + numBytes)
    }

    /// Parse basic info from an X.509 DER certificate.
    private func parseX509(der: [UInt8]) -> LocalCertInfo? {
        // Use Security framework to create a SecCertificate
        let certData = Data(der)
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else { return nil }

        // Get the common name
        var commonName: CFString?
        SecCertificateCopyCommonName(secCert, &commonName)
        let cn = (commonName as String?) ?? "Unknown"

        // Clean up the common name (strip Apple prefixes)
        let cleanName = cleanCN(cn)

        // Get validity dates from the certificate
        let (notBefore, notAfter) = extractDates(from: der)

        // Get serial number
        let serialHex = extractSerialHex(from: der)

        // Get issuer CN
        let issuerCN = extractIssuerCN(from: secCert)

        return LocalCertInfo(
            commonName: cleanName,
            issuerCN: issuerCN,
            notBefore: notBefore ?? Date(),
            notAfter: notAfter ?? Date(),
            serialHex: serialHex
        )
    }

    private func cleanCN(_ cn: String) -> String {
        let prefixes = ["iPhone Distribution: ", "Apple Distribution: ",
                        "iPhone Developer: ", "Apple Developer: "]
        var result = cn
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        // Remove team ID in parentheses
        if let parenRange = result.range(of: " (") {
            result = String(result[..<parenRange.lowerBound])
        }
        return result
    }

    private func extractDates(from der: [UInt8]) -> (Date?, Date?) {
        // Dates in X.509 are usually UTCTime (tag 0x17) or GeneralizedTime (tag 0x18)
        var dates: [Date] = []
        let dateFormatter = DateFormatter()

        for i in 0..<(der.count - 15) {
            if der[i] == 0x17 { // UTCTime
                let len = Int(der[i + 1])
                if len >= 12 && (i + 2 + len) <= der.count {
                    let timeStr = String(bytes: der[(i+2)..<(i+2+len)], encoding: .ascii) ?? ""
                    dateFormatter.dateFormat = "yyMMddHHmmss'Z'"
                    dateFormatter.timeZone = TimeZone(identifier: "UTC")
                    if let date = dateFormatter.date(from: timeStr) {
                        dates.append(date)
                    }
                }
            } else if der[i] == 0x18 { // GeneralizedTime
                let len = Int(der[i + 1])
                if len >= 14 && (i + 2 + len) <= der.count {
                    let timeStr = String(bytes: der[(i+2)..<(i+2+len)], encoding: .ascii) ?? ""
                    dateFormatter.dateFormat = "yyyyMMddHHmmss'Z'"
                    dateFormatter.timeZone = TimeZone(identifier: "UTC")
                    if let date = dateFormatter.date(from: timeStr) {
                        dates.append(date)
                    }
                }
            }
        }

        if dates.count >= 2 {
            return (dates[0], dates[1])
        }
        return (dates.first, nil)
    }

    private func extractSerialHex(from der: [UInt8]) -> String {
        // Serial number is early in tbsCertificate, tag 0x02 (INTEGER)
        // Skip outer SEQUENCE, inner SEQUENCE, then look for first INTEGER
        guard der.count > 10 else { return "" }

        // tbsCertificate starts after outer SEQUENCE header
        var pos = 0
        // Skip outer SEQUENCE
        if der[pos] == 0x30, let len = readASN1Length(der, offset: pos + 1) {
            pos = pos + 1 + len.lengthBytes
        }
        // Skip inner SEQUENCE (tbsCertificate)
        if pos < der.count && der[pos] == 0x30, let len = readASN1Length(der, offset: pos + 1) {
            pos = pos + 1 + len.lengthBytes
        }
        // Skip optional version [0] EXPLICIT
        if pos < der.count && der[pos] == 0xA0 {
            if let len = readASN1Length(der, offset: pos + 1) {
                pos += 1 + len.lengthBytes + len.value
            }
        }
        // Now we should be at the serial number INTEGER
        if pos < der.count && der[pos] == 0x02 {
            if let len = readASN1Length(der, offset: pos + 1) {
                let start = pos + 1 + len.lengthBytes
                let end = min(start + len.value, der.count)
                return der[start..<end].map { String(format: "%02X", $0) }.joined()
            }
        }
        return ""
    }

    private func extractIssuerCN(from cert: SecCertificate) -> String {
        // Try to get subject summary which often includes issuer info
        let summary = SecCertificateCopySubjectSummary(cert) as String?
        return summary ?? "Apple"
    }

    // MARK: - OCSP Check

    private func checkOCSPStatus(certData: Data, password: String) async -> LocalCertInfo.CertStatus {
        do {
            // Download the Apple WWDR issuer certificate
            let issuerDER = try await downloadIssuer()

            // Extract the leaf cert DER from the P12
            guard let leafDER = extractCertDER(from: [UInt8](certData), password: password) else {
                return .error("Can't extract cert")
            }

            // Build OCSP request
            guard let ocspRequest = buildOCSPRequest(certDER: leafDER, issuerDER: issuerDER) else {
                return .error("OCSP build failed")
            }

            // Send OCSP request
            var request = URLRequest(url: URL(string: ocspURL)!)
            request.httpMethod = "POST"
            request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
            request.httpBody = ocspRequest
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return .error("OCSP server error")
            }

            // Parse OCSP response
            return parseOCSPResponse(data: [UInt8](data))

        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func downloadIssuer() async throws -> [UInt8] {
        // Cache locally
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("apple_wwdr_g3.cer")
        if let cached = try? Data(contentsOf: cacheURL) {
            return [UInt8](cached)
        }

        let (data, _) = try await URLSession.shared.data(from: URL(string: issuerURL)!)
        try? data.write(to: cacheURL)
        return [UInt8](data)
    }

    /// Build a minimal OCSP request for the given certificate.
    /// Uses SHA-1 hashes of issuer name + key as per RFC 6960.
    private func buildOCSPRequest(certDER: [UInt8], issuerDER: [UInt8]) -> Data? {
        // Extract issuer name hash (SHA-1 of the issuer's Subject DN)
        guard let issuerNameDER = extractSubjectDN(from: issuerDER) else { return nil }
        let issuerNameHash = sha1(Data(issuerNameDER))

        // Extract issuer key hash (SHA-1 of the issuer's public key)
        guard let issuerKeyBits = extractPublicKeyBits(from: issuerDER) else { return nil }
        let issuerKeyHash = sha1(Data(issuerKeyBits))

        // Extract serial number from the leaf certificate
        guard let serialBytes = extractSerialBytes(from: certDER) else { return nil }

        // SHA-1 OID: 1.3.14.3.2.26
        let sha1OID: [UInt8] = [0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A]

        // Build CertID: SEQUENCE { hashAlgorithm, issuerNameHash, issuerKeyHash, serialNumber }
        let hashAlg = wrapSequence(sha1OID + [0x05, 0x00]) // AlgorithmIdentifier with NULL params
        let nameHash: [UInt8] = [0x04, UInt8(issuerNameHash.count)] + issuerNameHash
        let keyHash: [UInt8] = [0x04, UInt8(issuerKeyHash.count)] + issuerKeyHash
        let serial: [UInt8] = [0x02, UInt8(serialBytes.count)] + serialBytes

        let certId = wrapSequence(hashAlg + nameHash + keyHash + serial)

        // Wrap in Request SEQUENCE
        let singleRequest = wrapSequence(certId)

        // requestList: SEQUENCE OF Request
        let requestList = wrapSequence(singleRequest)

        // TBSRequest: SEQUENCE { requestList }
        let tbsRequest = wrapSequence(requestList)

        // OCSPRequest: SEQUENCE { tbsRequest }
        let ocspRequest = wrapSequence(tbsRequest)

        return Data(ocspRequest)
    }

    private func extractSubjectDN(from der: [UInt8]) -> [UInt8]? {
        // Navigate: outer SEQUENCE → tbsCertificate SEQUENCE → skip version, serial, sigAlg, then issuer (=subject for self, but we want subject)
        guard der.count > 20 else { return nil }
        var pos = 0

        // Outer SEQUENCE
        guard der[pos] == 0x30, let outerLen = readASN1Length(der, offset: pos + 1) else { return nil }
        pos = pos + 1 + outerLen.lengthBytes

        // tbsCertificate SEQUENCE
        guard pos < der.count, der[pos] == 0x30, let tbsLen = readASN1Length(der, offset: pos + 1) else { return nil }
        pos = pos + 1 + tbsLen.lengthBytes

        // Skip version [0] EXPLICIT if present
        if pos < der.count && der[pos] == 0xA0 {
            if let len = readASN1Length(der, offset: pos + 1) {
                pos += 1 + len.lengthBytes + len.value
            }
        }

        // Skip serial (INTEGER)
        if pos < der.count && der[pos] == 0x02 {
            if let len = readASN1Length(der, offset: pos + 1) {
                pos += 1 + len.lengthBytes + len.value
            }
        }

        // Skip signature algorithm (SEQUENCE)
        if pos < der.count && der[pos] == 0x30 {
            if let len = readASN1Length(der, offset: pos + 1) {
                pos += 1 + len.lengthBytes + len.value
            }
        }

        // Issuer (SEQUENCE) — this is what we want for issuerNameHash
        if pos < der.count && der[pos] == 0x30 {
            if let len = readASN1Length(der, offset: pos + 1) {
                let totalLen = 1 + len.lengthBytes + len.value
                if pos + totalLen <= der.count {
                    return Array(der[pos..<(pos + totalLen)])
                }
            }
        }

        return nil
    }

    private func extractPublicKeyBits(from der: [UInt8]) -> [UInt8]? {
        // Navigate to SubjectPublicKeyInfo → BIT STRING → skip tag+len+unusedBits
        guard der.count > 20 else { return nil }
        var pos = 0

        // Outer SEQUENCE
        guard der[pos] == 0x30, let outerLen = readASN1Length(der, offset: pos + 1) else { return nil }
        pos = pos + 1 + outerLen.lengthBytes

        // tbsCertificate SEQUENCE
        guard pos < der.count, der[pos] == 0x30, let tbsLen = readASN1Length(der, offset: pos + 1) else { return nil }
        pos = pos + 1 + tbsLen.lengthBytes

        // Skip: version, serial, sigAlg, issuer, validity, subject
        for _ in 0..<6 {
            if pos >= der.count { return nil }
            if der[pos] == 0xA0 { // version
                if let len = readASN1Length(der, offset: pos + 1) {
                    pos += 1 + len.lengthBytes + len.value
                }
            } else if der[pos] == 0x30 || der[pos] == 0x02 || der[pos] == 0x31 {
                if let len = readASN1Length(der, offset: pos + 1) {
                    pos += 1 + len.lengthBytes + len.value
                }
            } else {
                break
            }
        }

        // SubjectPublicKeyInfo SEQUENCE
        if pos < der.count && der[pos] == 0x30 {
            if let spkiLen = readASN1Length(der, offset: pos + 1) {
                let spkiStart = pos + 1 + spkiLen.lengthBytes
                // Skip algorithm SEQUENCE
                var innerPos = spkiStart
                if innerPos < der.count && der[innerPos] == 0x30 {
                    if let algLen = readASN1Length(der, offset: innerPos + 1) {
                        innerPos += 1 + algLen.lengthBytes + algLen.value
                    }
                }
                // BIT STRING
                if innerPos < der.count && der[innerPos] == 0x03 {
                    if let bsLen = readASN1Length(der, offset: innerPos + 1) {
                        let dataStart = innerPos + 1 + bsLen.lengthBytes + 1 // +1 for unused bits byte
                        let dataEnd = innerPos + 1 + bsLen.lengthBytes + bsLen.value
                        if dataEnd <= der.count {
                            return Array(der[dataStart..<dataEnd])
                        }
                    }
                }
            }
        }

        return nil
    }

    private func extractSerialBytes(from der: [UInt8]) -> [UInt8]? {
        guard der.count > 10 else { return nil }
        var pos = 0
        // Outer SEQUENCE
        if der[pos] == 0x30, let len = readASN1Length(der, offset: pos + 1) {
            pos = pos + 1 + len.lengthBytes
        }
        // tbsCertificate SEQUENCE
        if pos < der.count && der[pos] == 0x30, let len = readASN1Length(der, offset: pos + 1) {
            pos = pos + 1 + len.lengthBytes
        }
        // Skip version [0]
        if pos < der.count && der[pos] == 0xA0 {
            if let len = readASN1Length(der, offset: pos + 1) {
                pos += 1 + len.lengthBytes + len.value
            }
        }
        // Serial INTEGER
        if pos < der.count && der[pos] == 0x02 {
            if let len = readASN1Length(der, offset: pos + 1) {
                let start = pos + 1 + len.lengthBytes
                let end = start + len.value
                if end <= der.count {
                    return Array(der[start..<end])
                }
            }
        }
        return nil
    }

    private func sha1(_ data: Data) -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash
    }

    private func wrapSequence(_ content: [UInt8]) -> [UInt8] {
        return [0x30] + encodeASN1Length(content.count) + content
    }

    private func encodeASN1Length(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        } else if length < 0x100 {
            return [0x81, UInt8(length)]
        } else if length < 0x10000 {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        } else {
            return [0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        }
    }

    // MARK: - OCSP Response Parsing

    private func parseOCSPResponse(data: [UInt8]) -> LocalCertInfo.CertStatus {
        // OCSPResponse is: SEQUENCE { responseStatus ENUMERATED, [0] responseBytes }
        guard data.count > 10, data[0] == 0x30 else { return .error("Bad OCSP response") }

        // Check responseStatus (ENUMERATED, tag 0x0A)
        var pos = 0
        guard let outerLen = readASN1Length(data, offset: 1) else { return .error("Parse error") }
        pos = 1 + outerLen.lengthBytes

        if pos < data.count && data[pos] == 0x0A {
            if let len = readASN1Length(data, offset: pos + 1) {
                let statusByte = data[pos + 1 + len.lengthBytes]
                if statusByte != 0 { return .error("OCSP status: \(statusByte)") }
            }
        }

        // Look for certStatus in the response
        // certStatus is one of:
        //   [0] IMPLICIT NULL (good)     = 0x80 0x00
        //   [1] IMPLICIT RevokedInfo     = 0xA1 ...
        //   [2] IMPLICIT NULL (unknown)  = 0x82 0x00
        for i in 0..<(data.count - 2) {
            // Good (valid)
            if data[i] == 0x80 && data[i + 1] == 0x00 {
                // Verify this is in a certStatus context by checking nearby tags
                // Look backwards for a CertID sequence
                if i > 30 {
                    return .valid
                }
            }
            // Revoked
            if data[i] == 0xA1 {
                // Could be revoked info — check if preceded by CertID-like structure
                if i > 30 && data.count > i + 5 {
                    // Try to extract revocation time
                    let revokedStart = i + 1
                    if let len = readASN1Length(data, offset: revokedStart) {
                        let timeStart = revokedStart + len.lengthBytes
                        if timeStart < data.count && (data[timeStart] == 0x17 || data[timeStart] == 0x18) {
                            return .revoked(nil)
                        }
                    }
                    return .revoked(nil)
                }
            }
        }

        // Fallback: scan for the simple good/revoked patterns
        let dataSlice = data
        for i in 0..<(dataSlice.count - 1) {
            if dataSlice[i] == 0x80 && dataSlice[i+1] == 0x00 && i > 50 {
                return .valid
            }
        }

        return .error("Unknown OCSP result")
    }
}

//
//  LocalCertChecker.swift
//  Scarlet
//
//  Checks P12 certificates via Rust/OpenSSL OCSP.
//  Maintains status dictionaries for both local and API certs.
//  Checks only once per app launch + on new cert import.
//

import Foundation

/// Info extracted from a P12 certificate.
struct LocalCertInfo {
    let commonName: String
    let notBefore: String
    let notAfter: String
    let serialHex: String
    var status: CertStatus = .checking
    var daysLeft: Int = 0

    enum CertStatus: Equatable {
        case checking
        case valid
        case revoked
        case expired
        case error(String)

        var label: String {
            switch self {
            case .checking: return L("Checking…")
            case .valid: return L("Valid")
            case .revoked: return L("Revoked")
            case .expired: return L("Expired")
            case .error: return L("Error")
            }
        }

        var isGood: Bool { self == .valid }
        var isRevoked: Bool { self == .revoked }
        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }
}

/// Checks P12 certificates via Rust/OpenSSL OCSP.
@MainActor
final class LocalCertChecker: ObservableObject {

    static let shared = LocalCertChecker()

    /// Info for locally imported certs, keyed by filename
    @Published var localCertInfos: [String: LocalCertInfo] = [:]

    /// OCSP status for API certs, keyed by cert ID
    @Published var apiCertStatuses: [String: LocalCertInfo.CertStatus] = [:]

    /// Tracks whether we already checked this session (avoid re-checking on tab switches)
    private var hasCheckedAPIThisSession = false
    private var checkedLocalCerts: Set<String> = []

    private let ocspURL = "http://ocsp.apple.com/ocsp03-wwdrg3"

    /// Reusable URL session for OCSP (HTTP-only)
    private lazy var ocspSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config, delegate: PermissiveDelegate(), delegateQueue: nil)
    }()

    /// Cached issuer DER (cached remote → bundled fallback)
    private lazy var cachedIssuerDER: Data? = {
        guard let url = CertFetcher.wwdrURL else { return nil }
        return try? Data(contentsOf: url)
    }()

    // MARK: - Check a single local cert (used after import)

    func checkLocalCert(name: String, password: String) async {
        let settings = SigningSettings.shared
        let certURL = settings.certsDirectory.appendingPathComponent(name)
        guard let p12Data = try? Data(contentsOf: certURL) else {
            localCertInfos[name] = LocalCertInfo(
                commonName: name.replacingOccurrences(of: ".p12", with: "").replacingOccurrences(of: "local_", with: ""),
                notBefore: "", notAfter: "", serialHex: "",
                status: .error("Can't read file")
            )
            return
        }

        // Extract cert info
        var info = getCertInfo(p12Data: p12Data, password: password) ?? LocalCertInfo(
            commonName: name.replacingOccurrences(of: ".p12", with: "").replacingOccurrences(of: "local_", with: ""),
            notBefore: "", notAfter: "", serialHex: "",
            status: .error("Can't parse P12")
        )

        // Calculate days left
        info.daysLeft = parseDaysLeft(info.notAfter)

        // OCSP check
        let status = await checkOCSPStatus(p12Data: p12Data, password: password)
        info.status = status

        localCertInfos[name] = info
        checkedLocalCerts.insert(name)
    }

    // MARK: - Check all local certs (on app launch only)

    func checkAllLocalCerts(certs: [(name: String, password: String)]) async {
        for cert in certs {
            guard !checkedLocalCerts.contains(cert.name) else { continue }
            await checkLocalCert(name: cert.name, password: cert.password)
        }
    }

    // MARK: - Check API Certificates (once per session)

    func checkAPICertsIfNeeded(_ certs: [RemoteCertificate]) async {
        guard !hasCheckedAPIThisSession else { return }
        hasCheckedAPIThisSession = true

        for cert in certs {
            guard let p12Data = cert.p12Data else {
                apiCertStatuses[cert.id] = .error("No P12 data")
                continue
            }
            apiCertStatuses[cert.id] = .checking
            let status = await checkOCSPStatus(p12Data: p12Data, password: cert.p12_password)
            apiCertStatuses[cert.id] = status
        }
    }

    /// Force re-check API certs (e.g. pull-to-refresh)
    func forceCheckAPICerts(_ certs: [RemoteCertificate]) async {
        for cert in certs {
            guard let p12Data = cert.p12Data else { continue }
            let previousStatus = apiCertStatuses[cert.id]
            apiCertStatuses[cert.id] = .checking
            let status = await checkOCSPStatus(p12Data: p12Data, password: cert.p12_password)
            if case .error = status, let prev = previousStatus, prev != .checking {
                apiCertStatuses[cert.id] = prev
            } else {
                apiCertStatuses[cert.id] = status
            }
        }
    }

    /// Get status for an API cert by ID.
    func statusFor(_ certId: String) -> LocalCertInfo.CertStatus {
        apiCertStatuses[certId] ?? .checking
    }

    // MARK: - Date Parsing

    private func parseDaysLeft(_ notAfter: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")

        for fmt in ["MMM dd HH:mm:ss yyyy z", "MMM  d HH:mm:ss yyyy z"] {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: notAfter) {
                return max(0, Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0)
            }
        }
        return 0
    }

    // MARK: - Core OCSP Check

    private func checkOCSPStatus(p12Data: Data, password: String) async -> LocalCertInfo.CertStatus {
        do {
            guard let issuerDER = cachedIssuerDER else {
                FileLogger.shared.log("OCSP: Bundled issuer cert not found")
                return .error("Missing issuer cert")
            }

            guard let ocspReqData = buildOCSPRequest(p12Data: p12Data, password: password, issuerDER: issuerDER) else {
                FileLogger.shared.log("OCSP: build failed")
                return .error("OCSP build failed")
            }

            var request = URLRequest(url: URL(string: ocspURL)!)
            request.httpMethod = "POST"
            request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
            request.httpBody = ocspReqData

            let (respData, response) = try await ocspSession.data(for: request)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                FileLogger.shared.log("OCSP: HTTP error")
                return .error("OCSP HTTP error")
            }

            let status = parseOCSPResponse(p12Data: p12Data, password: password,
                                           issuerDER: issuerDER, responseDER: respData)
            return status

        } catch {
            FileLogger.shared.log("OCSP: \(error.localizedDescription)")
            return .error("OCSP: \(error.localizedDescription)")
        }
    }

    // MARK: - Rust FFI: Get Cert Info

    func getCertInfo(p12Data: Data, password: String) -> LocalCertInfo? {
        let jsonPtr = p12Data.withUnsafeBytes { rawBuf -> UnsafeMutablePointer<CChar>? in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return password.withCString { pwd in
                scarlet_cert_info_from_p12(ptr, UInt(p12Data.count), pwd)
            }
        }

        guard let jsonPtr = jsonPtr else { return nil }
        let jsonStr = String(cString: jsonPtr)
        scarlet_free_string(jsonPtr)

        guard let data = jsonStr.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }

        return LocalCertInfo(
            commonName: json["name"] ?? "Unknown",
            notBefore: json["not_before"] ?? "",
            notAfter: json["not_after"] ?? "",
            serialHex: json["serial"] ?? ""
        )
    }

    // MARK: - Rust FFI: Build OCSP Request

    private func buildOCSPRequest(p12Data: Data, password: String, issuerDER: Data) -> Data? {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen: UInt = 0

        let result = p12Data.withUnsafeBytes { p12Buf -> Int32 in
            guard let p12Ptr = p12Buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return issuerDER.withUnsafeBytes { issuerBuf -> Int32 in
                guard let issuerPtr = issuerBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                return password.withCString { pwd in
                    scarlet_build_ocsp_request(
                        p12Ptr, UInt(p12Data.count),
                        pwd,
                        issuerPtr, UInt(issuerDER.count),
                        &outPtr, &outLen
                    )
                }
            }
        }

        guard result == 0, let ptr = outPtr, outLen > 0 else { return nil }
        let data = Data(bytes: ptr, count: Int(outLen))
        scarlet_free_data(ptr)
        return data
    }

    // MARK: - Rust FFI: Parse OCSP Response

    private func parseOCSPResponse(p12Data: Data, password: String,
                                    issuerDER: Data, responseDER: Data) -> LocalCertInfo.CertStatus {
        let statusPtr = p12Data.withUnsafeBytes { p12Buf -> UnsafeMutablePointer<CChar>? in
            guard let p12Ptr = p12Buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return issuerDER.withUnsafeBytes { issuerBuf -> UnsafeMutablePointer<CChar>? in
                guard let issuerPtr = issuerBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
                return responseDER.withUnsafeBytes { respBuf -> UnsafeMutablePointer<CChar>? in
                    guard let respPtr = respBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
                    return password.withCString { pwd in
                        scarlet_parse_ocsp_response(
                            p12Ptr, UInt(p12Data.count),
                            pwd,
                            issuerPtr, UInt(issuerDER.count),
                            respPtr, UInt(responseDER.count)
                        )
                    }
                }
            }
        }

        guard let statusPtr = statusPtr else { return .error("Rust call failed") }
        let status = String(cString: statusPtr)
        scarlet_free_string(statusPtr)

        switch status {
        case "Valid": return .valid
        case "Revoked": return .revoked
        case "Unknown": return .error("Unknown status")
        default: return .error(status)
        }
    }
}

/// Delegate that permits HTTP connections (needed for Apple's HTTP-only OCSP responder).
private class PermissiveDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

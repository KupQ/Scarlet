//
//  LocalCertChecker.swift
//  Scarlet
//
//  Checks locally imported P12 certificates using the Rust/OpenSSL
//  OCSP checker (same logic as the server). Rust handles crypto,
//  Swift handles the HTTP call to Apple's OCSP responder.
//

import Foundation

/// Info extracted from a locally imported P12.
struct LocalCertInfo {
    let commonName: String
    let notBefore: String
    let notAfter: String
    let serialHex: String
    var status: CertStatus = .checking

    enum CertStatus: Equatable {
        case checking
        case valid
        case revoked
        case expired
        case error(String)

        var label: String {
            switch self {
            case .checking: return "Checking…"
            case .valid: return "Valid"
            case .revoked: return "Revoked"
            case .expired: return "Expired"
            case .error: return "Error"
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

/// Parses a local P12 file via Rust/OpenSSL and checks OCSP status.
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
              let p12Data = try? Data(contentsOf: certURL) else {
            certInfo = nil
            return
        }

        let password = settings.savedCertPassword

        isChecking = true

        // Step 1: Extract cert info via Rust/OpenSSL
        guard let info = getCertInfo(p12Data: p12Data, password: password) else {
            certInfo = LocalCertInfo(
                commonName: settings.savedCertName?.replacingOccurrences(of: ".p12", with: "") ?? "Unknown",
                notBefore: "", notAfter: "", serialHex: "",
                status: .error("Can't parse P12")
            )
            isChecking = false
            return
        }

        var result = info

        // Step 2: Check OCSP status via Rust + Apple HTTP
        let status = await checkOCSP(p12Data: p12Data, password: password)
        result.status = status

        certInfo = result
        isChecking = false
    }

    // MARK: - Rust FFI: Get Cert Info

    private func getCertInfo(p12Data: Data, password: String) -> LocalCertInfo? {
        let jsonPtr = p12Data.withUnsafeBytes { rawBuf -> UnsafeMutablePointer<CChar>? in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return password.withCString { pwd in
                scarlet_cert_info_from_p12(ptr, UInt(p12Data.count), pwd)
            }
        }

        guard let jsonPtr = jsonPtr else { return nil }
        let jsonStr = String(cString: jsonPtr)
        scarlet_free_string(jsonPtr)

        // Parse the JSON manually (simple format)
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

    // MARK: - OCSP Check (Rust crypto + Swift HTTP)

    private func checkOCSP(p12Data: Data, password: String) async -> LocalCertInfo.CertStatus {
        do {
            // 1. Download Apple WWDR issuer cert
            let issuerDER = try await downloadIssuer()

            // 2. Build OCSP request via Rust/OpenSSL
            guard let ocspReqData = buildOCSPRequest(p12Data: p12Data, password: password, issuerDER: issuerDER) else {
                return .error("OCSP build failed")
            }

            // 3. Send OCSP request to Apple via Swift HTTP
            var request = URLRequest(url: URL(string: ocspURL)!)
            request.httpMethod = "POST"
            request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
            request.httpBody = ocspReqData
            request.timeoutInterval = 10

            let (respData, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return .error("OCSP HTTP error")
            }

            // 4. Parse OCSP response via Rust/OpenSSL
            let status = parseOCSPResponse(p12Data: p12Data, password: password,
                                           issuerDER: issuerDER, responseDER: respData)
            return status

        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func downloadIssuer() async throws -> Data {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("apple_wwdr_g3.cer")
        if let cached = try? Data(contentsOf: cacheURL) {
            return cached
        }
        let (data, _) = try await URLSession.shared.data(from: URL(string: issuerURL)!)
        try? data.write(to: cacheURL)
        return data
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

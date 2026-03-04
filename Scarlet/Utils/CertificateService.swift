//
//  CertificateService.swift
//  Scarlet
//
//  Fetches signing certificates from the remote API using
//  the device UDID extracted from embedded.mobileprovision.
//

import Foundation

// MARK: - API Response Model

/// Represents a certificate returned by the API.
struct RemoteCertificate: Identifiable, Codable {
    let id: String
    let name: String
    let pname: String
    let p12: String                // base64 P12
    let p12_password: String
    let mobileprovision: String    // base64 mobileprovision
    let devp12: String?            // optional dev P12
    let devmp: String?             // optional dev mobileprovision
    let dev_name: String?          // optional dev cert name
    let expire_time: TimeInterval
    let plan_selected: String?
    let cert_type: String?
    let udid: String?

    var isExpired: Bool {
        Date(timeIntervalSince1970: expire_time) < Date()
    }

    var expiresDate: Date {
        Date(timeIntervalSince1970: expire_time)
    }

    /// Decoded P12 data.
    var p12Data: Data? {
        Data(base64Encoded: p12)
    }

    /// Decoded mobileprovision data.
    var provisionData: Data? {
        Data(base64Encoded: mobileprovision)
    }

    /// Decoded developer P12 data (if available).
    var devP12Data: Data? {
        devp12.flatMap { Data(base64Encoded: $0) }
    }

    /// Checks if the mobileprovision has PPQCheck enabled.
    /// If `<key>PPQCheck</key><true/>` is in the plist → PPQ enabled.
    /// If the key is absent → PPQless.
    var isPPQEnabled: Bool {
        guard let data = Data(base64Encoded: mobileprovision),
              let content = String(data: data, encoding: .isoLatin1) else { return false }
        // Extract embedded plist XML from CMS/PKCS7 envelope
        guard let start = content.range(of: "<?xml"),
              let end = content.range(of: "</plist>") else { return false }
        let xml = String(content[start.lowerBound...end.upperBound])
        return xml.contains("PPQCheck") && xml.contains("<true/>")
    }

    /// Creates a development variant using devp12 and devmp.
    var devVariant: RemoteCertificate {
        RemoteCertificate(
            id: "DEV-\(id)",
            name: dev_name ?? "\(name) (Dev)",
            pname: pname,
            p12: devp12 ?? p12,
            p12_password: p12_password,
            mobileprovision: devmp ?? mobileprovision,
            devp12: nil,
            devmp: nil,
            dev_name: nil,
            expire_time: expire_time,
            plan_selected: plan_selected,
            cert_type: "IOS_DEVELOPMENT",
            udid: udid
        )
    }
}

// MARK: - Certificate Service

/// Manages fetching certificates from the API for the current device.
@MainActor
final class CertificateService: ObservableObject {

    static let shared = CertificateService()

    private let apiURL = "https://api.nekoo.eu.org/certificate/public"

    @Published var certificates: [RemoteCertificate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var debugInfo: String = ""

    /// The device UDID extracted from embedded.mobileprovision
    private(set) var deviceUDID: String?

    private init() {
        deviceUDID = Self.getDeviceUDID()
    }

    // MARK: - UDID Extraction

    /// Gets the actual device UDID using MobileGestalt private API.
    /// Falls back to embedded.mobileprovision if unavailable.
    static func getDeviceUDID() -> String? {

        // Try MobileGestalt private API first (real device UDID)
        if let udid = mgCopyAnswer("UniqueDeviceID") {
            return udid
        }

        // Fallback: try embedded.mobileprovision
        if let udid = extractUDIDFromProvision() {
            return udid
        }

        return nil
    }

    /// Uses MobileGestalt MGCopyAnswer to query device properties.
    private static func mgCopyAnswer(_ key: String) -> String? {
        guard let gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY) else { return nil }
        defer { dlclose(gestalt) }

        typealias MGCopyAnswerFunc = @convention(c) (CFString) -> CFTypeRef?
        guard let sym = dlsym(gestalt, "MGCopyAnswer") else { return nil }
        let fn = unsafeBitCast(sym, to: MGCopyAnswerFunc.self)
        guard let result = fn(key as CFString) else { return nil }
        return result as? String
    }

    /// Fallback: extracts UDID from embedded.mobileprovision.
    static func extractUDIDFromProvision() -> String? {

        // Direct path — Bundle.main.url(forResource:) doesn't find root-level files reliably
        let provisionPath = Bundle.main.bundlePath + "/embedded.mobileprovision"
        let fm = FileManager.default

        guard fm.fileExists(atPath: provisionPath) else {
            // List bundle root to debug
            let contents = (try? fm.contentsOfDirectory(atPath: Bundle.main.bundlePath)) ?? []
            return nil
        }

        guard let data = fm.contents(atPath: provisionPath) else {
            return nil
        }


        // mobileprovision is CMS/PKCS7 binary; use isoLatin1 to handle all byte values
        guard let text = String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        guard let xmlStart = text.range(of: "<?xml"),
              let xmlEnd = text.range(of: "</plist>") else {
            return nil
        }

        let xmlString = String(text[xmlStart.lowerBound...xmlEnd.upperBound])
        guard let xmlData = xmlString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: xmlData,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }

        // ProvisionedDevices contains the UDIDs registered on this profile
        if let devices = plist["ProvisionedDevices"] as? [String] {
            if let first = devices.first {
                return first
            }
        }

        return nil
    }

    // MARK: - Fetch Certificates

    /// Fetches certificates from the API for the device UDID.
    func fetchCertificates() async {
        guard let udid = deviceUDID else {
            errorMessage = "Could not determine device UDID"
            return
        }

        isLoading = true
        errorMessage = nil


        do {
            var request = URLRequest(
                url: URL(string: "\(apiURL)?udid=\(udid)")!
            )
            request.httpMethod = "GET"
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CertError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw CertError.httpError(httpResponse.statusCode)
            }

            // Decode each entry individually to skip failures
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw CertError.invalidResponse
            }

            var debugLines: [String] = ["API: \(jsonArray.count) entries"]

            var all: [RemoteCertificate] = []
            var failCount = 0
            for (index, _) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonArray[index])
                    let cert = try JSONDecoder().decode(RemoteCertificate.self, from: itemData)
                    all.append(cert)
                    debugLines.append("[\(index)] \(cert.name) ✓")

                    // Split dev variant if devp12 exists
                    if cert.devp12 != nil {
                        all.append(cert.devVariant)
                        debugLines.append("[\(index)] +dev ✓")
                    }
                } catch {
                    failCount += 1
                    let errMsg = "\(error)"
                    debugLines.append("[\(index)] FAIL: \(errMsg.prefix(80))")
                }
            }

            certificates = all

            if failCount > 0 {
                errorMessage = "\(failCount) entry(ies) failed to decode. Got \(all.count)/\(jsonArray.count + all.count - jsonArray.count)"
            }
            debugInfo = debugLines.joined(separator: "\n")

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Saves a remote certificate's P12 and mobileprovision to disk
    /// and configures SigningSettings to use them.
    func useCertificate(_ cert: RemoteCertificate) {
        let settings = SigningSettings.shared

        // Save P12
        guard let p12Data = cert.p12Data else {
            return
        }
        let p12Name = "\(cert.id).p12"
        let p12URL = settings.certsDirectory.appendingPathComponent(p12Name)
        try? p12Data.write(to: p12URL)

        // Save mobileprovision
        guard let provData = cert.provisionData else {
            return
        }
        let provName = "\(cert.id).mobileprovision"
        let provURL = settings.certsDirectory.appendingPathComponent(provName)
        try? provData.write(to: provURL)

        // Configure signing settings
        settings.savedCertName = p12Name
        settings.savedCertPassword = cert.p12_password
        settings.savedProfileName = provName

    }

    private enum CertError: LocalizedError {
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid server response"
            case .httpError(let code): return "HTTP \(code)"
            }
        }
    }
}

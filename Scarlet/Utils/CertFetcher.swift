//
//  CertFetcher.swift
//  Scarlet
//
//  Downloads server.p12 and AppleWWDRCAG3.cer from
//  remote URLs and caches them locally. Bundled copies
//  serve as a fallback if the network is unavailable.
//

import Foundation

enum CertFetcher {

    // MARK: - Remote URLs

    private static let p12RemoteURL  = URL(string: "https://nekoo.eu.org/scarlet/server.p12")!
    private static let wwdrRemoteURL = URL(string: "https://nekoo.eu.org/scarlet/AppleWWDRCAG3.cer")!

    // MARK: - Local cache paths (Documents/Certs/)

    private static let certsDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Certs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var cachedP12URL: URL  { certsDir.appendingPathComponent("server.p12") }
    static var cachedWWDRURL: URL { certsDir.appendingPathComponent("AppleWWDRCAG3.cer") }

    // MARK: - Public: resolve best available cert

    /// Returns the best available server.p12 URL (cached → bundled).
    static var p12URL: URL? {
        if FileManager.default.fileExists(atPath: cachedP12URL.path) {
            return cachedP12URL
        }
        return Bundle.main.url(forResource: "server", withExtension: "p12")
    }

    /// Returns the best available AppleWWDRCAG3.cer URL (cached → bundled).
    static var wwdrURL: URL? {
        if FileManager.default.fileExists(atPath: cachedWWDRURL.path) {
            return cachedWWDRURL
        }
        return Bundle.main.url(forResource: "AppleWWDRCAG3", withExtension: "cer")
    }

    // MARK: - Fetch on launch

    /// Downloads both certs in the background. Safe to call on every launch.
    static func refreshAll() {
        download(from: p12RemoteURL, to: cachedP12URL, label: "server.p12")
        download(from: wwdrRemoteURL, to: cachedWWDRURL, label: "AppleWWDRCAG3.cer")
    }

    // MARK: - Private

    private static func download(from remote: URL, to local: URL, label: String) {
        let task = URLSession.shared.downloadTask(with: remote) { tmpURL, response, error in
            guard let tmpURL,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                FileLogger.shared.log("CertFetcher: \(label) fetch failed – \(error?.localizedDescription ?? "HTTP error")")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: local.path) {
                    try FileManager.default.removeItem(at: local)
                }
                try FileManager.default.moveItem(at: tmpURL, to: local)
                FileLogger.shared.log("CertFetcher: \(label) updated (\((try? Data(contentsOf: local))?.count ?? 0) bytes)")
            } catch {
                FileLogger.shared.log("CertFetcher: \(label) save failed – \(error.localizedDescription)")
            }
        }
        task.resume()
    }
}

import Foundation
import SwiftUI

// MARK: - Models

struct RepoManifest: Codable {
    let name: String
    let identifier: String?
    let sourceURL: String?
    let iconURL: String?
    let apps: [RepoApp]
}

struct RepoApp: Codable, Identifiable {
    let name: String
    let bundleID: String
    let version: String
    let size: Int?
    let downloadURL: String
    let localizedDescription: String?
    let iconURL: String?
    let appUpdateTime: String?

    var id: String { bundleID + (version) }

    var sizeString: String {
        guard let s = size else { return "—" }
        if s > 1_000_000_000 { return String(format: "%.1f GB", Double(s) / 1_000_000_000) }
        if s > 1_000_000 { return String(format: "%.0f MB", Double(s) / 1_000_000) }
        return String(format: "%.0f KB", Double(s) / 1_000) }
}

struct LoadedRepo: Identifiable {
    let url: String
    let manifest: RepoManifest
    var id: String { url }
}

// MARK: - Service

class RepoService: ObservableObject {
    static let shared = RepoService()

    @AppStorage("saved_repo_urls") private var savedURLsJSON: String = "[]"
    @Published var repos: [LoadedRepo] = []
    @Published var isLoading = false

    private init() {
        Task { await refreshAll() }
    }

    var savedURLs: [String] {
        get {
            guard let data = savedURLsJSON.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return urls
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                savedURLsJSON = json
            }
        }
    }

    var allApps: [RepoApp] {
        repos.flatMap { $0.manifest.apps }
    }

    func addRepo(url: String) async {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !savedURLs.contains(cleaned) else { return }
        var urls = savedURLs
        urls.append(cleaned)
        await MainActor.run { savedURLs = urls }
        await refreshAll()
    }

    func removeRepo(url: String) async {
        var urls = savedURLs
        urls.removeAll { $0 == url }
        await MainActor.run {
            savedURLs = urls
            repos.removeAll { $0.url == url }
        }
    }

    func refreshAll() async {
        let urls = savedURLs
        await MainActor.run { isLoading = true }

        var loaded: [LoadedRepo] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(RepoManifest.self, from: data)
                loaded.append(LoadedRepo(url: urlString, manifest: manifest))
            } catch {
                print("Failed to load repo \(urlString): \(error)")
            }
        }

        await MainActor.run {
            repos = loaded
            isLoading = false
        }
    }
}

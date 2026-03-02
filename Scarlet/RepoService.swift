import Foundation
import SwiftUI

// MARK: - Models

struct RepoManifest: Codable {
    let name: String?
    let identifier: String?
    let sourceURL: String?
    let iconURL: String?
    let subtitle: String?
    let apps: [RepoApp]?

    var displayName: String { name ?? "Unknown Repo" }
    var appCount: Int { apps?.count ?? 0 }
}

struct RepoApp: Codable, Identifiable, Hashable {
    let name: String?
    let bundleID: String?
    let bundleIdentifier: String?
    let version: String?
    let size: Int?
    let downloadURL: String?
    let down: String?  // some repos use "down" instead of "downloadURL"
    let localizedDescription: String?
    let iconURL: String?
    let icon: String?  // some repos use "icon" instead of "iconURL"
    let developerName: String?
    let versionDate: String?
    let type: Int?
    let appUpdateTime: String?

    var id: String { (bundleID ?? bundleIdentifier ?? UUID().uuidString) + (version ?? "") }

    var displayName: String { name ?? "Unknown App" }
    var resolvedDownloadURL: String? { downloadURL ?? down }
    var resolvedIconURL: String? { iconURL ?? icon }

    var sizeString: String {
        guard let s = size else { return "—" }
        if s > 1_000_000_000 { return String(format: "%.1f GB", Double(s) / 1_000_000_000) }
        if s > 1_000_000 { return String(format: "%.0f MB", Double(s) / 1_000_000) }
        return String(format: "%.0f KB", Double(s) / 1_000)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RepoApp, rhs: RepoApp) -> Bool { lhs.id == rhs.id }
}

struct LoadedRepo: Identifiable {
    let url: String
    let manifest: RepoManifest
    var id: String { url }
}

// MARK: - Service

class RepoService: ObservableObject {
    static let shared = RepoService()

    @Published var repos: [LoadedRepo] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var activeRepo: LoadedRepo?

    private let key = "scarlet_repo_urls_v2"

    var savedURLs: [String] {
        get { (UserDefaults.standard.array(forKey: key) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    var allApps: [RepoApp] {
        repos.flatMap { $0.manifest.apps ?? [] }
    }

    /// Apps to search — scoped to active repo if inside one, otherwise all repos
    var searchableApps: [RepoApp] {
        if let active = activeRepo {
            return active.manifest.apps ?? []
        }
        return allApps
    }

    private init() {
        let urls = savedURLs
        if !urls.isEmpty {
            Task { await fetchRepos(urls) }
        }
    }

    @MainActor
    func addRepo(url: String) {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var urls = savedURLs
        if !urls.contains(cleaned) {
            urls.append(cleaned)
            savedURLs = urls
        }
        isLoading = true
        lastError = nil
        Task { await fetchRepos(savedURLs) }
    }

    @MainActor
    func removeRepo(url: String) {
        var urls = savedURLs
        urls.removeAll { $0 == url }
        savedURLs = urls
        repos.removeAll { $0.url == url }
    }

    func fetchRepos(_ urls: [String]) async {
        await MainActor.run { isLoading = true; lastError = nil }

        var loaded: [LoadedRepo] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(RepoManifest.self, from: data)
                loaded.append(LoadedRepo(url: urlString, manifest: manifest))
            } catch {
                print("[RepoService] Error loading \(urlString): \(error)")
                await MainActor.run { self.lastError = "Failed to load repo" }
            }
        }

        await MainActor.run {
            self.repos = loaded
            self.isLoading = false
        }
    }
}

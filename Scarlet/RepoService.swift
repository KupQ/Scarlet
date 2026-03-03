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
    let isDefault: Bool
    var id: String { url }
}

// MARK: - Service

class RepoService: ObservableObject {
    static let shared = RepoService()

    @Published var repos: [LoadedRepo] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var activeRepo: LoadedRepo?

    private let localKey = "scarlet_local_repo_urls"

    // MARK: - Default repo URLs (from bundled repo.txt)

    var defaultURLs: [String] {
        guard let bundledURL = Bundle.main.url(forResource: "repo", withExtension: "txt"),
              let content = try? String(contentsOf: bundledURL, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("http") }
    }

    // MARK: - Local (user-added) repo URLs

    var localURLs: [String] {
        get { (UserDefaults.standard.array(forKey: localKey) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: localKey) }
    }

    // MARK: - Filtered views

    var defaultRepos: [LoadedRepo] { repos.filter { $0.isDefault } }
    var localRepos: [LoadedRepo] { repos.filter { !$0.isDefault } }

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

    /// Returns the repo display name that contains this app
    func repoName(for app: RepoApp) -> String? {
        for repo in repos {
            if repo.manifest.apps?.contains(where: { $0.id == app.id }) == true {
                return repo.manifest.displayName
            }
        }
        return nil
    }

    // MARK: - Init

    private init() {
        // Migrate old saved_repo_urls to local if needed
        if let oldURLs = UserDefaults.standard.array(forKey: "scarlet_repo_urls_v2") as? [String], !oldURLs.isEmpty {
            let defaults = defaultURLs
            let userOnly = oldURLs.filter { !defaults.contains($0) }
            if !userOnly.isEmpty {
                localURLs = userOnly
            }
            UserDefaults.standard.removeObject(forKey: "scarlet_repo_urls_v2")
        }

        let allURLs = defaultURLs + localURLs
        if !allURLs.isEmpty {
            Task { await fetchRepos() }
        }
    }

    // MARK: - Add / Remove (local only)

    @MainActor
    func addRepo(url: String) {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Don't add if already exists in default or local
        guard !defaultURLs.contains(cleaned), !localURLs.contains(cleaned) else { return }
        var urls = localURLs
        urls.append(cleaned)
        localURLs = urls
        isLoading = true
        lastError = nil
        Task { await fetchRepos() }
    }

    @MainActor
    func removeRepo(url: String) {
        // Only allow removing local repos
        guard !defaultURLs.contains(url) else { return }
        var urls = localURLs
        urls.removeAll { $0 == url }
        localURLs = urls
        repos.removeAll { $0.url == url }
    }

    // MARK: - Fetch

    func fetchRepos() async {
        let defaultList = defaultURLs
        let localList = localURLs
        await MainActor.run { isLoading = true; lastError = nil }

        var loaded: [LoadedRepo] = []

        // Load default repos
        for urlString in defaultList {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(RepoManifest.self, from: data)
                loaded.append(LoadedRepo(url: urlString, manifest: manifest, isDefault: true))
            } catch {
                print("[RepoService] Error loading default \(urlString): \(error)")
            }
        }

        // Load local repos
        for urlString in localList {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let manifest = try JSONDecoder().decode(RepoManifest.self, from: data)
                loaded.append(LoadedRepo(url: urlString, manifest: manifest, isDefault: false))
            } catch {
                print("[RepoService] Error loading local \(urlString): \(error)")
                await MainActor.run { self.lastError = "Failed to load repo" }
            }
        }

        await MainActor.run {
            self.repos = loaded
            self.isLoading = false
        }
    }
}


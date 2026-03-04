import Foundation
import SwiftUI

// MARK: - Models

/// AltStore v2 nested version entry (used by ~20% of repos).
struct AppVersion: Codable, Hashable {
    let version: String?
    let date: String?
    let downloadURL: String?
    let size: Int?
    let localizedDescription: String?
    let minOSVersion: String?
    let sha256: String?
}

/// Repo news item (some repos include news/announcements).
struct RepoNews: Codable, Identifiable {
    let title: String?
    let identifier: String?
    let caption: String?
    let tintColor: String?
    let imageURL: String?
    let date: String?
    let url: String?
    let notify: Bool?
    var id: String { identifier ?? title ?? UUID().uuidString }
}

struct RepoManifest: Codable {
    let name: String?
    let identifier: String?
    let sourceURL: String?
    let iconURL: String?
    let subtitle: String?
    let website: String?
    let apps: [RepoApp]?
    let news: [RepoNews]?

    var displayName: String { name ?? "Unknown Repo" }
    var appCount: Int { apps?.count ?? 0 }
}

struct RepoApp: Codable, Identifiable, Hashable {
    // Core fields (present in all formats)
    let name: String?
    let bundleID: String?
    let bundleIdentifier: String?
    let developerName: String?
    let localizedDescription: String?
    let iconURL: String?
    let icon: String?           // some repos use "icon" instead of "iconURL"
    let type: Int?

    // Flat format fields (ESign / most repos)
    let version: String?
    let size: Int?
    let downloadURL: String?
    let down: String?           // some repos use "down" instead of "downloadURL"
    let versionDate: String?
    let appUpdateTime: String?
    let versionDescription: String?

    // AltStore v2 format (versions nested per app)
    let versions: [AppVersion]?

    // Optional rich fields
    let screenshotURLs: [String]?
    let subtitle: String?
    let tintColor: String?

    /// Stable fallback identifier for apps that lack bundleID/bundleIdentifier.
    /// Generated once during decoding so SwiftUI identity stays consistent.
    private let _stableId: String

    // MARK: - Computed (universal — flat fields take priority, versions[] as fallback)

    var id: String { _stableId }

    // Custom decoding to generate a stable fallback ID once
    enum CodingKeys: String, CodingKey {
        case name, bundleID, bundleIdentifier, developerName, localizedDescription
        case iconURL, icon, type, version, size, downloadURL, down
        case versionDate, appUpdateTime, versionDescription, versions
        case screenshotURLs, subtitle, tintColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        developerName = try c.decodeIfPresent(String.self, forKey: .developerName)
        localizedDescription = try c.decodeIfPresent(String.self, forKey: .localizedDescription)
        iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        type = try c.decodeIfPresent(Int.self, forKey: .type)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        downloadURL = try c.decodeIfPresent(String.self, forKey: .downloadURL)
        down = try c.decodeIfPresent(String.self, forKey: .down)
        versionDate = try c.decodeIfPresent(String.self, forKey: .versionDate)
        appUpdateTime = try c.decodeIfPresent(String.self, forKey: .appUpdateTime)
        versionDescription = try c.decodeIfPresent(String.self, forKey: .versionDescription)
        versions = try c.decodeIfPresent([AppVersion].self, forKey: .versions)
        screenshotURLs = try c.decodeIfPresent([String].self, forKey: .screenshotURLs)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        tintColor = try c.decodeIfPresent(String.self, forKey: .tintColor)

        // Generate a stable unique ID for every app
        let bid = bundleID ?? bundleIdentifier ?? ""
        let dl = downloadURL ?? down ?? ""
        let ver = version ?? ""
        let nm = name ?? ""
        if !bid.isEmpty || !dl.isEmpty {
            // Combine all distinguishing fields for uniqueness
            let combo = bid + "|" + ver + "|" + dl + "|" + nm
            _stableId = "app_\(abs(combo.hashValue))"
        } else {
            _stableId = UUID().uuidString
        }
    }

    var displayName: String { name ?? "Unknown App" }

    var resolvedDownloadURL: String? {
        downloadURL ?? down ?? versions?.first?.downloadURL
    }

    var resolvedIconURL: String? { iconURL ?? icon }

    var resolvedVersion: String? {
        version ?? versions?.first?.version
    }

    var resolvedSize: Int? {
        size ?? versions?.first?.size
    }

    var resolvedDate: String? {
        versionDate ?? appUpdateTime ?? versions?.first?.date
    }

    var resolvedDescription: String? {
        localizedDescription ?? versions?.first?.localizedDescription
    }

    var sizeString: String {
        guard let s = resolvedSize else { return "—" }
        if s > 1_000_000_000 { return String(format: "%.1f GB", Double(s) / 1_000_000_000) }
        if s > 1_000_000 { return String(format: "%.0f MB", Double(s) / 1_000_000) }
        return String(format: "%.0f KB", Double(s) / 1_000)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RepoApp, rhs: RepoApp) -> Bool { lhs.id == rhs.id }
}

struct LoadedRepo: Identifiable, Codable {
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
    @Published var loadedCount = 0
    @Published var totalCount = 0

    private let localKey = "scarlet_local_repo_urls"
    private let cacheRefreshInterval: TimeInterval = 15 * 60  // 15 minutes

    // MARK: - Cache

    private var cacheURL: URL {
        let support = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("repo_cache.json")
    }

    private var cacheAge: TimeInterval {
        let ts = UserDefaults.standard.double(forKey: "scarlet_repo_cache_ts")
        guard ts > 0 else { return .infinity }
        return Date().timeIntervalSince1970 - ts
    }

    private func loadCache() -> [LoadedRepo]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([LoadedRepo].self, from: data) else { return nil }
        return cached
    }

    private func saveCache(_ repos: [LoadedRepo]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? data.write(to: cacheURL)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "scarlet_repo_cache_ts")
    }

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

        // Load from disk cache instantly (no network)
        if let cached = loadCache() {
            repos = cached
        }

        // Background refresh if cache is stale or empty
        let needsRefresh = repos.isEmpty || cacheAge > cacheRefreshInterval
        if needsRefresh {
            Task { await fetchRepos(showProgress: repos.isEmpty) }
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

    func fetchRepos(showProgress: Bool = true) async {
        let defaultList = defaultURLs
        let localList = localURLs
        let allURLs: [(url: String, isDefault: Bool)] =
            defaultList.map { ($0, true) } + localList.map { ($0, false) }

        await MainActor.run {
            if showProgress {
                isLoading = true
                loadedCount = 0
                totalCount = allURLs.count
            }
            lastError = nil
        }

        // Load all repos concurrently — each appears on screen as it loads
        var freshRepos: [LoadedRepo] = []
        await withTaskGroup(of: LoadedRepo?.self) { group in
            for entry in allURLs {
                group.addTask {
                    guard let url = URL(string: entry.url) else { return nil }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let manifest = try JSONDecoder().decode(RepoManifest.self, from: data)
                        return LoadedRepo(url: entry.url, manifest: manifest, isDefault: entry.isDefault)
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                await MainActor.run { loadedCount += 1 }
                if let repo = result {
                    freshRepos.append(repo)
                    // Show repo on screen immediately
                    await MainActor.run {
                        // Replace if already exists (refresh), otherwise append
                        if let idx = repos.firstIndex(where: { $0.url == repo.url }) {
                            repos[idx] = repo
                        } else {
                            repos.append(repo)
                        }
                    }
                }
            }
        }

        // Update UI and persist to disk
        await MainActor.run {
            isLoading = false
        }
        saveCache(freshRepos)
    }

    /// Force refresh — user-triggered
    func forceRefresh() async {
        await fetchRepos(showProgress: true)
    }
}


import SwiftUI

// MARK: - Download Manager with Progress

struct PendingDownload: Identifiable {
    let id: String
    let appName: String
    let iconURL: String?
    let sizeString: String
    var progress: Double  // 0.0-1.0
}

class DownloadManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: Double] = [:]  // id -> progress 0.0-1.0
    @Published var pendingDownloads: [PendingDownload] = []
    private var tasks: [URLSessionDataTask: String] = [:]  // task -> app id
    private var completions: [String: (URL) -> Void] = [:]
    private var fileHandles: [String: FileHandle] = [:]   // id -> open file handle
    private var destURLs: [String: URL] = [:]             // id -> destination path
    private var expectedBytes: [String: Int64] = [:]
    private var receivedBytes: [String: Int64] = [:]
    private var bgTaskIds: [String: UIBackgroundTaskIdentifier] = [:] // keep alive in bg
    var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    /// Downloads go to the same unsigned/ dir as imported apps
    private var downloadsDir: URL {
        ImportedAppsManager.appsDirectory
    }

    func download(id: String, url: URL, appName: String = "", iconURL: String? = nil, sizeString: String = "", completion: @escaping (URL) -> Void) {
        guard activeDownloads[id] == nil else { return }

        let log = FileLogger.shared
        let dest = downloadsDir.appendingPathComponent(UUID().uuidString + ".ipa")
        log.log("[DL] Starting download '\(appName)' -> \(dest.lastPathComponent)")

        // Create the destination file immediately
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: dest) else {
            log.log("[DL] ERROR: cannot create file handle at \(dest.path)")
            return
        }

        // Request background execution time so download survives backgrounding
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "IPA Download \(id)") { [weak self] in
            self?.cancelDownload(id: id)
        }
        bgTaskIds[id] = bgTask

        activeDownloads[id] = 0.0
        pendingDownloads.append(PendingDownload(id: id, appName: appName, iconURL: iconURL, sizeString: sizeString, progress: 0.0))
        completions[id] = completion
        fileHandles[id] = handle
        destURLs[id] = dest
        expectedBytes[id] = 0
        receivedBytes[id] = 0

        let task = session.dataTask(with: url)
        tasks[task] = id
        task.resume()
    }

    func cancelDownload(id: String) {
        if let entry = tasks.first(where: { $0.value == id }) {
            entry.key.cancel()
            tasks.removeValue(forKey: entry.key)
        }
        cleanupDownload(id: id)
        // Delete partial file
        if let dest = destURLs[id] {
            try? FileManager.default.removeItem(at: dest)
        }
        destURLs.removeValue(forKey: id)
    }

    // Called when we receive the response headers — get expected size
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let id = tasks[dataTask] else {
            completionHandler(.cancel)
            return
        }
        expectedBytes[id] = response.expectedContentLength
        FileLogger.shared.log("[DL] Response received, expected bytes: \(response.expectedContentLength)")
        completionHandler(.allow)
    }

    // Called as data chunks arrive — write directly to file
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let id = tasks[dataTask], let handle = fileHandles[id] else { return }
        handle.write(data)
        receivedBytes[id] = (receivedBytes[id] ?? 0) + Int64(data.count)

        let total = expectedBytes[id] ?? 0
        let received = receivedBytes[id] ?? 0
        let p = total > 0 ? Double(received) / Double(total) : 0.0
        activeDownloads[id] = p
        if let idx = pendingDownloads.firstIndex(where: { $0.id == id }) {
            pendingDownloads[idx].progress = p
        }
    }

    // Called when download completes or errors
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dataTask = task as? URLSessionDataTask, let id = tasks[dataTask] else { return }
        let log = FileLogger.shared

        // Close file handle
        fileHandles[id]?.closeFile()
        fileHandles.removeValue(forKey: id)

        if let error = error {
            log.log("[DL] ERROR: \(error.localizedDescription)")
            // Delete partial file
            if let dest = destURLs[id] {
                try? FileManager.default.removeItem(at: dest)
            }
            cleanupDownload(id: id)
            destURLs.removeValue(forKey: id)
            return
        }

        guard let dest = destURLs[id] else {
            log.log("[DL] ERROR: no dest URL for id \(id)")
            cleanupDownload(id: id)
            return
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        log.log("[DL] Download complete: \(dest.lastPathComponent) (\(size) bytes)")

        let appName = pendingDownloads.first(where: { $0.id == id })?.appName ?? "App"
        let completion = completions[id]
        cleanupDownload(id: id)
        destURLs.removeValue(forKey: id)

        // Call completion with the file we already wrote
        completion?(dest)

        // Notify if backgrounded
        if UIApplication.shared.applicationState != .active {
            NotificationHelper.send(
                title: L("Download Complete"),
                body: String(format: L("%@ has been downloaded"), appName)
            )
        }
    }

    private func cleanupDownload(id: String) {
        completions.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)
        pendingDownloads.removeAll { $0.id == id }
        expectedBytes.removeValue(forKey: id)
        receivedBytes.removeValue(forKey: id)
        if let entry = tasks.first(where: { $0.value == id }) {
            tasks.removeValue(forKey: entry.key)
        }
        // End background execution
        if let bgTask = bgTaskIds.removeValue(forKey: id), bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
    }
}

/// Detail view for a single repo — shows all apps with lazy loading.
struct RepoDetailView: View {
    let repo: LoadedRepo
    @ObservedObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    private var apps: [RepoApp] {
        repo.manifest.apps ?? []
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let iconStr = repo.manifest.iconURL, let url = URL(string: iconStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.manifest.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(apps.count) \(L("apps"))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

                // Lazy app list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(apps) { app in
                            repoAppRow(app)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .background(InteractivePopGestureEnabler())
        .onAppear { RepoService.shared.activeRepo = repo }
        .onDisappear { RepoService.shared.activeRepo = nil }
    }

    private func repoAppRow(_ app: RepoApp) -> some View {
        let progress = downloadManager.activeDownloads[app.id]

        return HStack(spacing: 14) {
            // Icon
            if let iconStr = app.resolvedIconURL, let url = URL(string: iconStr) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.04))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "app.fill").foregroundColor(.white.opacity(0.15)))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Subtitle line — only show items that exist
                let parts = buildSubtitle(app)
                if !parts.isEmpty {
                    Text(parts)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .lineLimit(1)
                }
            }

            Spacer()

            // GET / progress
            if let p = progress {
                Text("\(Int(p * 100))%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.scarletRed)
                    .frame(width: 50)
            } else {
                Button { downloadApp(app) } label: {
                    Text(L("GET"))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.scarletRed)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.scarletRed.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.02))
        )
    }

    private func buildSubtitle(_ app: RepoApp) -> String {
        var items: [String] = []
        if let v = app.resolvedVersion, !v.isEmpty { items.append("v\(v)") }
        let size = app.sizeString
        if size != "—" { items.append(size) }
        if let dev = app.developerName, !dev.isEmpty { items.append(dev) }
        return items.joined(separator: " • ")
    }

    private func downloadApp(_ app: RepoApp) {
        guard let dlStr = app.resolvedDownloadURL, let url = URL(string: dlStr) else { return }

        downloadManager.download(
            id: app.id, url: url,
            appName: app.displayName, iconURL: app.resolvedIconURL, sizeString: app.sizeString
        ) { savedURL in
            ImportedAppsManager.shared.importIPA(from: savedURL)
        }

        // Switch to Library tab without leaving repo
        NotificationCenter.default.post(name: .switchToLibrary, object: nil)
    }
}

extension Notification.Name {
    static let switchToLibrary = Notification.Name("switchToLibrary")
}

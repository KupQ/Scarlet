import SwiftUI

// MARK: - Download Manager with Progress

struct PendingDownload: Identifiable {
    let id: String
    let appName: String
    let iconURL: String?
    let sizeString: String
    var progress: Double  // 0.0-1.0
}

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: Double] = [:]  // id -> progress 0.0-1.0
    @Published var pendingDownloads: [PendingDownload] = []
    private var tasks: [URLSessionDownloadTask: String] = [:]  // task -> app id
    private var completions: [String: (URL) -> Void] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 600  // 10 min for large IPAs
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    func download(id: String, url: URL, appName: String = "", iconURL: String? = nil, sizeString: String = "", completion: @escaping (URL) -> Void) {
        guard activeDownloads[id] == nil else { return }
        activeDownloads[id] = 0.0
        pendingDownloads.append(PendingDownload(id: id, appName: appName, iconURL: iconURL, sizeString: sizeString, progress: 0.0))
        completions[id] = completion
        let task = session.downloadTask(with: url)
        tasks[task] = id
        task.resume()
    }

    func cancelDownload(id: String) {
        if let entry = tasks.first(where: { $0.value == id }) {
            entry.key.cancel()
            tasks.removeValue(forKey: entry.key)
        }
        completions.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)
        pendingDownloads.removeAll { $0.id == id }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = tasks[downloadTask], totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        activeDownloads[id] = p
        if let idx = pendingDownloads.firstIndex(where: { $0.id == id }) {
            pendingDownloads[idx].progress = p
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = tasks[downloadTask] else { return }
        let appName = pendingDownloads.first(where: { $0.id == id })?.appName ?? "App"
        let log = FileLogger.shared

        log.log("[DL-1] didFinishDownloadingTo for '\(appName)' thread=\(Thread.isMainThread ? "main" : "bg")")
        log.log("[DL-2] temp location: \(location.path)")
        log.log("[DL-3] temp file exists: \(FileManager.default.fileExists(atPath: location.path))")

        let fm = FileManager.default
        let appSupport = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = appSupport.appendingPathComponent("Downloads")
        try? fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let dest = downloadsDir.appendingPathComponent(UUID().uuidString + ".ipa")
        log.log("[DL-4] dest path: \(dest.path)")

        var saved = false
        // iOS 15: background URLSession temp files can be MOVED but not copied
        do {
            try fm.moveItem(at: location, to: dest)
            saved = true
            let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? -1
            log.log("[DL-5] moveItem OK, saved size=\(size) bytes")
        } catch {
            log.log("[DL-5] ERROR moveItem: \(error)")
            // Fallback: try copy
            do {
                try fm.copyItem(at: location, to: dest)
                saved = true
                log.log("[DL-5b] copyItem fallback OK")
            } catch {
                log.log("[DL-5b] ERROR copyItem: \(error)")
                // Last resort: read data
                if let data = try? Data(contentsOf: location) {
                    do {
                        try data.write(to: dest)
                        saved = true
                        log.log("[DL-6] data fallback OK (\(data.count) bytes)")
                    } catch {
                        log.log("[DL-6] ERROR data write: \(error)")
                    }
                } else {
                    log.log("[DL-6] ERROR cannot read temp file data")
                }
            }
        }

        tasks.removeValue(forKey: downloadTask)
        let completion = completions.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)
        pendingDownloads.removeAll { $0.id == id }

        guard saved, fm.fileExists(atPath: dest.path) else {
            log.log("[DL-7] ABORT: file not saved, skipping import")
            return
        }

        log.log("[DL-7] file verified, dispatching import to main")

        DispatchQueue.main.async {
            log.log("[DL-8] main dispatch fired, calling completion")
            completion?(dest)
            log.log("[DL-9] completion returned")
        }

        // Notify if backgrounded
        if UIApplication.shared.applicationState != .active {
            NotificationHelper.send(
                title: L("Download Complete"),
                body: String(format: L("%@ has been downloaded"), appName)
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dlTask = task as? URLSessionDownloadTask, let id = tasks[dlTask] else { return }
        if error != nil {
            print("[DownloadManager] Error for \(id): \(error!)")
            tasks.removeValue(forKey: dlTask)
            completions.removeValue(forKey: id)
            activeDownloads.removeValue(forKey: id)
            pendingDownloads.removeAll { $0.id == id }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
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

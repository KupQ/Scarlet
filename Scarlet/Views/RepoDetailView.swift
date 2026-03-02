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
        let config = URLSessionConfiguration.background(withIdentifier: "com.scarlet.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
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
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try? FileManager.default.moveItem(at: location, to: tmp)
        tasks.removeValue(forKey: downloadTask)
        completions[id]?(tmp)
        completions.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)
        pendingDownloads.removeAll { $0.id == id }

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
                    LazyVStack(spacing: 6) {
                        ForEach(apps) { app in
                            repoAppRow(app)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { RepoService.shared.activeRepo = repo }
        .onDisappear { RepoService.shared.activeRepo = nil }
    }

    private func repoAppRow(_ app: RepoApp) -> some View {
        let progress = downloadManager.activeDownloads[app.id]

        return HStack(spacing: 12) {
            // Icon
            if let iconStr = app.resolvedIconURL, let url = URL(string: iconStr) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "app.fill").foregroundColor(.white.opacity(0.15)))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let v = app.version {
                        Text("v\(v)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text("•")
                    Text(app.sizeString)
                        .font(.system(size: 10, weight: .medium))
                    if let dev = app.developerName {
                        Text("•")
                        Text(dev)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(.white.opacity(0.25))
            }

            Spacer()

            // GET / progress
            if let p = progress {
                Text("\(Int(p * 100))%")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.scarletRed)
                    .frame(width: 50)
            } else {
                Button { downloadApp(app) } label: {
                    Text(L("GET"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.scarletRed)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.scarletRed.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.02))
        )
    }

    private func downloadApp(_ app: RepoApp) {
        guard let dlStr = app.resolvedDownloadURL, let url = URL(string: dlStr) else { return }

        downloadManager.download(
            id: app.id, url: url,
            appName: app.displayName, iconURL: app.resolvedIconURL, sizeString: app.sizeString
        ) { tempURL in
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let filename = "\(app.bundleID ?? app.bundleIdentifier ?? UUID().uuidString).ipa"
            let dest = docs.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                ImportedAppsManager.shared.importIPA(from: dest)
            } catch {
                print("[RepoDetail] Move error: \(error)")
            }
        }
    }
}

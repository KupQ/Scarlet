//
//  HomeView.swift
//  Scarlet
//
//  Home dashboard with premium liquid glass design.
//

import SwiftUI

/// Simple seeded RNG for deterministic shuffling
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct HomeView: View {
    @ObservedObject var signingState: SigningState
    var switchToLibrary: () -> Void

    @ObservedObject private var repoService = RepoService.shared
    @ObservedObject private var appsManager = ImportedAppsManager.shared
    @State private var animatePulse = false
    @State private var animateGlow = false
    @State private var showAddRepo = false
    @State private var showBulkAdd = false
    @State private var repoURLInput = ""
    @State private var bulkRepoInput = ""
    @State private var currentSlide = 0
    private let slideTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private func isInLibrary(_ app: RepoApp) -> Bool {
        let bid = app.bundleID ?? app.bundleIdentifier ?? ""
        guard !bid.isEmpty else { return false }
        let ver = app.resolvedVersion ?? ""
        return appsManager.apps.contains { $0.bundleIdentifier == bid && (ver.isEmpty || $0.version == ver) }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Pinned header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Scarlet"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Menu {
                        Button { showAddRepo = true } label: {
                            Label(L("Add Repo"), systemImage: "plus.app")
                        }
                        Button { showBulkAdd = true } label: {
                            Label(L("Add Multiple"), systemImage: "list.bullet.rectangle")
                        }
                        Button {
                            if let clip = UIPasteboard.general.string, !clip.isEmpty {
                                let urls = clip
                                    .components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { $0.hasPrefix("http") }
                                if urls.isEmpty {
                                    repoService.addRepo(url: clip.trimmingCharacters(in: .whitespacesAndNewlines))
                                } else {
                                    for url in urls { repoService.addRepo(url: url) }
                                }
                            }
                        } label: {
                            Label(L("Add from Clipboard"), systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.03))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.scarletRed.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.bgPrimary)

                // Pinned hero slideshow (does not scroll)
                heroBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {

                    // Loading progress indicator
                    if repoService.isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                                .tint(.scarletRed)
                                .scaleEffect(0.9)
                            Text(L("Loading sources... \(repoService.loadedCount)/\(repoService.totalCount)"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    // Repos
                    repoAppsSection

                    Spacer().frame(height: 80)
                }
            }
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear {
            animateGlow = true
            animatePulse = true
        }
        .alert(L("Add Repository"), isPresented: $showAddRepo) {
            TextField(L("https://example.com/repo.json"), text: $repoURLInput)
                .autocapitalization(.none)
            Button(L("Cancel"), role: .cancel) { repoURLInput = "" }
            Button(L("Add")) {
                let url = repoURLInput
                repoURLInput = ""
                repoService.addRepo(url: url)
            }
        } message: {
            Text(L("Enter the repo JSON URL"))
        }
        .alert(L("Add Multiple Repos"), isPresented: $showBulkAdd) {
            TextField(L("One URL per line"), text: $bulkRepoInput)
                .autocapitalization(.none)
            Button(L("Cancel"), role: .cancel) { bulkRepoInput = "" }
            Button(L("Add All")) {
                let urls = bulkRepoInput
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                bulkRepoInput = ""
                for url in urls { repoService.addRepo(url: url) }
            }
        } message: {
            Text(L("Enter repo URLs, one per line"))
        }
        .alert(L("Repo Error"), isPresented: Binding(
            get: { repoService.lastError != nil },
            set: { if !$0 { repoService.lastError = nil } }
        )) {
            Button(L("OK")) { repoService.lastError = nil }
        } message: {
            Text(repoService.lastError ?? L("Unknown error"))
        }
    }

    // MARK: - App Showcase Banner

    private var showcaseApps: [RepoApp] {
        let apps = repoService.allApps
        guard !apps.isEmpty else { return [] }
        let seed = UInt64(arc4random())
        var rng = SeededRNG(seed: seed)
        return Array(apps.shuffled(using: &rng).prefix(8))
    }

    private var heroBanner: some View {
        let apps = showcaseApps
        return Group {
            if apps.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 8) {
                    TabView(selection: $currentSlide) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            appShowcaseCard(app)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentSlide)
                    .onReceive(slideTimer) { _ in
                        guard apps.count > 1 else { return }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                            currentSlide = (currentSlide + 1) % apps.count
                        }
                    }

                    if apps.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<apps.count, id: \.self) { i in
                                Capsule()
                                    .fill(i == currentSlide ? Color.scarletRed : Color.white.opacity(0.15))
                                    .frame(width: i == currentSlide ? 18 : 5, height: 5)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentSlide)
                            }
                        }
                    }
                }
            }
        }
    }

    private func appShowcaseCard(_ app: RepoApp) -> some View {
        ZStack {
            // Animated background — low FPS since blobs move slowly
            TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: 0.98, saturation: 0.7, brightness: 0.28),
                                    Color(hue: 0.0, saturation: 0.5, brightness: 0.12),
                                    Color(white: 0.05)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .fill(RadialGradient(colors: [Color.scarletRed.opacity(0.55), Color.scarletRed.opacity(0.12), .clear], center: .center, startRadius: 10, endRadius: 110))
                        .frame(width: 220, height: 220)
                        .offset(x: CGFloat(sin(t * 0.6)) * 80 + 30, y: CGFloat(cos(t * 0.45)) * 50 - 20)
                        .blur(radius: 20)

                    Circle()
                        .fill(RadialGradient(colors: [Color(hue: 0.95, saturation: 0.9, brightness: 0.5).opacity(0.4), .clear], center: .center, startRadius: 5, endRadius: 90))
                        .frame(width: 180, height: 180)
                        .offset(x: CGFloat(cos(t * 0.5)) * 70 - 20, y: CGFloat(sin(t * 0.7)) * 45 + 10)
                        .blur(radius: 16)

                    Circle()
                        .fill(RadialGradient(colors: [Color(hue: 0.02, saturation: 1.0, brightness: 0.7).opacity(0.25), .clear], center: .center, startRadius: 3, endRadius: 50))
                        .frame(width: 100, height: 100)
                        .offset(x: CGFloat(sin(t * 0.9 + 2.0)) * 90, y: CGFloat(cos(t * 0.65 + 1.0)) * 40)
                        .blur(radius: 12)
                }
                .drawingGroup()
            }

            // Static border
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [Color.scarletRed.opacity(0.25), Color.white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // Static content — NOT inside TimelineView
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 76, height: 76)
                        .shadow(color: Color.scarletRed.opacity(0.25), radius: 12, y: 4)
                    AsyncImage(url: URL(string: app.resolvedIconURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        default:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.scarletRed.opacity(0.3), .scarletDark.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                                .overlay(Image(systemName: "app.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.25)))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white).lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill").font(.system(size: 9)).foregroundColor(.scarletRed.opacity(0.7))
                        Text(app.resolvedVersion ?? "1.0").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                        if app.resolvedSize != nil {
                            Text("·").foregroundColor(.white.opacity(0.3))
                            Text(app.sizeString).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                        }
                    }
                    HStack(spacing: 3) {
                        Capsule().fill(Color.scarletRed.opacity(0.6)).frame(width: 30, height: 3)
                        Capsule().fill(Color.scarletRed.opacity(0.3)).frame(width: 16, height: 3)
                        Capsule().fill(Color.scarletRed.opacity(0.15)).frame(width: 8, height: 3)
                    }.padding(.top, 2)
                }
                Spacer()
                if isInLibrary(app) {
                    Button {
                        NotificationCenter.default.post(
                            name: .signAppDirectly,
                            object: nil,
                            userInfo: ["bundleID": app.bundleID ?? app.bundleIdentifier ?? "",
                                       "version": app.resolvedVersion ?? ""]
                        )
                    } label: {
                        Text("Sign")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                            )
                    }.buttonStyle(.plain)
                } else {
                    Button {
                        guard let urlStr = app.resolvedDownloadURL, let url = URL(string: urlStr) else { return }
                        DownloadManager.shared.download(id: app.id, url: url, appName: app.displayName, iconURL: app.resolvedIconURL, sizeString: app.sizeString) { fileURL in
                            ImportedAppsManager.shared.importIPA(from: fileURL)
                        }
                    } label: {
                        Text("GET")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                            )
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .frame(height: 180)
    }




    // MARK: - Repo Cards

    private var repoAppsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Default Repos ──
            if !repoService.defaultRepos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("DEFAULT"))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.25))
                        Spacer()
                        if repoService.isLoading {
                            ProgressView()
                                .tint(.white.opacity(0.3))
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 20)

                    ForEach(repoService.defaultRepos) { repo in
                        NavigationLink(destination: RepoDetailView(repo: repo)) {
                            repoCard(repo)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }
            }

            // ── Local Repos ──
            if !repoService.localRepos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("LOCAL"))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.25))
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    ForEach(repoService.localRepos) { repo in
                        NavigationLink(destination: RepoDetailView(repo: repo)) {
                            repoCard(repo)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .contextMenu {
                            Button(role: .destructive) {
                                repoService.removeRepo(url: repo.url)
                            } label: {
                                Label(L("Remove Repo"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func repoCard(_ repo: LoadedRepo) -> some View {
        HStack(spacing: 14) {
            // Repo icon
            if let iconStr = repo.manifest.iconURL, let url = URL(string: iconStr) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.scarletRed, .scarletDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Text(String(repo.manifest.displayName.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.manifest.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(repo.manifest.appCount) \(L("apps"))")
                        .font(.system(size: 11, weight: .medium))
                    if let sub = repo.manifest.subtitle {
                        Text("•")
                        Text(sub)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

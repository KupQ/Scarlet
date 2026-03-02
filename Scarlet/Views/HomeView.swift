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
    @State private var animatePulse = false
    @State private var animateGlow = false
    @State private var showAddRepo = false
    @State private var showBulkAdd = false
    @State private var repoURLInput = ""
    @State private var bulkRepoInput = ""
    @State private var currentSlide = 0
    private let slideTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
                        Text(L("iOS App Signing"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                    Button { showAddRepo = true } label: {
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
                    .buttonStyle(.plain)
                    .contextMenu {
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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.bgPrimary)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {

                    // API-driven hero slideshow
                    heroBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // Repos
                    if !repoService.repos.isEmpty {
                        repoAppsSection
                    }

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
        let seed = Calendar.current.component(.hour, from: Date())
        var rng = SeededRNG(seed: UInt64(seed))
        return Array(apps.shuffled(using: &rng).prefix(8))
    }

    private var heroBanner: some View {
        let apps = showcaseApps
        return Group {
            if apps.isEmpty {
                fallbackBanner
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
        let seed = Double(abs(app.displayName.hashValue % 100)) / 100.0
        let hue = (0.98 + seed * 0.04).truncatingRemainder(dividingBy: 1.0)
        let sat = 0.65 + seed * 0.2
        let bri = 0.30 + seed * 0.12

        return ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: sat, brightness: bri),
                            Color(hue: 0.0, saturation: 0.5, brightness: 0.15),
                            Color(white: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            LinearGradient(
                                colors: [Color.scarletRed.opacity(0.3), Color.white.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            Circle()
                .fill(RadialGradient(colors: [Color.scarletRed.opacity(0.3), .clear], center: .center, startRadius: 5, endRadius: 90))
                .frame(width: 180, height: 180)
                .offset(x: 90, y: -50)
                .blur(radius: 25)

            Circle()
                .fill(RadialGradient(colors: [Color(hue: 0.0, saturation: 0.7, brightness: 0.3).opacity(0.2), .clear], center: .center, startRadius: 5, endRadius: 70))
                .frame(width: 140, height: 140)
                .offset(x: -70, y: 40)
                .blur(radius: 20)

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
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill").font(.system(size: 9)).foregroundColor(.scarletRed.opacity(0.7))
                        Text(app.version ?? "1.0").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                        if app.size != nil {
                            Text("·").foregroundColor(.white.opacity(0.3))
                            Text(app.sizeString).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                        }
                    }

                    HStack(spacing: 3) {
                        Capsule().fill(Color.scarletRed.opacity(0.6)).frame(width: 30, height: 3)
                        Capsule().fill(Color.scarletRed.opacity(0.3)).frame(width: 16, height: 3)
                        Capsule().fill(Color.scarletRed.opacity(0.15)).frame(width: 8, height: 3)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                Button {
                    guard let urlStr = app.resolvedDownloadURL, let url = URL(string: urlStr) else { return }
                    DownloadManager.shared.download(id: app.id, url: url, appName: app.displayName, iconURL: app.resolvedIconURL, sizeString: app.sizeString) { fileURL in
                        ImportedAppsManager.shared.importIPA(from: fileURL)
                    }
                    switchToLibrary()
                } label: {
                    Text("GET")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [.scarletRed, .scarletDark], startPoint: .top, endPoint: .bottom))
                                .shadow(color: .scarletRed.opacity(0.4), radius: 6, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 180)
    }

    private var fallbackBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color.scarletRed.opacity(0.20), Color(white: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .scarletPink], startPoint: .top, endPoint: .bottom)
                    )
                Text(L("Sign & Install"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(L("Add a repo to see apps here"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(22)
        }
    }



    // MARK: - Repo Cards

    private var repoAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("REPOSITORIES"))
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

            ForEach(repoService.repos) { repo in
                NavigationLink(destination: RepoDetailView(repo: repo)) {
                    repoCard(repo)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(.white.opacity(0.2))
                    )
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

//
//  HomeView.swift
//  Scarlet
//
//  Home dashboard with premium liquid glass design.
//

import SwiftUI

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


    private func isInLibrary(_ app: RepoApp) -> Bool {
        let bid = app.bundleID ?? app.bundleIdentifier ?? ""
        let ver = app.resolvedVersion ?? ""
        let name = app.displayName
        return appsManager.apps.contains {
            // Match by bundle ID (preferred)
            if !bid.isEmpty && $0.bundleIdentifier == bid && (ver.isEmpty || $0.version == ver) { return true }
            // Fallback: match by app name
            if $0.appName.localizedCaseInsensitiveCompare(name) == .orderedSame { return true }
            return false
        }
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



            // ZStack so blur overlays the top of scroll content
            ZStack(alignment: .top) {
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

                    Spacer().frame(height: 100)
                }
                .padding(.top, 14)            }

            // Blur overlay on top of scroll — fades out downward
            LinearGradient(
                colors: [Color.bgPrimary, Color.bgPrimary.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 17)
            .allowsHitTesting(false)
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


    // MARK: - Repo Cards

    private var repoAppsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Local Repos (user-added, on top) ──
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

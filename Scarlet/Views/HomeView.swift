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
    @ObservedObject private var bannerService = BannerService.shared
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

            // Ambient scarlet glow
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.scarletRed.opacity(0.20),
                                Color.scarletDark.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 220
                        )
                    )
                    .frame(width: 400, height: 260)
                    .offset(y: -60)
                    .blur(radius: 40)
                    .scaleEffect(animateGlow ? 1.05 : 0.95)
                    .animation(
                        .easeInOut(duration: 4).repeatForever(autoreverses: true),
                        value: animateGlow
                    )
                Spacer()
            }
            .ignoresSafeArea()

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

    // MARK: - Hero Banner

    private var heroBanner: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentSlide) {
                ForEach(Array(bannerService.slides.enumerated()), id: \.element.safeId) { index, slide in
                    bannerSlideView(slide)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .animation(.easeInOut(duration: 0.4), value: currentSlide)
            .onReceive(slideTimer) { _ in
                guard bannerService.slides.count > 1 else { return }
                withAnimation {
                    currentSlide = (currentSlide + 1) % bannerService.slides.count
                }
            }

            // Page dots
            if bannerService.slides.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<bannerService.slides.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentSlide ? Color.scarletRed : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: currentSlide)
                    }
                }
            }
        }
    }

    private func bannerSlideView(_ slide: BannerSlide) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background: remote image or gradient
            if let imgKey = slide.imageURL, let img = bannerService.imageCache[imgKey] {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear, .black.opacity(0.3)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.scarletRed.opacity(0.30),
                                Color.scarletDark.opacity(0.20),
                                Color(white: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                    )
                // Watermark
                HStack {
                    Spacer()
                    Image(systemName: "signature")
                        .font(.system(size: 70, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.06))
                        .rotationEffect(.degrees(-10))
                        .offset(x: -20, y: -20)
                }
            }

            // Content
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(slide.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if let subtitle = slide.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                // Red CTA button
                if let btnText = slide.buttonText, !btnText.isEmpty {
                    Button {
                        if let urlStr = slide.buttonURL, let url = URL(string: urlStr) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text(btnText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.scarletRed)
                                    .shadow(color: .scarletRed.opacity(0.4), radius: 6, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
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

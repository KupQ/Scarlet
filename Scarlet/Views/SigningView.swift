//
//  SigningView.swift
//  Scarlet
//
//  Library tab — liquid glass design, preserving app icons/logos.
//

import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    @ObservedObject var signingState: SigningState
    var onAppTapped: (ImportedApp) -> Void

    @StateObject private var appsManager = ImportedAppsManager.shared
    @StateObject private var signedManager = SignedAppsManager.shared
    @State private var showIPAImportPicker = false
    @State private var signIconPulse = false
    @State private var libraryTab: Int = 0  // 0 = Unsigned, 1 = Signed

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .background(Color.bgPrimary)

                // Unsigned / Signed picker
                libraryPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if libraryTab == 0 {
                            // Unsigned tab
                            if appsManager.isImporting {
                                importingIndicator
                                    .padding(.top, 16)
                                    .padding(.horizontal, 20)
                            }

                            if appsManager.apps.isEmpty && !appsManager.isImporting && downloadManager.pendingDownloads.isEmpty {
                                emptyState.padding(.top, 60)
                            } else {
                                appsList.padding(.top, 20)
                            }
                        } else {
                            // Signed tab
                            if signedManager.signedApps.isEmpty {
                                signedEmptyState.padding(.top, 60)
                            } else {
                                signedAppsList.padding(.top, 20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 80)
                }
            }
            .navigationBarHidden(true)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showIPAImportPicker) {
            DocumentPicker(contentTypes: [.ipa]) { url in
                appsManager.importIPA(from: url)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Library"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(L("Imported Apps"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            Button { showIPAImportPicker = true } label: {
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
    }

    // MARK: - Library Picker

    private var libraryPicker: some View {
        HStack(spacing: 0) {
            pickerButton(title: L("Unsigned"), count: appsManager.apps.count, isActive: libraryTab == 0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { libraryTab = 0 }
            }
            pickerButton(title: L("Signed"), count: signedManager.signedApps.count, isActive: libraryTab == 1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { libraryTab = 1 }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func pickerButton(title: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isActive ? Color.scarletRed.opacity(0.3) : Color.white.opacity(0.06))
                    )
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Importing

    private var importingIndicator: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.scarletRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Importing..."))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(L("Extracting metadata and icon"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                                                    .fill(Color.white.opacity(0.03))
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.2))
            }
            VStack(spacing: 6) {
                Text(L("No Apps Imported"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Text(L("Tap + to import an IPA file"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
            Button { showIPAImportPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(L("Import IPA"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                                                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Apps List (split into installed + all)

    @StateObject private var installedManager = InstalledAppsManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    private var allAppsSorted: [ImportedApp] {
        appsManager.apps.sorted { $0.importDate > $1.importDate }
    }

    private var appsList: some View {
        VStack(spacing: 16) {
            // ── Downloading ──
            if !downloadManager.pendingDownloads.isEmpty {
                sectionHeader(title: L("Downloading"), count: downloadManager.pendingDownloads.count)
                VStack(spacing: 10) {
                    ForEach(downloadManager.pendingDownloads) { dl in
                        downloadingCard(dl)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                    }
                }
            }

            // ── All Apps (sign / re-sign) ──
            sectionHeader(title: L("All Apps"), count: allAppsSorted.count)
            VStack(spacing: 10) {
                ForEach(allAppsSorted) { app in
                    SwipeableAppCard(app: app, onTap: { signApp(app) }, onDelete: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            appsManager.removeApp(app)
                        }
                    }) {
                        unsignedCardContent(app)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Signed Empty State

    private var signedEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.2))
            }
            VStack(spacing: 6) {
                Text(L("No Signed Apps"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Text(L("Signed apps will appear here"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Signed Apps List

    private var signedAppsList: some View {
        VStack(spacing: 10) {
            ForEach(signedManager.signedApps) { app in
                SwipeableSignedCard(
                    onShare: {
                        let url = signedManager.ipaURL(for: app)
                        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(ac, animated: true)
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            signedManager.removeApp(app)
                        }
                    }
                ) {
                    signedAppCard(app)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 20)
    }

    private func signedAppCard(_ app: SignedApp) -> some View {
        HStack(spacing: 14) {
            if let iconURL = signedManager.iconURL(for: app),
               let data = try? Data(contentsOf: iconURL),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(LinearGradient(colors: [.scarletRed.opacity(0.3), .scarletDark.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.scarletRed)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(app.bundleId)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(app.formattedSize)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                    Text("·")
                        .foregroundColor(.white.opacity(0.15))
                    Text(app.formattedDate)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            Spacer()

            Button {
                let url = signedManager.ipaURL(for: app)
                let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    root.present(ac, animated: true)
                }
            } label: {
                Text(L("Install"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.scarletRed, .scarletDark],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .shadow(color: .scarletRed.opacity(0.3), radius: 4, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Downloading Card

    private func downloadingCard(_ dl: PendingDownload) -> some View {
        HStack(spacing: 14) {
            // Icon
            if let iconStr = dl.iconURL, let url = URL(string: iconStr) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.white.opacity(0.04))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(LinearGradient(colors: [.scarletRed.opacity(0.3), .scarletDark.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.scarletRed)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dl.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(dl.sizeString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
            }

            Spacer()

            // App Store-style circular progress ring (tap to cancel)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    downloadManager.cancelDownload(id: dl.id)
                }
            } label: {
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 3)
                        .frame(width: 32, height: 32)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: dl.progress)
                        .stroke(Color.scarletRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: dl.progress)

                    // Stop icon (square)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.scarletRed)
                        .frame(width: 10, height: 10)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.2))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.04)))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Installed Card

    private func installedCardContent(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            installedAppIcon(app)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(L("v\(app.version)"), systemImage: "number")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Label(validityText, systemImage: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            Spacer()

            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(Color.white.opacity(0.03))
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.scarletRed.opacity(0.8))
                }
                Text(L("Open"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func installedAppIcon(_ app: InstalledApp) -> some View {
        if let iconURL = app.iconURL,
           let data = try? Data(contentsOf: iconURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(colors: [.scarletRed, .scarletDark],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text(String(app.appName.prefix(1)))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Unsigned Card

    private func unsignedCardContent(_ app: ImportedApp) -> some View {
        HStack(spacing: 14) {
            appIcon(app)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(L("v\(app.version)"), systemImage: "number")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Text(app.formattedSize)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            Spacer()

            Text(L("Sign"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .overlay(PulseGlow(cornerRadius: 8))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Validity

    private var validityText: String {
        let certService = CertificateService.shared
        let settings = SigningSettings.shared
        if let name = settings.savedCertName,
           let cert = certService.certificates.first(where: { "\($0.id).p12" == name }) {
            let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
            return "\(days)d left"
        }
        return "—"
    }

    // MARK: - Icon

    @ViewBuilder
    private func appIcon(_ app: ImportedApp) -> some View {
        if let iconURL = app.iconURL,
           let data = try? Data(contentsOf: iconURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(colors: [.scarletRed, .scarletDark],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text(String(app.appName.prefix(1)))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Sign Action

    private func signApp(_ app: ImportedApp) {
        onAppTapped(app)
    }
}

// Isolated glow — manages own @State so parent never re-renders
struct PulseGlow: View {
    let cornerRadius: CGFloat
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            .opacity(on ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

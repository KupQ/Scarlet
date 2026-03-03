//
//  ContentView.swift
//  Scarlet
//
//  Root view that hosts the glass tab bar, three main tabs
//  (Home, Library, Settings), and the signing configuration
//  bottom sheet with three phases: configure, signing, success.
//

import SwiftUI

/// Root container with glass tab bar and three-phase signing bottom sheet.
struct ContentView: View {
    @StateObject private var signingState = SigningState()
    @ObservedObject private var certService = CertificateService.shared
    @ObservedObject private var repoService = RepoService.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var appsManager = ImportedAppsManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var selectedTab: Tab = .home
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showSettingsCard = false
    @State private var showCertsCard = false
    @State private var showPrefsCard = false
    @State private var showInfoCard = false
    @State private var certsDragOffset: CGFloat = 0
    @State private var prefsDragOffset: CGFloat = 0
    @State private var infoDragOffset: CGFloat = 0
    @State private var langExpanded = false
    @State private var settingsDragActive = false
    @State private var hoveredSettingsOption: Int? = nil
    @State private var showSettingsHint = !UserDefaults.standard.bool(forKey: "settingsHintDismissed")
    @State private var hintPulse = false
    @State private var handPhase = 0
    @State private var handLoopId = 0

    // Bottom sheet phases
    enum SheetPhase {
        case configure   // Show signing options
        case signing     // Progress
        case success     // Done, share
    }

    @State private var sheetPhase: SheetPhase = .configure
    @State private var sheetVisible = false
    @State private var sheetOffset: CGFloat = 500
    @State private var showCertPicker = false
    @State private var signingProgress: CGFloat = 0
    @State private var signingOutputURL: URL?
    @State private var showShareSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Per-sign overrides (pre-filled from app metadata)
    @State private var selectedApp: ImportedApp?
    @State private var signBundleId: String = ""
    @State private var signDisplayName: String = ""
    @State private var signVersion: String = ""
    @State private var signCompression: Int = 0
    @State private var signIconPulse = false

    enum Tab: Int, CaseIterable {
        case home, sign, settings
        var icon: String {
            switch self {
            case .home: return "house"
            case .sign: return "square.and.arrow.down"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep all tabs alive so navigation state is preserved
            NavigationView {
                HomeView(signingState: signingState, switchToLibrary: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .sign
                    }
                })
                .navigationBarHidden(true)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .opacity(selectedTab == .home ? 1 : 0)
            .animation(.none, value: selectedTab)
            .allowsHitTesting(selectedTab == .home)

            NavigationView {
                SigningView(signingState: signingState, onAppTapped: { app in
                    openConfigSheet(app)
                })
                .navigationBarHidden(true)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .opacity(selectedTab == .sign ? 1 : 0)
            .animation(.none, value: selectedTab)
            .allowsHitTesting(selectedTab == .sign)

            Color.bgPrimary.ignoresSafeArea()
                .opacity(selectedTab == .settings ? 1 : 0)
                .animation(.none, value: selectedTab)


            // Search results overlay (above content, below tab bar)
            if isSearching && !searchText.isEmpty {
                searchResultsOverlay
                    .zIndex(80)
            }

            // Settings card backdrop
            if showSettingsCard {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .zIndex(88)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSettingsCard = false
                        }
                    }
            }

            // Floating settings popup — glass drop-up
            if showSettingsCard {
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        settingsIconButton(icon: "shield", index: 0) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettingsCard = false
                                showCertsCard = true
                            }
                        }
                        settingsIconButton(icon: "slider.horizontal.3", index: 1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettingsCard = false
                                showPrefsCard = true
                            }
                        }
                        settingsIconButton(icon: "info.circle", index: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettingsCard = false
                                showInfoCard = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
                    )
                    .padding(.bottom, 116)
                }
                .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                .zIndex(92)
            }

            // Tab bar (ALWAYS on top so search field is visible)
            glassTabBar
                .zIndex(95)
                .onReceive(NotificationCenter.default.publisher(for: .switchToLibrary)) { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .sign
                    }
                }

            // Certificates liquid glass card
            if showCertsCard {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .zIndex(96)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showCertsCard = false
                        }
                    }

                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 0) {
                        // Drag handle
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 36, height: 4)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        // Embedded CertificatesView
                        CertificatesView()
                            .frame(height: UIScreen.main.bounds.height * 0.65)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .offset(y: certsDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    certsDragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showCertsCard = false
                                        certsDragOffset = 0
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        certsDragOffset = 0
                                    }
                                }
                            }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom))
                .zIndex(97)
            }

            // Language picker glass card
            // Info card overlay
            if showInfoCard {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .zIndex(98)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showInfoCard = false
                        }
                    }

                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 16) {
                        // Drag handle
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 36, height: 4)
                            .padding(.top, 10)

                        // App icon + name
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(RadialGradient(colors: [Color.scarletRed.opacity(0.15), .clear],
                                                         center: .center, startRadius: 0, endRadius: 40))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "app.fill")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.scarletRed, .scarletPink],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            }

                            Text("Scarlet")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)

                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }

                        // Developer info
                        VStack(spacing: 10) {
                            infoRow(icon: "person.fill", label: L("Developer"), value: "Scarlet Team")
                            infoRow(icon: "globe", label: L("Website"), value: "scarlet.app")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassCard(cornerRadius: 16)

                        // Credits
                        Text(L("Built with ❤️ for the community"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.2))
                            .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .offset(y: infoDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    infoDragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showInfoCard = false
                                        infoDragOffset = 0
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        infoDragOffset = 0
                                    }
                                }
                            }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom))
                .zIndex(99)
            }

            // Preferences card overlay
            if showPrefsCard {
                VStack {
                    Spacer()
                    preferencesCard
                        .offset(y: prefsDragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        prefsDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.height > 120 {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showPrefsCard = false
                                            prefsDragOffset = 0
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            prefsDragOffset = 0
                                        }
                                    }
                                }
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom))
                .zIndex(99)
            }

            // Dimmed backdrop
            if sheetVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if sheetPhase == .configure || sheetPhase == .success {
                            dismissSheet()
                        }
                    }
                    .zIndex(99)
            }

            // Bottom sheet — always on top
            if sheetVisible {
                bottomSheet
                    .offset(y: sheetOffset)
                    .transition(.move(edge: .bottom))
                    .zIndex(100)
            }
        }
        // Let keyboard push content up naturally
        .tint(Color.scarletRed)
        .onChange(of: signingState.phase) { newPhase in
            switch newPhase {
            case .success(let url):
                signingOutputURL = url
                if let app = selectedApp {
                    // Save signed IPA to SignedAppsManager
                    let settings = SigningSettings.shared
                    SignedAppsManager.shared.saveSignedIPA(
                        sourceURL: url,
                        appName: settings.displayName.isEmpty ? app.appName : settings.displayName,
                        bundleId: settings.bundleId.isEmpty ? app.bundleIdentifier : settings.bundleId,
                        version: settings.version.isEmpty ? app.version : settings.version,
                        iconURL: app.iconURL
                    )
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        ImportedAppsManager.shared.markAsSigned(app)
                    }
                    // Start local server for OTA Install button
                    signingState.prepareInstall(app: app, outputURL: url)

                    // Send notification if backgrounded
                    if UIApplication.shared.applicationState != .active {
                        NotificationHelper.send(
                            title: L("Signing Complete"),
                            body: String(format: L("%@ has been signed successfully"), app.appName)
                        )
                    }
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    signingProgress = 1.0
                    sheetPhase = .success
                }
            case .failure(let msg):
                errorMessage = msg
                showErrorAlert = true
                dismissSheet()
            default: break
            }
        }
        .alert(L("Signing Failed"), isPresented: $showErrorAlert) {
            Button(L("OK")) { signingState.phase = .selectingFiles }
        } message: { Text(errorMessage) }
        .sheet(isPresented: $showShareSheet) {
            if let url = signingOutputURL { ShareSheet(items: [url]) }
        }
        .task {
            // Fetch certs and check OCSP at app launch, regardless of which tab is active
            await certService.fetchCertificates()
            await LocalCertChecker.shared.checkAPICertsIfNeeded(certService.certificates)
            // Check local certs too
            let localJSON = UserDefaults.standard.string(forKey: "local_imported_certs_json") ?? "[]"
            if let data = localJSON.data(using: .utf8),
               let localCerts = try? JSONDecoder().decode([LocalImportedCert].self, from: data) {
                let pairs = localCerts.map { (name: $0.filename, password: $0.password) }
                await LocalCertChecker.shared.checkAllLocalCerts(certs: pairs)
            }
        }
    }

    // MARK: - Open Config Sheet

    private func openConfigSheet(_ app: ImportedApp) {
        selectedApp = app
        signBundleId = app.bundleIdentifier
        signDisplayName = app.appName
        signVersion = app.version
        signCompression = SigningSettings.shared.zipCompression
        signingProgress = 0
        signingOutputURL = nil
        sheetPhase = .configure

        // Auto-select the first certificate if none is selected
        if SigningSettings.shared.savedCertName == nil {
            let json = UserDefaults.standard.string(forKey: "local_imported_certs_json") ?? "[]"
            if let data = json.data(using: .utf8),
               let locals = try? JSONDecoder().decode([LocalImportedCert].self, from: data),
               let first = locals.first {
                SigningSettings.shared.savedCertName = first.filename
            } else if let firstAPI = certService.certificates.first {
                certService.useCertificate(firstAPI)
            }
        }

        sheetVisible = true
        sheetOffset = 500
        withAnimation(.easeOut(duration: 0.45)) {
            sheetOffset = 0
        }
    }

    private func dismissSheet() {
        signingState.cancelAll()
        withAnimation(.easeIn(duration: 0.3)) {
            sheetOffset = 500
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            sheetVisible = false
        }
    }

    /// Removes all scarlet_* temp dirs created during signing to keep device clean.
    private func cleanupSignedFiles() {
        let tmp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(atPath: tmp.path) {
            for item in items where item.hasPrefix("scarlet_") {
                try? FileManager.default.removeItem(at: tmp.appendingPathComponent(item))
            }
        }
    }

    /// Drag gesture for the entire bottom sheet — uses simple onChanged/onEnded
    /// with direct offset assignment, no @GestureState or animations during drag.
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                // Only allow dragging downward; rubber-band resist upward
                sheetOffset = dy > 0 ? dy : dy * 0.1
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height
                if value.translation.height > 100 || velocity > 300 {
                    dismissSheet()
                } else {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25)) {
                        sheetOffset = 0
                    }
                }
            }
    }

    // MARK: - Bottom Sheet

    @ViewBuilder
    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 4)

            switch sheetPhase {
            case .configure:
                configureContent
            case .signing:
                signingContent
            case .success:
                successContent
            }
        }
        .background(sheetBackground)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .gesture(sheetDragGesture)
    }

    // MARK: - Phase 1: Configure

    private var configureContent: some View {
        let localChecker = LocalCertChecker.shared
        let localCertsJSON = UserDefaults.standard.string(forKey: "local_imported_certs_json") ?? "[]"
        let localCerts: [LocalImportedCert] = {
            guard let data = localCertsJSON.data(using: .utf8),
                  let certs = try? JSONDecoder().decode([LocalImportedCert].self, from: data) else { return [] }
            return certs
        }()

        return VStack(spacing: 12) {
            // App header with reload button
            if let app = selectedApp {
                HStack(spacing: 12) {
                    appIconView(app)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.appName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(app.formattedSize)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()

                    // Sign action
                    Button {
                        startSigning()
                    } label: {
                        Text(L("Sign"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
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
                    .buttonStyle(.plain)
                    .disabled(!SigningSettings.shared.hasCertificate)
                    .opacity(SigningSettings.shared.hasCertificate ? 1.0 : 0.35)
                }
            }

            // Editable fields
            configField(icon: "textformat", label: L("App Name"), text: $signDisplayName)
            configField(icon: "app.badge", label: L("Bundle ID"), text: $signBundleId)
            configField(icon: "number", label: L("Version"), text: $signVersion)

            // Compression picker
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 14))
                    .foregroundColor(.scarletRed)
                    .frame(width: 20)
                Text(L("Compression"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Picker("", selection: $signCompression) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("6").tag(6)
                    Text("9").tag(9)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            // Certificate — symbol row style, tappable to expand list
            VStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCertPicker.toggle()
                    }
                    if showCertPicker && certService.certificates.isEmpty {
                        Task { await certService.fetchCertificates() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shield")
                            .font(.system(size: 16))
                            .foregroundColor(.scarletRed)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Certificate"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                            certDisplayText
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: showCertPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)

                // Expandable cert list
                if showCertPicker {
                    VStack(spacing: 4) {
                        // API certs
                        ForEach(certService.certificates) { cert in
                            let isActive = SigningSettings.shared.savedCertName == "\(cert.id).p12"
                            let status = localChecker.statusFor(cert.id)
                            let isDev = (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")

                            Button {
                                certService.useCertificate(cert)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCertPicker = false
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(cert.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        if isActive {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        // Status
                                        HStack(spacing: 3) {
                                            Image(systemName: statusIcon(status))
                                                .font(.system(size: 8, weight: .bold))
                                            Text(statusLabel(status))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(statusColor(status))
                                        // Type
                                        HStack(spacing: 3) {
                                            Image(systemName: isDev ? "hammer" : "building.2")
                                                .font(.system(size: 8, weight: .bold))
                                            Text(isDev ? L("Development") : L("Distribution"))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(.white.opacity(0.3))
                                        // PPQ
                                        HStack(spacing: 3) {
                                            Image(systemName: cert.isPPQEnabled ? "lock.fill" : "lock.open")
                                                .font(.system(size: 8, weight: .bold))
                                            Text(cert.isPPQEnabled ? L("PPQ") : L("PPQless"))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(.white.opacity(0.3))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isActive ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Local certs
                        ForEach(localCerts, id: \.filename) { cert in
                            let isActive = SigningSettings.shared.savedCertName == cert.filename
                            let info = localChecker.localCertInfos[cert.filename]
                            let status = info?.status ?? .checking
                            let certName = info?.commonName ?? cert.filename.replacingOccurrences(of: ".p12", with: "").replacingOccurrences(of: "local_", with: "")

                            Button {
                                SigningSettings.shared.savedCertName = cert.filename
                                SigningSettings.shared.savedCertPassword = cert.password
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCertPicker = false
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(certName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        if isActive {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        // Status
                                        HStack(spacing: 3) {
                                            Image(systemName: statusIcon(status))
                                                .font(.system(size: 8, weight: .bold))
                                            Text(statusLabel(status))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(statusColor(status))
                                        // Local
                                        HStack(spacing: 3) {
                                            Image(systemName: "externaldrive")
                                                .font(.system(size: 8, weight: .bold))
                                            Text(L("Local"))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(.white.opacity(0.3))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isActive ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if certService.certificates.isEmpty && localCerts.isEmpty {
                            Text(L("No certificates available"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                                .padding(.vertical, 8)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    // Current cert display row
    private var certDisplayRow: some View {
        let localChecker = LocalCertChecker.shared
        let settings = SigningSettings.shared
        let localCertsJSON = UserDefaults.standard.string(forKey: "local_imported_certs_json") ?? "[]"
        let localCerts: [LocalImportedCert] = {
            guard let data = localCertsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([LocalImportedCert].self, from: data) else { return [] }
            return decoded
        }()

        return HStack(spacing: 10) {
            // Status dot instead of green checkmark
            Group {
                if let savedName = settings.savedCertName {
                    if let cert = certService.certificates.first(where: { "\($0.id).p12" == savedName }) {
                        certStatusDot(localChecker.statusFor(cert.id))
                    } else if let localCert = localCerts.first(where: { $0.filename == savedName }) {
                        let status = localChecker.localCertInfos[localCert.filename]?.status ?? .checking
                        certStatusDot(status)
                    } else {
                        certStatusDot(.error(L("Not found")))
                    }
                } else {
                    certStatusDot(.error(L("None")))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Certificate"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                certDisplayText
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // Cert status helpers for signing sheet
    private func certStatusDot(_ status: LocalCertInfo.CertStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: LocalCertInfo.CertStatus) -> Color {
        switch status {
        case .valid: return Color(red: 0.2, green: 0.75, blue: 0.4)
        case .revoked: return Color(red: 0.95, green: 0.25, blue: 0.25)
        case .expired: return .orange
        case .checking: return .yellow
        case .error: return .gray
        }
    }

    private func statusLabel(_ status: LocalCertInfo.CertStatus) -> String {
        status.label
    }

    private func statusIcon(_ status: LocalCertInfo.CertStatus) -> String {
        switch status {
        case .valid: return "checkmark.shield"
        case .revoked: return "xmark.shield"
        case .expired: return "clock.badge.xmark"
        case .checking: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }

    // Certificate display text showing actual cert name + type
    private var certDisplayText: Text {
        guard SigningSettings.shared.hasCertificate else {
            return Text(L("Tap to select"))
        }
        if let savedName = SigningSettings.shared.savedCertName,
           let matchingCert = certService.certificates.first(where: { "\($0.id).p12" == savedName }) {
            let typeStr = certTypeLabel(matchingCert.cert_type)
            return Text(matchingCert.name) + Text(" · \(typeStr)").foregroundColor(typeStr == L("Development") ? .blue.opacity(0.6) : .orange.opacity(0.6))
        }
        // Local cert
        if let savedName = SigningSettings.shared.savedCertName {
            let localChecker = LocalCertChecker.shared
            if let info = localChecker.localCertInfos[savedName] {
                return Text(info.commonName) + Text(L(" · Local")).foregroundColor(.white.opacity(0.3))
            }
            let cleanName = savedName.replacingOccurrences(of: ".p12", with: "").replacingOccurrences(of: "local_", with: "")
            return Text(cleanName) + Text(L(" · Local")).foregroundColor(.white.opacity(0.3))
        }
        return Text(L("Tap to select"))
    }

    private func certTypeLabel(_ type: String?) -> String {
        guard let t = type?.uppercased() else { return "Certificate" }
        if t.contains("DEVELOPMENT") || t.contains("DEV") { return "Development" }
        if t.contains("DISTRIBUTION") || t.contains("DISTRO") || t.contains("DIST") { return "Distribution" }
        return type ?? "Certificate"
    }

    private func configField(icon: String, label: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(!text.wrappedValue.isEmpty ? .scarletRed : .gray)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                TextField(label, text: text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Phase 2: Signing Progress

    private var signingContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.glassFill, lineWidth: 4)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: signingProgress)
                        .stroke(
                            AngularGradient(
                                colors: [.scarletDark, .scarletRed, .scarletPink, .scarletRed],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(signingProgress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedApp?.appName ?? L("Signing..."))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(progressStatusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.glassFill).frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [.scarletRed, .scarletPink], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * signingProgress, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            // App info during signing
            HStack(spacing: 16) {
                infoChip(label: L("Bundle"), value: signBundleId.isEmpty ? "—" : signBundleId)
                infoChip(label: L("Version"), value: signVersion.isEmpty ? "—" : signVersion)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.2))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.03))
        )
    }

    private var currentCertDisplayName: String? {
        guard let savedName = SigningSettings.shared.savedCertName else { return nil }
        if let cert = certService.certificates.first(where: { "\($0.id).p12" == savedName }) {
            return "\(cert.name) · \(certTypeLabel(cert.cert_type))"
        }
        return savedName
    }

    // MARK: - Phase 3: Success

    private var successContent: some View {
        VStack(spacing: 14) {
            // App icon + status + install button
            HStack(spacing: 14) {
                // App icon — NO circle behind it
                if let iconURL = selectedApp?.iconURL,
                   let iconData = try? Data(contentsOf: iconURL),
                   let uiImage = UIImage(data: iconData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                } else {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(colors: [.scarletRed, .scarletDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Text(String(selectedApp?.appName.prefix(1) ?? "?"))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedApp?.appName ?? L("Done"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    installStatusText
                    if signingState.installStatus != .completed {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LinearGradient(colors: [.scarletRed, .scarletDark],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * installProgressValue, height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                Spacer(minLength: 0)

                // Actions
                if signingState.installStatus == .completed {
                    Button {
                        InstallProgressPoller.openApp(bundleId: signingState.installingBundleId)
                    } label: {
                        Text(L("Open"))
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
                    .buttonStyle(.plain)
                } else if signingState.isUploading {
                    VStack(spacing: 3) {
                        ProgressView().tint(.scarletRed).scaleEffect(0.8)
                        Text(L("Installing"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                } else if let url = signingState.installURL,
                          signingState.installStatus != .completed {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.scarletRed)
                            Text(L("Install"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // App info
            HStack(spacing: 12) {
                infoChip(label: L("Bundle"), value: signBundleId.isEmpty ? "—" : signBundleId)
                infoChip(label: L("Version"), value: signVersion.isEmpty ? "—" : signVersion)
            }


        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        // Auto-reset stuck sendingManifest after timeout
        .onChange(of: signingState.installStatus) { newStatus in
            if case .sendingManifest = newStatus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if case .sendingManifest = signingState.installStatus {
                        signingState.resetStuckInstall()
                    }
                }
            }
            if case .completed = newStatus {
                if let app = selectedApp {
                    InstalledAppsManager.shared.add(from: app)
                }
                cleanupSignedFiles()
            }
        }
    }

    // MARK: - Install Status Helpers

    /// Dynamic status text based on install status.
    @ViewBuilder
    private var installStatusText: some View {
        switch signingState.installStatus {
        case .sendingManifest:
            Text(L("Sending Manifest..."))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        case .sendingPayload:
            Text(L("Sending Payload..."))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        case .installing(let progress):
            Text("\(L("Installing")) \(Int(progress * 100))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.scarletRed)
        case .completed:
            Text(L("Installed ✓"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.scarletRed)
        case .failed(let msg):
            Text("\(L("Error")): \(msg)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        default:
            Text(L("Signed Successfully!"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    /// Progress value (0–1) based on install status.
    private var installProgressValue: CGFloat {
        switch signingState.installStatus {
        case .sendingManifest: return 0.1
        case .sendingPayload: return 0.3
        case .installing(let progress): return 0.3 + CGFloat(progress) * 0.7
        case .completed: return 1.0
        default: return 1.0
        }
    }

    // MARK: - Signing Logic

    private func startSigning() {
        guard let app = selectedApp else { return }

        // Save overrides to settings
        let settings = SigningSettings.shared
        settings.bundleId = signBundleId == app.bundleIdentifier ? "" : signBundleId
        settings.displayName = signDisplayName == app.appName ? "" : signDisplayName
        settings.version = signVersion == app.version ? "" : signVersion
        settings.zipCompression = signCompression

        // Transition to signing phase
        withAnimation(.easeInOut(duration: 0.3)) {
            sheetPhase = .signing
        }

        // Start progress animation
        let steps: [(CGFloat, TimeInterval)] = [
            (0.12, 0.3), (0.25, 0.7), (0.38, 1.2),
            (0.48, 2.0), (0.58, 3.0), (0.68, 4.0),
            (0.78, 5.5), (0.85, 7.0), (0.92, 9.0),
        ]
        for (progress, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    if sheetPhase == .signing { signingProgress = progress }
                }
            }
        }

        // Kick off actual signing
        signingState.reset()
        signingState.ipaFile = SelectedFile(url: app.ipaURL, name: app.fileName, size: app.fileSize)
        signingState.startSigning()
    }

    private var progressStatusText: String {
        if signingProgress < 0.25 { return "Extracting IPA..." }
        else if signingProgress < 0.55 { return "Signing binaries..." }
        else if signingProgress < 0.85 { return "Re-packaging..." }
        else { return "Finishing up..." }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func appIconView(_ app: ImportedApp) -> some View {
        if let iconURL = app.iconURL,
           let data = try? Data(contentsOf: iconURL),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.scarletRed, .scarletDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(app.appName.prefix(1)))
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            }
        }
    }

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
    }

    // MARK: - Tab Bar

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            if isSearching {
                // Search mode
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    TextField(L("Search apps..."), text: $searchText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .tint(.scarletRed)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            searchText = ""
                            isSearching = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
            } else {
                // Normal tab mode
                ForEach(Tab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                }
                // Divider
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1.5, height: 28)
                    .padding(.horizontal, 4)

                // Search button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSearching = true
                        showSettingsCard = false
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(.gray.opacity(0.6))
                        Capsule()
                            .fill(Color.clear)
                            .frame(width: 14, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, isSearching ? 20 : 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, isSearching ? 16 : 24)
        .padding(.bottom, 20)
    }

    private func tabButton(_ tab: Tab) -> some View {
        if tab == .settings {
            return AnyView(settingsTabButton)
        } else {
            return AnyView(
                Button {
                    selectedTab = tab
                    showSettingsCard = false
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 32, weight: selectedTab == tab ? .light : .thin))
                            .foregroundColor(selectedTab == tab ? .scarletRed : .gray.opacity(0.6))
                        Capsule()
                            .fill(selectedTab == tab ? Color.white : .clear)
                            .frame(width: 14, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            )
        }
    }

    private var settingsTabButton: some View {
        VStack(spacing: 6) {
            Image(systemName: Tab.settings.icon)
                .font(.system(size: 32, weight: showSettingsCard ? .light : .thin))
                .foregroundColor(showSettingsCard ? .scarletRed : .gray.opacity(0.6))
            Capsule()
                .fill(showSettingsCard ? Color.white : .clear)
                .frame(width: 14, height: 2.5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSettingsCard.toggle()
                hoveredSettingsOption = nil
            }
        }
        .overlay(alignment: .top) {
            if showSettingsHint && !showSettingsCard && !isSearching {
                VStack(spacing: 2) {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.scarletRed)
                            .offset(
                                x: handPhase == 3 ? -5 : (handPhase == 5 ? 5 : 0)
                            )
                            .scaleEffect(handPhase == 1 ? 0.88 : 1.0)
                            .animation(.easeInOut(duration: 0.35), value: handPhase)
                        Text(L("Hold to open"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white)
                            .fixedSize()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .fixedSize()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.scarletRed.opacity(hintPulse ? 0.5 : 0.2), lineWidth: 1)
                            )
                            .shadow(color: .scarletRed.opacity(hintPulse ? 0.25 : 0.08), radius: hintPulse ? 12 : 5)
                    )

                    // Arrow pointing down
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                }
                .fixedSize()
                .offset(y: -82)
                .transition(.opacity)
                .onAppear {
                    hintPulse = false
                    handPhase = 0
                    handLoopId += 1
                    let currentLoopId = handLoopId
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        hintPulse = true
                    }
                    func runHandLoop() {
                        guard showSettingsHint, handLoopId == currentLoopId else { return }
                        handPhase = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { guard handLoopId == currentLoopId else { return }; handPhase = 1 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { guard handLoopId == currentLoopId else { return }; handPhase = 2 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { guard handLoopId == currentLoopId else { return }; handPhase = 5 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) { guard handLoopId == currentLoopId else { return }; handPhase = 3 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) { guard handLoopId == currentLoopId else { return }; handPhase = 4 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) { guard handLoopId == currentLoopId else { return }; handPhase = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) { runHandLoop() }
                    }
                    runHandLoop()
                }
            }
        }
        .simultaneousGesture(
             LongPressGesture(minimumDuration: 0.1)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    switch value {
                    case .first(true):
                        // Long press recognized — show popup
                        if !showSettingsCard {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettingsCard = true
                                settingsDragActive = true
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                    case .second(true, let drag):
                        // Dragging — compute which option is hovered
                        guard let drag else { return }
                        let y = drag.location.y
                        let x = drag.location.x
                        let screenW = UIScreen.main.bounds.width
                        let screenH = UIScreen.main.bounds.height
                        // Wider detection zone
                        let centerX = screenW / 2
                        let startX = centerX - 105
                        if y < screenH - 60 && y > screenH - 300 {
                            let relX = x - startX
                            if relX >= 0 && relX < 70 {
                                hoveredSettingsOption = 0
                            } else if relX >= 70 && relX < 140 {
                                hoveredSettingsOption = 1
                            } else if relX >= 140 && relX < 210 {
                                hoveredSettingsOption = 2
                            } else {
                                hoveredSettingsOption = nil
                            }
                        } else {
                            hoveredSettingsOption = nil
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    if settingsDragActive {
                        // Dismiss hint after a delay so user sees it worked
                        if showSettingsHint {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showSettingsHint = false }
                                UserDefaults.standard.set(true, forKey: "settingsHintDismissed")
                            }
                        }
                        // Fire the hovered option
                        if let option = hoveredSettingsOption {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettingsCard = false
                                switch option {
                                case 0: showCertsCard = true
                                case 1: showPrefsCard = true
                                case 2: showInfoCard = true
                                default: break
                                }
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                        settingsDragActive = false
                        hoveredSettingsOption = nil
                    }
                }
        )
    }

    // MARK: - Import Overlay

    @State private var importShimmer = false

    private var importOverlay: some View {
        VStack {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.scarletRed.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.scarletRed)
                            .scaleEffect(importShimmer ? 1.1 : 0.9)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: importShimmer)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Importing..."))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(appsManager.importingFileName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                // Indeterminate progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(colors: [.scarletRed.opacity(0.6), .scarletRed, .scarletRed.opacity(0.6)],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: importShimmer ? geo.size.width * 0.65 : 0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: importShimmer)
                    }
                }
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: .scarletRed.opacity(0.1), radius: 12)
            )
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .onAppear { importShimmer = true }
            .onDisappear { importShimmer = false }

            Spacer()
        }
    }

    // MARK: - Preferences Card

    @State private var notificationsEnabled = NotificationHelper.isEnabled

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text(L("Preferences"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                // Language selector (dropdown)
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            langExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 16))
                                .foregroundColor(.scarletRed)
                                .frame(width: 20)
                            Text(L("Language"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text(LanguageManager.supportedLanguages.first { $0.id == langManager.currentLanguage }?.name ?? "English")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                            Image(systemName: langExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if langExpanded {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)

                        VStack(spacing: 2) {
                            ForEach(LanguageManager.supportedLanguages) { lang in
                                let isSelected = langManager.currentLanguage == lang.id
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        langManager.currentLanguage = lang.id
                                        langExpanded = false
                                    }
                                } label: {
                                    HStack {
                                        Text(lang.name)
                                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.scarletRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? Color.scarletRed.opacity(0.08) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .glassCard(cornerRadius: 14)

                // Notifications toggle
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.scarletRed)
                        .frame(width: 20)
                    Text(L("Notifications"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .tint(.scarletRed)
                        .onChange(of: notificationsEnabled) { value in
                            NotificationHelper.isEnabled = value
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 14)

                // Cache — compact row with inline trash icon
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 16))
                        .foregroundColor(.scarletRed)
                        .frame(width: 20)
                    Text(L("Cache"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(cacheSizeFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            ImportedAppsManager.shared.clearAll()
                            SignedAppsManager.shared.clearAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.7))
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    /// Total cache: unsigned apps + signed apps
    private var cacheSizeFormatted: String {
        let signedSize = SignedAppsManager.shared.totalCacheSize
        let unsignedSize = ImportedAppsManager.shared.totalCacheSize
        return ByteCountFormatter.string(fromByteCount: signedSize + unsignedSize, countStyle: .file)
    }

    // MARK: - Info Row Helper

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.scarletRed)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
    }

    // MARK: - Settings Icon Button

    private func settingsIconButton(icon: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: hoveredSettingsOption == index ? .regular : .thin))
                .foregroundColor(hoveredSettingsOption == index ? .white : .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hoveredSettingsOption == index ? Color.scarletRed.opacity(0.4) : .clear)
                        .shadow(color: hoveredSettingsOption == index ? .scarletRed.opacity(0.6) : .clear, radius: 10)
                        .animation(.easeOut(duration: 0.08), value: hoveredSettingsOption)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Results

    private var searchResultsOverlay: some View {
        let filtered = repoService.searchableApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(spacing: 0) {
            Spacer().frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { app in
                        searchResultRow(app)
                    }
                    if filtered.isEmpty {
                        Text(L("No apps found"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func searchResultRow(_ app: RepoApp) -> some View {
        let progress = downloadManager.activeDownloads[app.id]

        return HStack(spacing: 14) {
            if let iconStr = app.resolvedIconURL, let url = URL(string: iconStr) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.white.opacity(0.05))
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(app.resolvedVersion ?? "?") • \(app.sizeString)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                    // Repo source badge (only in global search)
                    if repoService.activeRepo == nil,
                       let repoName = repoService.repoName(for: app) {
                        Text(repoName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.scarletRed.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.scarletRed.opacity(0.1))
                            )
                    }
                }
            }
            Spacer()
            if let p = progress {
                Text("\(Int(p * 100))%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.scarletRed)
                    .frame(width: 50)
            } else {
                Button { downloadFromSearch(app) } label: {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func downloadFromSearch(_ app: RepoApp) {
        guard let dlStr = app.resolvedDownloadURL, let url = URL(string: dlStr) else { return }
        withAnimation { isSearching = false; searchText = "" }
        selectedTab = .sign

        downloadManager.download(
            id: app.id, url: url,
            appName: app.displayName, iconURL: app.resolvedIconURL, sizeString: app.sizeString
        ) { savedURL in
            // File is already saved in Application Support/Downloads by DownloadManager
            ImportedAppsManager.shared.importIPA(from: savedURL)
        }
    }
}

// MARK: - Slide to Action Component

/// Apple power-off inspired slide control with animated hint arrows.
/// Slide-to-action matching the app's glass card design language.
struct SlideToActionView: View {
    let text: String
    let gradient: [Color]
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var triggered = false
    @State private var shimmer: CGFloat = -1

    private let h: CGFloat = 50
    private let thumbW: CGFloat = 46
    private let cr: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - thumbW - 8
            let pct = travel > 0 ? min(offset / travel, 1) : 0

            ZStack(alignment: .leading) {
                // ── Glass card track (same as home quick actions) ──
                RoundedRectangle(cornerRadius: cr)
                                                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: cr)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                // ── Scarlet reveal ──
                RoundedRectangle(cornerRadius: cr)
                    .fill(
                        LinearGradient(
                            colors: [gradient[0].opacity(0.12 * Double(pct)),
                                     gradient[1].opacity(0.06 * Double(pct))],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbW + 8, thumbW + offset + 4))
                    .animation(.none, value: offset)

                // ── Text with shimmer ──
                ZStack {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.3 * (1 - pct)))

                    // Shimmer sweep over text
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.clear)
                        .overlay(
                            GeometryReader { textGeo in
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.4), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: 50)
                                .offset(x: shimmer * textGeo.size.width)
                                .mask(
                                    Text(text)
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                )
                            }
                        )
                        .opacity(1 - Double(pct))
                }
                .frame(maxWidth: .infinity)
                .offset(x: 16)

                // ── Thumb — mini glass card ──
                RoundedRectangle(cornerRadius: cr - 4)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: thumbW, height: h - 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: cr - 4)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.20), .white.opacity(0.06)],
                                    startPoint: .top, endPoint: .bottom
                                ), lineWidth: 0.5
                            )
                    )
                    .overlay(
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(gradient[0].opacity(0.25))
                                .frame(width: 30, height: 30)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(gradient[0].opacity(0.9))
                        }
                    )
                    .offset(x: 4 + offset)
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { v in
                                guard !triggered else { return }
                                offset = max(0, min(v.translation.width, travel))
                            }
                            .onEnded { _ in
                                guard !triggered else { return }
                                if offset >= travel * 0.85 {
                                    triggered = true
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    withAnimation(.easeOut(duration: 0.1)) { offset = travel }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        action()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                offset = 0
                                                triggered = false
                                            }
                                        }
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: h)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmer = 1
            }
        }
    }
}

// MARK: - Flat Scarlet Action Button

/// Flat dark button with spinning scarlet arc and ambient blood glow.
/// Matches the app's flat dark aesthetic — no glass, no 3D.
struct ScarletSignButton: View {
    let icon: String
    let action: () -> Void
    var accentColor: Color = .scarletRed
    var size: CGFloat = 48

    @State private var arcRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Ambient blood glow
                Circle()
                    .fill(accentColor.opacity(0.10))
                    .frame(width: size + 16, height: size + 16)
                    .blur(radius: 12)
                    .scaleEffect(pulseScale)

                // Spinning scarlet arc
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.8), accentColor.opacity(0.05)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: size + 2, height: size + 2)
                    .rotationEffect(.degrees(arcRotation))

                // Flat dark fill
                Circle()
                    .fill(Color(red: 0.12, green: 0.03, blue: 0.04))
                    .frame(width: size - 4, height: size - 4)
                    .overlay(
                        Circle()
                            .stroke(accentColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: accentColor.opacity(0.3), radius: 10, y: 2)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .heavy))
                    .foregroundColor(accentColor.opacity(0.9))
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                arcRotation = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

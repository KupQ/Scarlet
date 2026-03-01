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
    @State private var selectedTab: Tab = .home

    // Bottom sheet phases
    enum SheetPhase {
        case configure   // Show signing options
        case signing     // Progress
        case success     // Done, share
    }

    @State private var sheetPhase: SheetPhase = .configure
    @State private var sheetVisible = false
    @State private var sheetOffset: CGFloat = 600
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

    enum Tab: Int, CaseIterable {
        case home, sign, certs
        var icon: String {
            switch self {
            case .home: return "house"
            case .sign: return "square.and.arrow.down"
            case .certs: return "magnifyingglass"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeView(signingState: signingState, switchToLibrary: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = .sign
                            }
                        })
                    }
                case .sign:
                    NavigationStack {
                        SigningView(signingState: signingState, onAppTapped: { app in
                            openConfigSheet(app)
                        })
                    }
                case .certs:
                    NavigationStack { CertificatesView() }
                }
            }

            // Tab bar
            glassTabBar

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
        .ignoresSafeArea(.keyboard)
        .tint(Color.scarletRed)
        .onChange(of: signingState.phase) { newPhase in
            switch newPhase {
            case .success(let url):
                signingOutputURL = url
                if let app = selectedApp {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        ImportedAppsManager.shared.markAsSigned(app)
                    }
                    // Start local server for OTA Install button
                    signingState.prepareInstall(app: app, outputURL: url)
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
        .alert("Signing Failed", isPresented: $showErrorAlert) {
            Button("OK") { signingState.phase = .selectingFiles }
        } message: { Text(errorMessage) }
        .sheet(isPresented: $showShareSheet) {
            if let url = signingOutputURL { ShareSheet(items: [url]) }
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

        sheetVisible = true
        sheetOffset = 600
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            sheetOffset = 0
        }
    }

    private func dismissSheet() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sheetOffset = 600
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            sheetVisible = false
            signingState.stopLocalServer()
            signingState.reset()
        }
    }

    // MARK: - Bottom Sheet

    @ViewBuilder
    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

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
    }

    // MARK: - Phase 1: Configure

    private var configureContent: some View {
        VStack(spacing: 14) {
            // App header
            if let app = selectedApp {
                HStack(spacing: 14) {
                    appIconView(app)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.appName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(app.formattedSize)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Certificate
            HStack(spacing: 12) {
                Image(systemName: SigningSettings.shared.hasCertificate ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundColor(SigningSettings.shared.hasCertificate ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Certificate")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(SigningSettings.shared.savedCertName ?? "No certificate — add in Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SigningSettings.shared.hasCertificate ? .gray : .red)
                        .lineLimit(1)
                }
                Spacer()
            }

            Divider().background(Color.white.opacity(0.1))

            // Editable fields
            configField(icon: "textformat", label: "App Name", text: $signDisplayName)
            configField(icon: "app.badge", label: "Bundle ID", text: $signBundleId)
            configField(icon: "number", label: "Version", text: $signVersion)

            // Compression picker
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
                    .frame(width: 20)
                Text("Compression")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Picker("", selection: $signCompression) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("6").tag(6)
                    Text("9").tag(9)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            // Sign button
            Button { startSigning() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "signature")
                        .font(.system(size: 16, weight: .bold))
                    Text("Sign")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            SigningSettings.shared.hasCertificate
                                ? LinearGradient.scarletButtonGradient
                                : LinearGradient(colors: [.gray.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                        )
                )
                .shadow(color: .scarletRed.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!SigningSettings.shared.hasCertificate)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.glassFill, lineWidth: 4)
                    .frame(width: 58, height: 58)
                Circle()
                    .trim(from: 0, to: signingProgress)
                    .stroke(
                        AngularGradient(
                            colors: [.scarletDark, .scarletRed, .scarletPink, .scarletRed],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(signingProgress * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedApp?.appName ?? "Signing...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(progressStatusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.glassFill).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.scarletRed, .scarletPink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * signingProgress, height: 5)
                    }
                }
                .frame(height: 5)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(Color.scarletRed)
                .frame(width: 10, height: 10)
                .scaleEffect(1.3)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: signingProgress)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    // MARK: - Phase 3: Success

    private var successContent: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.glassFill, lineWidth: 4)
                    .frame(width: 58, height: 58)
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(
                        AngularGradient(colors: [.green.opacity(0.5), .green, .green.opacity(0.8)], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))
                if let iconURL = selectedApp?.iconURL,
                   let iconData = try? Data(contentsOf: iconURL),
                   let uiImage = UIImage(data: iconData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.green)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedApp?.appName ?? "Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                installStatusText
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * installProgressValue, height: 5)
                        .animation(.easeInOut(duration: 0.3), value: installProgressValue)
                }
                .frame(height: 5)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                // Open button (after install completes)
                if signingState.installStatus == .completed {
                    Button {
                        InstallProgressPoller.openApp(bundleId: signingState.installingBundleId)
                    } label: {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.blue))
                    }
                }
                // Install button (auto-triggers, but can re-trigger)
                if signingState.isUploading {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.green.opacity(0.8)))
                } else if let url = signingState.installURL,
                          signingState.installStatus != .completed {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.green))
                    }
                }
                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.scarletRed))
                }
                Button { dismissSheet() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.glassFill))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    // MARK: - Install Status Helpers

    /// Dynamic status text based on install status.
    @ViewBuilder
    private var installStatusText: some View {
        switch signingState.installStatus {
        case .sendingManifest:
            Text("Sending Manifest...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
        case .sendingPayload:
            Text("Sending Payload...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
        case .installing(let progress):
            Text("Installing... \(Int(progress * 100))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
        case .completed:
            Text("Installed ✓")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
        case .failed(let msg):
            Text("Error: \(msg)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        default:
            Text("Signed Successfully!")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green)
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
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                (sheetPhase == .success ? Color.green : Color.scarletRed).opacity(0.1),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke((sheetPhase == .success ? Color.green : Color.scarletRed).opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 30, y: -10)
    }

    // MARK: - Tab Bar

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 60)
        .padding(.bottom, 20)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .scarletRed : .gray.opacity(0.6))

                Capsule()
                    .fill(selectedTab == tab ? Color.white : .clear)
                    .frame(width: 14, height: 2.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

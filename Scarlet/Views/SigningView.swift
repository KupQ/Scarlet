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
    @State private var showIPAImportPicker = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.scarletRed.opacity(0.10), Color.clear],
                            center: .center, startRadius: 10, endRadius: 180
                        )
                    )
                    .frame(width: 350, height: 200)
                    .offset(y: -40)
                    .blur(radius: 40)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection.padding(.top, 8)

                    if appsManager.isImporting {
                        importingIndicator
                            .padding(.top, 16)
                            .padding(.horizontal, 20)
                    }

                    if appsManager.apps.isEmpty && !appsManager.isImporting {
                        emptyState.padding(.top, 60)
                    } else {
                        appsList.padding(.top, 20)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .sheet(isPresented: $showIPAImportPicker) {
            DocumentPicker(contentTypes: [.ipa, .data]) { url in
                appsManager.importIPA(from: url)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("Imported Apps")
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
    }

    // MARK: - Importing

    private var importingIndicator: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.scarletRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("Importing...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Extracting metadata and icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.scarletRed.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.scarletRed.opacity(0.12), lineWidth: 0.5)
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
                Text("No Apps Imported")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Text("Tap + to import an IPA file")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
            Button { showIPAImportPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Import IPA")
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

    // MARK: - Apps List (split into installed + unsigned)

    private var installedApps: [ImportedApp] {
        appsManager.apps.filter(\.isSigned).sorted {
            ($0.signedDate ?? .distantPast) > ($1.signedDate ?? .distantPast)
        }
    }

    private var unsignedApps: [ImportedApp] {
        appsManager.apps.filter { !$0.isSigned }.sorted {
            $0.importDate > $1.importDate
        }
    }

    private var allAppsSorted: [ImportedApp] {
        appsManager.apps.sorted { $0.importDate > $1.importDate }
    }

    private var appsList: some View {
        VStack(spacing: 16) {
            // ── Installed Apps ──
            if !installedApps.isEmpty {
                sectionHeader(title: "Installed Apps", count: installedApps.count)
                VStack(spacing: 10) {
                    ForEach(installedApps) { app in
                        SwipeableAppCard(app: app, onTap: {
                            InstallProgressPoller.openApp(bundleId: app.bundleIdentifier)
                        }, onDelete: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                appsManager.removeApp(app)
                            }
                        }) {
                            installedCardContent(app)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
            }

            // ── All Apps (sign / re-sign) ──
            sectionHeader(title: "All Apps", count: allAppsSorted.count)
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

    private func installedCardContent(_ app: ImportedApp) -> some View {
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
                    Label("v\(app.version)", systemImage: "number")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.scarletPink.opacity(0.7))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Text(app.formattedSize)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Label(validityText, systemImage: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.scarletRed.opacity(0.7))
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
                Text("Open")
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
                    Label("v\(app.version)", systemImage: "number")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.scarletPink.opacity(0.7))
                    Text("·").foregroundColor(.white.opacity(0.15))
                    Text(app.formattedSize)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            Spacer()

            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.scarletRed.opacity(0.10))
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                        )
                    Image(systemName: "signature")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.scarletRed.opacity(0.8))
                }
                Text("Sign")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.scarletRed.opacity(0.5))
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

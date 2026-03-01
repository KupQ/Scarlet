//
//  SigningView.swift
//  Scarlet
//
//  Library tab displaying imported IPA files with swipe-to-delete
//  support and signed/unsigned sorting. The signing configuration
//  sheet is managed by ContentView.
//

import SwiftUI
import UniformTypeIdentifiers

/// Library tab — displays imported apps with swipe-to-delete support.
struct SigningView: View {
    @ObservedObject var signingState: SigningState
    var onAppTapped: (ImportedApp) -> Void  // Opens config sheet

    @StateObject private var appsManager = ImportedAppsManager.shared
    @State private var showIPAImportPicker = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.scarletRed.opacity(0.12), Color.clear],
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
                            .padding(.horizontal, 16)
                    }

                    if appsManager.apps.isEmpty && !appsManager.isImporting {
                        emptyState.padding(.top, 60)
                    } else {
                        appsList.padding(.top, 20)
                    }
                }
                .padding(.bottom, 100)
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
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Imported Apps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button { showIPAImportPicker = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.scarletRed)
                        .frame(width: 42, height: 42)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Extracting metadata and icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(16)
        .glassCardRed(cornerRadius: 18)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.glassFill)
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)
            }
            VStack(spacing: 8) {
                Text("No Apps Imported")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("Tap + to import an IPA file")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
            Button { showIPAImportPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text("Import IPA")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(LinearGradient.scarletButtonGradient))
                .shadow(color: .scarletRed.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Apps List

    private var appsList: some View {
        VStack(spacing: 12) {
            ForEach(appsManager.sortedApps) { app in
                SwipeableAppCard(app: app, onTap: { signApp(app) }, onDelete: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        appsManager.removeApp(app)
                    }
                }) {
                    appCardContent(app)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal, 16)
    }

    private func appCardContent(_ app: ImportedApp) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                appIcon(app)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if app.isSigned {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                    }
                    .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.appName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label("v\(app.version)", systemImage: "number")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.scarletPink)
                    Text("·").foregroundColor(.gray)
                    Text(app.formattedSize)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    if app.isSigned {
                        Text("·").foregroundColor(.gray)
                        Label("Signed", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
            Spacer()
            if app.isSigned {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Text("Signed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                }
            } else {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.scarletRed)
                            .frame(width: 36, height: 36)
                        Image(systemName: "signature")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Sign")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.scarletRed)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
    }

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
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(colors: [.scarletRed, .scarletDark],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text(String(app.appName.prefix(1)))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Sign Action

    private func signApp(_ app: ImportedApp) {
        onAppTapped(app)
    }
}

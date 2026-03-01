//
//  CertificatesView.swift
//  Scarlet
//
//  Displays certificates fetched from the API for the current device.
//  Users can select a certificate to use for signing, or import their own.
//

import SwiftUI

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared
    @State private var showImportP12 = false
    @State private var showImportProfile = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Certificates")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        if let udid = certService.deviceUDID {
                            Text(udid)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        Button {
                            showImportP12 = true
                        } label: {
                            Label("Import P12", systemImage: "key.fill")
                        }
                        Button {
                            showImportProfile = true
                        } label: {
                            Label("Import Profile", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

                // Error
                if let error = certService.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.scarletRed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.scarletRed.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Content
                ScrollView(showsIndicators: false) {
                    if certService.isLoading && certService.certificates.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(.scarletRed)
                                .scaleEffect(1.1)
                            Text("Loading...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else if certService.certificates.isEmpty {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.scarletRed.opacity(0.1))
                                    .frame(width: 70, height: 70)
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 28))
                                    .foregroundColor(.scarletRed.opacity(0.6))
                            }
                            Text("No Certificates")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Import your own using the\n+ button above.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.25))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(certService.certificates) { cert in
                                CertCard(
                                    cert: cert,
                                    onUse: { certService.useCertificate(cert) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task {
            await certService.fetchCertificates()
        }
        .sheet(isPresented: $showImportP12) {
            DocumentPicker(contentTypes: [.p12]) { url in
                try? SigningSettings.shared.importCertificate(from: url)
            }
        }
        .sheet(isPresented: $showImportProfile) {
            DocumentPicker(contentTypes: [.mobileprovision]) { url in
                try? SigningSettings.shared.importProfile(from: url)
            }
        }
    }
}

// MARK: - Certificate Card

struct CertCard: View {

    let cert: RemoteCertificate
    let onUse: () -> Void
    @State private var applied = false

    private var isActive: Bool { !cert.isExpired }

    private var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: cert.expiresDate).day ?? 0)
    }

    private var isDev: Bool {
        (cert.cert_type?.uppercased() ?? "").contains("DEVELOPMENT")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left: type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.scarletRed.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.scarletRed)
            }

            // Center: name + badges
            VStack(alignment: .leading, spacing: 5) {
                Text(cert.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Type badge
                    Text(isDev ? "Development" : "Distribution")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundColor(.scarletRed.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.scarletRed.opacity(0.1)))

                    // PPQ badge
                    Text(cert.isPPQEnabled ? "PPQ" : "PPQless")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))

                    Spacer()
                }

                // Status line
                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive
                              ? Color(red: 0.2, green: 0.7, blue: 0.3).opacity(0.7)
                              : Color.scarletRed.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(isActive ? "Active · \(daysRemaining) days" : "Expired")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            // Right: Use button
            Button {
                onUse()
                withAnimation(.easeInOut(duration: 0.2)) { applied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) { applied = false }
                }
            } label: {
                ZStack {
                    if applied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.scarletRed)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Use")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.scarletRed)
                            .transition(.opacity)
                    }
                }
                .frame(width: 48, height: 30)
                .background(Capsule().fill(Color.scarletRed.opacity(0.1)))
            }
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            applied ? Color.scarletRed.opacity(0.3) : Color.white.opacity(0.06),
                            lineWidth: applied ? 1 : 0.5
                        )
                        .animation(.easeInOut(duration: 0.2), value: applied)
                )
        )
    }
}

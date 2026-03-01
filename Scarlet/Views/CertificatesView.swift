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
        HStack(spacing: 14) {
            // Left: type icon
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [Color.scarletRed.opacity(0.25), Color.scarletDark.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color.scarletRed.opacity(0.2), lineWidth: 0.5)
                    )
                Image(systemName: isDev ? "wrench.and.screwdriver" : "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.scarletRed)
            }

            // Center: name + type
            VStack(alignment: .leading, spacing: 4) {
                Text(cert.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(isDev ? "Dev" : "Distro")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.scarletRed.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.scarletRed.opacity(0.12))
                        )

                    Text(isActive ? "\(daysRemaining)d left" : "Expired")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isActive ? .white.opacity(0.35) : .scarletRed.opacity(0.7))
                }
            }

            Spacer()

            // Right: Use button
            Button {
                onUse()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { applied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut) { applied = false }
                }
            } label: {
                Text(applied ? "Done" : "Use")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(applied ? .white : .scarletRed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(applied
                                  ? Color.scarletRed
                                  : Color.scarletRed.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.scarletRed.opacity(applied ? 0 : 0.25), lineWidth: 0.5)
                    )
            }
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.35)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

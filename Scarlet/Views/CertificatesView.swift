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
            // Background gradient
            LinearGradient(
                colors: [Color.scarletRed.opacity(0.08), Color.clear, Color.scarletDark.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

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
                                .foregroundColor(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    // Import button
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
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
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
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
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
                            Text("Loading certificates...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else if certService.certificates.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 70, height: 70)
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 28))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.scarletRed, .scarletPink],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            }
                            Text("No Certificates")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Import your own using the\n+ button above.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 14) {
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
        let ct = cert.cert_type?.uppercased() ?? ""
        return ct.contains("DEVELOPMENT")
    }

    private var typeLabel: String { isDev ? "Development" : "Distribution" }
    private var typeIcon: String { isDev ? "hammer.fill" : "paperplane.fill" }
    private var typeGradient: [Color] {
        isDev ? [.blue, .cyan] : [.purple, .pink]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section: icon + info
            HStack(spacing: 14) {
                // Type icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(colors: typeGradient,
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 42, height: 42)
                    Image(systemName: typeIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Name + type
                VStack(alignment: .leading, spacing: 3) {
                    Text(cert.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(typeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // Status badge
                VStack(spacing: 2) {
                    Text(isActive ? "\(daysRemaining)" : "0")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? .white : .red)
                    Text("days")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(width: 48)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isActive
                                        ? Color.green.opacity(0.2)
                                        : Color.red.opacity(0.2),
                                    lineWidth: 0.5
                                )
                        )
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Bottom: Use button
            Button {
                onUse()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { applied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut) { applied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: applied ? "checkmark" : "arrow.down.to.line")
                        .font(.system(size: 11, weight: .bold))
                    Text(applied ? "Applied" : "Use")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(applied ? .green : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
    }
}

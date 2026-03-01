//
//  CertificatesView.swift
//  Scarlet
//
//  Displays certificates fetched from the API for the current device.
//  Users can select a certificate to use for signing, or import their own.
//

import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared
    @State private var showImportP12 = false
    @State private var showImportProfile = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Certificates")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    if let udid = certService.deviceUDID {
                        Text(udid)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // Import certificate button
                Menu {
                    Button {
                        showImportP12 = true
                    } label: {
                        Label("Import P12 Certificate", systemImage: "key.fill")
                    }
                    Button {
                        showImportProfile = true
                    } label: {
                        Label("Import Provisioning Profile", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.scarletRed))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Error
            if let error = certService.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Loading
            if certService.isLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(.gray)
                    Text("Fetching certificates...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 8)
            }

            // Certificate List
            ScrollView {
                if certService.certificates.isEmpty && !certService.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Certificates")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Import your own certificate\nusing the + button above.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(certService.certificates) { cert in
                            CertificateCard(
                                cert: cert,
                                onUse: { certService.useCertificate(cert) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
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

struct CertificateCard: View {

    let cert: RemoteCertificate
    let onUse: () -> Void
    @State private var applied = false

    private var isActive: Bool { !cert.isExpired }

    private var certTypeLabel: String {
        let ct = cert.cert_type?.uppercased() ?? ""
        if ct.contains("DEVELOPMENT") { return "Development" }
        if ct.contains("DISTRIBUTION") { return "Distribution" }
        return "Distribution"
    }

    private var certTypeColor: Color {
        certTypeLabel == "Development" ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name + cert type
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cert.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Cert type badge
                    Text(certTypeLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(certTypeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(certTypeColor.opacity(0.15))
                        )
                }
                Spacer()
                // Active / Expired badge
                Text(isActive ? "Active" : "Expired")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isActive ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isActive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    )
            }

            // Expiry
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Text("Expires \(formatExpiry(cert.expiresDate))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            // Use button
            Button {
                onUse()
                withAnimation(.easeInOut(duration: 0.3)) { applied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { applied = false }
                }
            } label: {
                HStack {
                    Image(systemName: applied ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    Text(applied ? "Applied!" : "Use Certificate")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(applied ? Color.green : Color.scarletRed)
                )
            }
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.5)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.glassFill)
        )
    }

    private func formatExpiry(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

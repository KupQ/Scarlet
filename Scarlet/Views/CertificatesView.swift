//
//  CertificatesView.swift
//  Scarlet
//
//  Displays certificates fetched from the API for the current device.
//  Users can select a certificate to use for signing.
//

import SwiftUI

struct CertificatesView: View {

    @ObservedObject private var certService = CertificateService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Certificates")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    if let udid = certService.deviceUDID {
                        Text("\(udid) • \(certService.certificates.count) certs")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Button {
                    Task { await certService.fetchCertificates() }
                } label: {
                    if certService.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.scarletRed))
                    }
                }
                .disabled(certService.isLoading)
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
                        Text("Tap the refresh button to fetch\ncertificates for this device.")
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

                // Debug info
                if !certService.debugInfo.isEmpty {
                    Text(certService.debugInfo)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .task {
            // Always re-fetch to pick up latest data
            await certService.fetchCertificates()
        }
    }
}

// MARK: - Certificate Card

struct CertificateCard: View {

    let cert: RemoteCertificate
    let onUse: () -> Void
    @State private var applied = false

    private var isActive: Bool {
        !cert.isExpired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: name + status badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cert.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let plan = cert.plan_selected, !plan.isEmpty {
                        Text(plan)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(isActive ? "Active" : "Expired")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isActive ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isActive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    )
            }

            // Details
            HStack(spacing: 16) {
                Label {
                    Text(cert.id)
                        .font(.system(size: 11, design: .monospaced))
                } icon: {
                    Image(systemName: "number")
                        .font(.system(size: 10))
                }
                .foregroundColor(.gray)

                Label {
                    Text(formatExpiry(cert.expiresDate))
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                }
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

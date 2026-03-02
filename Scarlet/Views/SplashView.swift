//
//  SplashView.swift
//  Scarlet
//
//  Functional boot splash — fetches UDID and certificates,
//  shows real status, transitions once loaded.
//

import SwiftUI

struct SplashView: View {

    enum Phase {
        case gettingUDID
        case fetchingCerts
        case ready
    }

    @State private var phase: Phase = .gettingUDID
    @State private var udid: String? = nil
    @State private var certCount: Int = 0
    @State private var ringOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var exitOpacity: Double = 1

    @StateObject private var certService = CertificateService.shared
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [Color.scarletRed.opacity(0.08), Color.clear],
                center: .center, startRadius: 0, endRadius: 200
            )
            .ignoresSafeArea()
            .opacity(ringOpacity)

            // Rotating ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.scarletRed.opacity(0.25), .clear, .scarletRed.opacity(0.10), .clear],
                        center: .center
                    ), lineWidth: 1
                )
                .frame(width: 160, height: 160)
                .opacity(ringOpacity * 0.5)
                .rotationEffect(.degrees(ringRotation))

            VStack(spacing: 24) {
                // Spinner
                ZStack {
                    // Outer glass ring
                    Circle()
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        .frame(width: 64, height: 64)

                    // Spinning scarlet arc
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            LinearGradient(
                                colors: [.scarletRed, .scarletRed.opacity(0.2)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(ringRotation))

                    // Phase icon
                    Group {
                        switch phase {
                        case .gettingUDID:
                            Image(systemName: "cpu")
                                .font(.system(size: 18, weight: .medium))
                        case .fetchingCerts:
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 18, weight: .medium))
                        case .ready:
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .foregroundColor(.scarletRed.opacity(0.7))
                }

                // Status text
                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))

                    Text(statusDetail)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260)
                }
            }
            .opacity(contentOpacity)
        }
        .opacity(exitOpacity)
        .onAppear { boot() }
    }

    // MARK: - Status Text

    private var statusTitle: String {
        switch phase {
        case .gettingUDID:    return "Identifying Device"
        case .fetchingCerts:  return "Fetching Certificates"
        case .ready:          return "Ready"
        }
    }

    private var statusDetail: String {
        switch phase {
        case .gettingUDID:
            return udid ?? "..."
        case .fetchingCerts:
            if certService.isLoading { return "Loading..." }
            return "\(certCount) certificate\(certCount == 1 ? "" : "s") found"
        case .ready:
            return udid ?? ""
        }
    }

    // MARK: - Boot Sequence

    private func boot() {
        // Start animations
        withAnimation(.easeOut(duration: 0.4)) {
            ringOpacity = 1
            contentOpacity = 1
        }
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Phase 1: Get UDID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let deviceUDID = CertificateService.shared.deviceUDID
                ?? CertificateService.getDeviceUDID()
            withAnimation(.easeOut(duration: 0.3)) {
                udid = deviceUDID ?? L("Unknown")
            }

            // Phase 2: Fetch certificates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.2)) {
                    phase = .fetchingCerts
                }

                Task {
                    await certService.fetchCertificates()
                    await MainActor.run {
                        certCount = certService.certificates.count
                        withAnimation(.easeOut(duration: 0.2)) {
                            phase = .ready
                        }

                        // Transition out
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeIn(duration: 0.35)) {
                                exitOpacity = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                // Mark as shown so it never shows again
                                UserDefaults.standard.set(true, forKey: "splashShown")
                                onFinish()
                            }
                        }
                    }
                }
            }
        }
    }
}

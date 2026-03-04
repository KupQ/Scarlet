//
//  SplashView.swift
//  Scarlet
//
//  Elegant launch screen — app icon, version, status line.
//

import SwiftUI
import UIKit

struct SplashView: View {

    @State private var phase = 0           // 0=init 1=checking 2=ready
    @State private var showContent = false
    @State private var exitOpacity: Double = 1
    @State private var iconScale: CGFloat = 0.8
    @State private var glowPulse = false

    let onFinish: () -> Void

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"

    var body: some View {
        ZStack {
            // Background
            Color.bgPrimary.ignoresSafeArea()

            // Subtle top glow
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.scarletRed.opacity(glowPulse ? 0.08 : 0.04), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 200)
                    .blur(radius: 60)
                Spacer()
            }
            .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                Spacer()

                // App Icon
                VStack(spacing: 20) {
                    if let iconImage = UIImage(named: "AppIcon60x60") {
                        Image(uiImage: iconImage)
                            .resizable()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                            .scaleEffect(iconScale)
                    }

                    // App name
                    Text(L("Scarlet"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    // Version
                    Text("v\(version)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }

                Spacer()

                // Bottom status
                VStack(spacing: 16) {
                    // Status text
                    HStack(spacing: 8) {
                        if phase < 2 {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white.opacity(0.3))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.scarletRed)
                        }

                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                            .animation(.easeOut(duration: 0.2), value: phase)
                    }
                    .frame(height: 20)

                    // Footer
                    HStack(spacing: 4) {
                        Text(L("Made with"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.12))
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.scarletRed.opacity(0.3))
                        Text(L("by DebianArch64"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.12))
                    }
                }
                .padding(.bottom, 50)
            }
            .opacity(showContent ? 1 : 0)
        }
        .opacity(exitOpacity)
        .onAppear { boot() }
    }

    private var statusText: String {
        switch phase {
        case 0:  return L("Initializing...")
        case 1:  return L("Checking device...")
        default: return L("Ready")
        }
    }

    // MARK: - Boot Sequence

    private func boot() {
        // Fade in + scale up
        withAnimation(.easeOut(duration: 0.6)) {
            showContent = true
            iconScale = 1.0
        }

        // Start glow pulse
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowPulse = true
        }

        // Phase 1: Check device
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            _ = CertificateService.getDeviceUDID()
            withAnimation(.easeOut(duration: 0.3)) {
                phase = 1
            }

            // Phase 2: Ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    phase = 2
                }

                // Exit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeIn(duration: 0.25)) {
                        exitOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        UserDefaults.standard.set(true, forKey: "splashShown")
                        onFinish()
                    }
                }
            }
        }
    }
}

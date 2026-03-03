//
//  SplashView.swift
//  Scarlet
//
//  Premium splash screen — identifies device, transitions smoothly.
//

import SwiftUI

struct SplashView: View {

    @State private var phase = 0          // 0=boot 1=identified 2=ready
    @State private var ringRotation: Double = 0
    @State private var showContent = false
    @State private var exitOpacity: Double = 1

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.scarletRed.opacity(0.12), Color.scarletRed.opacity(0.03), .clear],
                            center: .center, startRadius: 20, endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .blur(radius: 40)

                // Outer rotating ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.scarletRed.opacity(0.3), .clear, .scarletRed.opacity(0.1), .clear, .scarletRed.opacity(0.2)],
                            center: .center
                        ), lineWidth: 1
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(ringRotation))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: ringRotation)

                // Inner ring
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                    .frame(width: 100, height: 100)
            }
            .opacity(showContent ? 1 : 0)

            VStack(spacing: 28) {
                // App icon area
                ZStack {
                    // Spinning arc
                    Circle()
                        .trim(from: 0, to: phase < 2 ? 0.25 : 0)
                        .stroke(
                            LinearGradient(
                                colors: [.scarletRed, .scarletRed.opacity(0.1)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(ringRotation))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: ringRotation)

                    // Outer glass ring
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 72, height: 72)

                    // Center icon
                    if phase < 2 {
                        Image(systemName: "cpu")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(
                                LinearGradient(colors: [.scarletRed.opacity(0.8), .scarletPink.opacity(0.5)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .transition(.opacity)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.scarletRed)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // App name + status
                VStack(spacing: 10) {
                    Text("Scarlet")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text(statusText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260)
                        .animation(.easeOut(duration: 0.2), value: phase)
                }
            }
            .opacity(showContent ? 1 : 0)
        }
        .opacity(exitOpacity)
        .onAppear { boot() }
    }

    private var statusText: String {
        switch phase {
        case 0:  return L("Identifying device...")
        case 1:  return CertificateService.shared.deviceUDID ?? "..."
        default: return L("Ready")
        }
    }

    // MARK: - Boot

    private func boot() {
        // Fade in
        withAnimation(.easeOut(duration: 0.5)) {
            showContent = true
        }
        ringRotation = 360

        // Phase 1: UDID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = CertificateService.getDeviceUDID()
            withAnimation(.easeOut(duration: 0.3)) {
                phase = 1
            }

            // Phase 2: Ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    phase = 2
                }

                // Exit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        exitOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        UserDefaults.standard.set(true, forKey: "splashShown")
                        onFinish()
                    }
                }
            }
        }
    }
}

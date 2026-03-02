//
//  SplashView.swift
//  Scarlet
//
//  Premium launch animation — particle ring, pulsating glow,
//  cinematic reveal. Matches scarlet glass design language.
//

import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var glowRadius: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var particlePhase: Double = 0
    @State private var shimmerX: CGFloat = -200
    @State private var finished = false

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            // Deep dark background
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow behind everything
            RadialGradient(
                colors: [Color.scarletRed.opacity(0.15), Color.clear],
                center: .center, startRadius: 0, endRadius: 250
            )
            .scaleEffect(glowRadius / 250 + 0.5)
            .opacity(ringOpacity)
            .ignoresSafeArea()

            // Particle ring
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(Color.scarletRed.opacity(0.4 + Double(i % 3) * 0.15))
                        .frame(width: 4, height: 4)
                        .offset(y: -90)
                        .rotationEffect(.degrees(Double(i) * 30 + particlePhase * 360))
                        .opacity(ringOpacity * 0.8)
                }
            }
            .scaleEffect(ringScale)

            // Outer ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.scarletRed.opacity(0.3), .clear, .scarletRed.opacity(0.15), .clear],
                        center: .center
                    ), lineWidth: 1.5
                )
                .frame(width: 180, height: 180)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
                .rotationEffect(.degrees(particlePhase * 180))

            // Inner glass ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                .frame(width: 130, height: 130)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Logo — "S" in a glass card
            ZStack {
                // Soft glow behind logo
                Circle()
                    .fill(Color.scarletRed.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                // Glass card
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .white.opacity(0.03)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: 0.5
                            )
                    )
                    .overlay(
                        // Shimmer sweep
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.08), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 40)
                            .offset(x: shimmerX)
                            .clipped()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                // "S" letter
                Text("S")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.scarletRed, .scarletPink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            // App name
            VStack(spacing: 6) {
                Spacer()

                Text("SCARLET")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(6)
                    .foregroundColor(.white.opacity(0.5))

                Text("IPA Signing Tool")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))

                Spacer().frame(height: 120)
            }
            .opacity(textOpacity)
            .offset(y: textOffset)
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        // Phase 1: Logo appears with spring bounce (0-0.5s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Phase 2: Ring expands, particles start rotating (0.3-0.8s)
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringScale = 1.0
            ringOpacity = 1.0
            glowRadius = 250
        }

        // Phase 3: Particles rotate continuously
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false).delay(0.3)) {
            particlePhase = 1
        }

        // Phase 4: Shimmer sweep across logo (0.5-1.0s)
        withAnimation(.easeInOut(duration: 0.8).delay(0.5)) {
            shimmerX = 200
        }

        // Phase 5: Text fades in (0.7-1.0s)
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            textOpacity = 1
            textOffset = 0
        }

        // Phase 6: Transition out (1.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.4)) {
                logoScale = 1.15
                ringOpacity = 0
                textOpacity = 0
                logoOpacity = 0
                glowRadius = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                finished = true
                onFinish()
            }
        }
    }
}

//
//  SplashView.swift
//  Scarlet
//
//  Premium launch animation — 3D flip, particle orbits, aurora nebula,
//  breathing glow, glowing border trace, light rays from "S".
//

import SwiftUI

struct SplashView: View {
    // Logo entrance
    @State private var logoScale: CGFloat = 0.15
    @State private var logoOpacity: Double = 0
    @State private var flipAngle: Double = -180

    // Rings & particles
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0
    @State private var particlePhase: Double = 0

    // Glow effects
    @State private var glowPulse: Double = 0
    @State private var auroraPhase: Double = 0

    // Border trace
    @State private var borderTrim: CGFloat = 0

    // Light rays
    @State private var rayOpacity: Double = 0
    @State private var rayRotation: Double = 0

    // S letter
    @State private var sGlow: Double = 0
    @State private var sShadowRadius: CGFloat = 0

    // Shimmer
    @State private var shimmerX: CGFloat = -200

    // Text
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20

    // Reflection
    @State private var reflectionOpacity: Double = 0

    @State private var finished = false
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // ── Aurora nebula backdrop ──
            ZStack {
                // Layer 1
                Ellipse()
                    .fill(Color.scarletRed.opacity(0.06))
                    .frame(width: 350, height: 200)
                    .rotationEffect(.degrees(auroraPhase * 25))
                    .offset(y: -30)
                    .blur(radius: 60)

                // Layer 2
                Ellipse()
                    .fill(Color.scarletPink.opacity(0.04))
                    .frame(width: 280, height: 180)
                    .rotationEffect(.degrees(-auroraPhase * 15 + 45))
                    .offset(x: 20, y: 20)
                    .blur(radius: 50)

                // Layer 3 - deeper glow
                Circle()
                    .fill(Color.scarletRed.opacity(0.10 + glowPulse * 0.06))
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)
            }
            .opacity(ringOpacity)

            // ── Light rays from center ──
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.scarletRed.opacity(0.15), .clear],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 2, height: 150)
                        .offset(y: -75)
                        .rotationEffect(.degrees(Double(i) * 45 + rayRotation))
                }
            }
            .opacity(rayOpacity)
            .blur(radius: 3)

            // ── Outer particle orbit (12 dots) ──
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(Color.scarletRed.opacity(0.3 + Double(i % 4) * 0.12))
                        .frame(width: 3 + CGFloat(i % 3), height: 3 + CGFloat(i % 3))
                        .offset(y: -100)
                        .rotationEffect(.degrees(Double(i) * 30 + particlePhase * 360))
                }
            }
            .scaleEffect(ringScale)
            .opacity(ringOpacity * 0.7)

            // ── Inner particle orbit (8 dots, opposite direction) ──
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill(Color.scarletPink.opacity(0.25 + Double(i % 3) * 0.10))
                        .frame(width: 2.5, height: 2.5)
                        .offset(y: -65)
                        .rotationEffect(.degrees(Double(i) * 45 - particlePhase * 240))
                }
            }
            .scaleEffect(ringScale)
            .opacity(ringOpacity * 0.5)

            // ── Outer angular gradient ring ──
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.scarletRed.opacity(0.3), .clear, .scarletPink.opacity(0.15), .clear, .scarletRed.opacity(0.2), .clear],
                        center: .center
                    ), lineWidth: 1.5
                )
                .frame(width: 200, height: 200)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
                .rotationEffect(.degrees(particlePhase * 180))

            // ── Glass faint inner ring ──
            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                .frame(width: 140, height: 140)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // ── Main Logo ──
            ZStack {
                // Deep glow pulse behind card
                Circle()
                    .fill(Color.scarletRed.opacity(0.06 + glowPulse * 0.06))
                    .frame(width: 130, height: 130)
                    .blur(radius: 25)

                // Card shadow layer
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.scarletRed.opacity(0.04 + glowPulse * 0.03))
                    .frame(width: 88, height: 88)
                    .blur(radius: 15)

                // Main glass card
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 84, height: 84)
                    .overlay(
                        // Static border
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.14), .white.opacity(0.02)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: 0.5
                            )
                    )
                    .overlay(
                        // ✨ Animated glowing border trace
                        RoundedRectangle(cornerRadius: 26)
                            .trim(from: 0, to: borderTrim)
                            .stroke(
                                LinearGradient(
                                    colors: [.scarletRed.opacity(0.8), .scarletPink.opacity(0.4), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                ), lineWidth: 1.5
                            )
                            .shadow(color: .scarletRed.opacity(0.6), radius: 6)
                    )
                    .overlay(
                        // Shimmer sweep
                        RoundedRectangle(cornerRadius: 26)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.10), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 30)
                            .offset(x: shimmerX)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26))

                // "S" letter with glow
                Text("S")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.scarletRed, .scarletPink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .scarletRed.opacity(sGlow), radius: sShadowRadius)
                    .shadow(color: .scarletRed.opacity(sGlow * 0.4), radius: sShadowRadius * 2)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)

            // ── Reflection of logo (subtle mirror below) ──
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.white.opacity(0.015))
                    .frame(width: 84, height: 84)

                Text("S")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.scarletRed.opacity(0.3), .scarletPink.opacity(0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(x: 1, y: -1)
            .offset(y: 95)
            .mask(
                LinearGradient(
                    colors: [.white.opacity(0.3), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 50)
                .offset(y: 95)
            )
            .opacity(reflectionOpacity)
            .blur(radius: 2)

            // ── App name ──
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

    // MARK: - Animation Sequence

    private func startAnimation() {

        // Phase 1 (0s): Logo flips in from back with spring
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
            logoScale = 1.0
            logoOpacity = 1.0
            flipAngle = 0
        }

        // Phase 2 (0.3s): Rings expand, aurora starts
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringScale = 1.0
            ringOpacity = 1.0
        }

        // Phase 3 (0.3s): Continuous particle rotation
        withAnimation(.linear(duration: 5).repeatForever(autoreverses: false).delay(0.3)) {
            particlePhase = 1
        }

        // Phase 3b: Aurora slow drift
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(0.3)) {
            auroraPhase = 1
        }

        // Phase 4 (0.4s): Glowing border trace draws around card
        withAnimation(.easeInOut(duration: 0.8).delay(0.4)) {
            borderTrim = 1.0
        }

        // Phase 5 (0.5s): S letter starts glowing + shimmer sweep
        withAnimation(.easeInOut(duration: 0.7).delay(0.5)) {
            sGlow = 0.7
            sShadowRadius = 15
            shimmerX = 200
        }

        // Phase 5b: Breathing glow pulse
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.6)) {
            glowPulse = 1
        }

        // Phase 6 (0.6s): Light rays appear and slowly rotate
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            rayOpacity = 0.7
        }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false).delay(0.6)) {
            rayRotation = 360
        }

        // Phase 7 (0.7s): Reflection fades in
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            reflectionOpacity = 1
        }

        // Phase 8 (0.8s): Text fades in
        withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
            textOpacity = 1
            textOffset = 0
        }

        // Phase 9 (2.2s): Cinematic exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeIn(duration: 0.45)) {
                logoScale = 1.2
                ringOpacity = 0
                textOpacity = 0
                logoOpacity = 0
                rayOpacity = 0
                reflectionOpacity = 0
                glowPulse = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                finished = true
                onFinish()
            }
        }
    }
}

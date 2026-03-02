//
//  SplashView.swift
//  Scarlet
//
//  Dragon-fire splash — scattered ember particles converge to
//  forge a blazing "S", then shockwave detonates outward.
//

import SwiftUI

// MARK: - Ember Particle

private struct Ember: Identifiable {
    let id: Int
    var startX: CGFloat
    var startY: CGFloat
    var size: CGFloat
    var delay: Double
    var hue: Double          // 0 = deep scarlet, 1 = bright pink
}

// MARK: - Splash View

struct SplashView: View {
    // Particles
    @State private var particlesConverged = false
    @State private var embers: [Ember] = []

    // S letter
    @State private var sScale: CGFloat = 0.5
    @State private var sOpacity: Double = 0
    @State private var sBlur: CGFloat = 12
    @State private var sGlowIntensity: Double = 0

    // Fire halo
    @State private var haloScale: CGFloat = 0.3
    @State private var haloOpacity: Double = 0

    // Rising embers
    @State private var risingPhase: Double = 0

    // Shockwave
    @State private var waveScale: CGFloat = 0.1
    @State private var waveOpacity: Double = 0

    // Second shockwave
    @State private var wave2Scale: CGFloat = 0.1
    @State private var wave2Opacity: Double = 0

    // Flash
    @State private var flashOpacity: Double = 0

    // Energy tendrils
    @State private var tendrilRotation: Double = 0
    @State private var tendrilOpacity: Double = 0

    // Exit
    @State private var exitScale: CGFloat = 1
    @State private var exitOpacity: Double = 1

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // ── Deep ambient heat ──
            RadialGradient(
                colors: [
                    Color(red: 0.25, green: 0.02, blue: 0.02).opacity(0.5),
                    Color.clear
                ],
                center: .center, startRadius: 20, endRadius: 300
            )
            .scaleEffect(haloScale * 1.5)
            .opacity(haloOpacity * 0.6)
            .ignoresSafeArea()

            // ── Energy tendrils (rotating scarlet wisps) ──
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.scarletRed.opacity(0.3),
                                    Color.scarletRed.opacity(0.08),
                                    .clear
                                ],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 3, height: 80 + CGFloat(i * 12))
                        .offset(y: -40 - CGFloat(i * 6))
                        .rotationEffect(.degrees(Double(i) * 60 + tendrilRotation))
                        .blur(radius: 4)
                }
            }
            .opacity(tendrilOpacity)

            // ── Converging particles ──
            ForEach(embers) { ember in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.9 + ember.hue * 0.1, green: 0.1 + ember.hue * 0.15, blue: 0.05),
                                Color.scarletRed.opacity(0.4),
                                .clear
                            ],
                            center: .center, startRadius: 0, endRadius: ember.size
                        )
                    )
                    .frame(width: ember.size * 2, height: ember.size * 2)
                    .offset(
                        x: particlesConverged ? 0 : ember.startX,
                        y: particlesConverged ? 0 : ember.startY
                    )
                    .opacity(particlesConverged ? 0 : 1)
                    .blur(radius: particlesConverged ? 4 : 1)
                    .animation(
                        .easeIn(duration: 0.6)
                        .delay(ember.delay),
                        value: particlesConverged
                    )
            }

            // ── Fire halo behind S ──
            ZStack {
                // Inner hot core
                Circle()
                    .fill(Color(red: 0.9, green: 0.15, blue: 0.05).opacity(0.15 + sGlowIntensity * 0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 30)

                // Mid ring
                Circle()
                    .fill(Color.scarletRed.opacity(0.08 + sGlowIntensity * 0.06))
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)

                // Outer heat
                Circle()
                    .fill(Color(red: 0.3, green: 0.02, blue: 0.02).opacity(0.06))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
            }
            .scaleEffect(haloScale)
            .opacity(haloOpacity)

            // ── Rising ember particles (fire effect) ──
            ZStack {
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(
                            Color(
                                red: 0.85 + Double(i % 3) * 0.05,
                                green: 0.1 + Double(i % 4) * 0.04,
                                blue: 0.02
                            ).opacity(0.5 - Double(i) * 0.02)
                        )
                        .frame(width: CGFloat(2 + i % 3), height: CGFloat(2 + i % 3))
                        .offset(
                            x: CGFloat(sin(Double(i) * 0.8 + risingPhase * .pi * 2) * (8 + Double(i) * 1.5)),
                            y: CGFloat(-risingPhase * (40 + Double(i) * 8))
                        )
                        .opacity(1 - risingPhase * 0.6)
                        .blur(radius: CGFloat(risingPhase * 2))
                }
            }
            .opacity(haloOpacity)

            // ── The S — forged in scarlet fire ──
            Text("S")
                .font(.system(size: 100, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.25, blue: 0.15),
                            Color.scarletRed,
                            Color(red: 0.6, green: 0.05, blue: 0.08)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 1, green: 0.2, blue: 0.1).opacity(sGlowIntensity * 0.9), radius: 20)
                .shadow(color: Color.scarletRed.opacity(sGlowIntensity * 0.6), radius: 40)
                .shadow(color: Color(red: 0.5, green: 0.02, blue: 0.05).opacity(sGlowIntensity * 0.3), radius: 60)
                .scaleEffect(sScale)
                .opacity(sOpacity)
                .blur(radius: sBlur)

            // ── Shockwave ring 1 ──
            Circle()
                .stroke(
                    RadialGradient(
                        colors: [Color.scarletRed.opacity(0.6), Color.scarletRed.opacity(0.1), .clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ),
                    lineWidth: 3
                )
                .frame(width: 160, height: 160)
                .scaleEffect(waveScale)
                .opacity(waveOpacity)

            // ── Shockwave ring 2 (delayed) ──
            Circle()
                .stroke(
                    Color.scarletRed.opacity(0.25),
                    lineWidth: 1.5
                )
                .frame(width: 120, height: 120)
                .scaleEffect(wave2Scale)
                .opacity(wave2Opacity)

            // ── White flash ──
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
        }
        .scaleEffect(exitScale)
        .opacity(exitOpacity)
        .onAppear {
            generateEmbers()
            startAnimation()
        }
    }

    // MARK: - Generate Ember Particles

    private func generateEmbers() {
        embers = (0..<40).map { i in
            let angle = Double.random(in: 0...(2 * .pi))
            let dist = CGFloat.random(in: 200...400)
            return Ember(
                id: i,
                startX: cos(angle) * dist,
                startY: sin(angle) * dist,
                size: CGFloat.random(in: 3...8),
                delay: Double.random(in: 0...0.3),
                hue: Double.random(in: 0...1)
            )
        }
    }

    // MARK: - Animation Sequence

    private func startAnimation() {

        // Phase 1 (0s): Particles rush inward to center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            particlesConverged = true
        }

        // Phase 2 (0.5s): Fire halo blooms
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            haloScale = 1.0
            haloOpacity = 1.0
        }

        // Phase 3 (0.6s): WHITE FLASH on impact
        withAnimation(.easeOut(duration: 0.08).delay(0.6)) {
            flashOpacity = 0.7
        }
        withAnimation(.easeIn(duration: 0.25).delay(0.68)) {
            flashOpacity = 0
        }

        // Phase 4 (0.65s): S letter materializes from blur
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.65)) {
            sScale = 1.0
            sOpacity = 1.0
            sBlur = 0
        }

        // Phase 5 (0.7s): S glow intensifies
        withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
            sGlowIntensity = 0.8
        }

        // Phase 5b: Breathing glow
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(1.0)) {
            sGlowIntensity = 1.0
        }

        // Phase 6 (0.75s): Shockwave 1 blasts outward
        withAnimation(.easeOut(duration: 0.6).delay(0.75)) {
            waveScale = 4.0
            waveOpacity = 0.8
        }
        withAnimation(.easeIn(duration: 0.3).delay(1.1)) {
            waveOpacity = 0
        }

        // Phase 6b (0.9s): Shockwave 2
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
            wave2Scale = 5.0
            wave2Opacity = 0.5
        }
        withAnimation(.easeIn(duration: 0.3).delay(1.2)) {
            wave2Opacity = 0
        }

        // Phase 7 (0.8s): Energy tendrils appear
        withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
            tendrilOpacity = 0.6
        }
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false).delay(0.8)) {
            tendrilRotation = 360
        }

        // Phase 8 (0.9s): Rising embers (fire)
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false).delay(0.9)) {
            risingPhase = 1
        }

        // Phase 9 (2.3s): Cinematic exit — S scales up + everything fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            withAnimation(.easeIn(duration: 0.4)) {
                exitScale = 1.3
                exitOpacity = 0
                haloOpacity = 0
                tendrilOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onFinish()
            }
        }
    }
}

//
//  SplashView.swift
//  Scarlet
//
//  Scarlet Galaxy — a serene deep-space nebula with parallax
//  starfield. Apple-presentation quality. No text, no logos.
//

import SwiftUI

// MARK: - Star

private struct Star: Identifiable {
    let id: Int
    let x: CGFloat        // 0-1 normalized
    let y: CGFloat        // 0-1 normalized
    let size: CGFloat
    let brightness: Double
    let twinkleSpeed: Double
    let depth: Int        // 0 = far, 2 = near
}

struct SplashView: View {

    // Starfield
    @State private var stars: [Star] = []
    @State private var twinkle: Bool = false

    // Nebula phases
    @State private var nebulaReveal: Double = 0
    @State private var nebulaBreathe: Double = 0
    @State private var nebulaRotation: Double = 0

    // Galaxy spiral
    @State private var spiralRotation: Double = 0
    @State private var spiralOpacity: Double = 0

    // Depth layers
    @State private var layer1Offset: CGSize = .zero
    @State private var layer2Offset: CGSize = .zero

    // Light bloom
    @State private var bloomScale: CGFloat = 0.6
    @State private var bloomOpacity: Double = 0

    // Exit
    @State private var exitOpacity: Double = 1

    let onFinish: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // ── Deep void ──
                Color(red: 0.02, green: 0.01, blue: 0.03)
                    .ignoresSafeArea()

                // ── Far star layer (parallax slow) ──
                Canvas { context, size in
                    for star in stars where star.depth == 0 {
                        let rect = CGRect(
                            x: star.x * size.width + layer1Offset.width * 0.15,
                            y: star.y * size.height + layer1Offset.height * 0.15,
                            width: star.size, height: star.size
                        )
                        context.opacity = star.brightness * (twinkle ? (0.4 + sin(star.twinkleSpeed) * 0.3) : 0.2)
                        context.fill(Circle().path(in: rect), with: .color(.white))
                    }
                }
                .ignoresSafeArea()
                .opacity(nebulaReveal)

                // ── Mid star layer ──
                Canvas { context, size in
                    for star in stars where star.depth == 1 {
                        let rect = CGRect(
                            x: star.x * size.width + layer1Offset.width * 0.3,
                            y: star.y * size.height + layer1Offset.height * 0.3,
                            width: star.size, height: star.size
                        )
                        context.opacity = star.brightness * (twinkle ? (0.5 + sin(star.twinkleSpeed * 1.3) * 0.4) : 0.3)
                        context.fill(Circle().path(in: rect), with: .color(.white))
                    }
                }
                .ignoresSafeArea()
                .opacity(nebulaReveal)

                // ── Near star layer (brighter, parallax faster) ──
                Canvas { context, size in
                    for star in stars where star.depth == 2 {
                        let rect = CGRect(
                            x: star.x * size.width + layer2Offset.width * 0.5,
                            y: star.y * size.height + layer2Offset.height * 0.5,
                            width: star.size, height: star.size
                        )
                        context.opacity = star.brightness * (twinkle ? (0.6 + sin(star.twinkleSpeed * 1.7) * 0.4) : 0.4)
                        context.fill(Circle().path(in: rect), with: .color(.white))
                    }
                }
                .ignoresSafeArea()
                .opacity(nebulaReveal)

                // ── Nebula Layer 1 — deep crimson cloud ──
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.35, green: 0.02, blue: 0.06).opacity(0.5),
                                Color(red: 0.20, green: 0.01, blue: 0.04).opacity(0.2),
                                .clear
                            ],
                            center: .center, startRadius: 30, endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 300)
                    .rotationEffect(.degrees(-15 + nebulaRotation * 3))
                    .offset(x: -20, y: -40)
                    .blur(radius: 40)
                    .opacity(nebulaReveal)

                // ── Nebula Layer 2 — rose dust ──
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.55, green: 0.06, blue: 0.12).opacity(0.3 + nebulaBreathe * 0.08),
                                Color(red: 0.30, green: 0.03, blue: 0.07).opacity(0.12),
                                .clear
                            ],
                            center: .center, startRadius: 20, endRadius: 180
                        )
                    )
                    .frame(width: 350, height: 250)
                    .rotationEffect(.degrees(25 - nebulaRotation * 2))
                    .offset(x: 30, y: 20)
                    .blur(radius: 35)
                    .opacity(nebulaReveal)

                // ── Nebula Layer 3 — hot core ──
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.75, green: 0.10, blue: 0.12).opacity(0.20 + nebulaBreathe * 0.06),
                                Color(red: 0.45, green: 0.04, blue: 0.08).opacity(0.10),
                                .clear
                            ],
                            center: .center, startRadius: 10, endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 180)
                    .rotationEffect(.degrees(-8 + nebulaRotation * 5))
                    .blur(radius: 25)
                    .opacity(nebulaReveal)

                // ── Galaxy spiral arms ──
                ZStack {
                    ForEach(0..<3, id: \.self) { arm in
                        ForEach(0..<12, id: \.self) { dot in
                            let angle = Double(arm) * 120 + Double(dot) * 8
                            let radius: CGFloat = 30 + CGFloat(dot) * 10
                            let dotSize: CGFloat = 1.5 + CGFloat(dot % 3) * 0.5
                            Circle()
                                .fill(Color(red: 0.8, green: 0.15 + Double(dot) * 0.02, blue: 0.12).opacity(0.3 - Double(dot) * 0.02))
                                .frame(width: dotSize, height: dotSize)
                                .offset(
                                    x: cos((angle + spiralRotation) * .pi / 180) * radius,
                                    y: sin((angle + spiralRotation) * .pi / 180) * radius * 0.6
                                )
                                .blur(radius: 1)
                        }
                    }
                }
                .opacity(spiralOpacity)

                // ── Central light bloom ──
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.9, green: 0.20, blue: 0.15).opacity(0.12 + nebulaBreathe * 0.04),
                                Color(red: 0.6, green: 0.08, blue: 0.10).opacity(0.06),
                                .clear
                            ],
                            center: .center, startRadius: 5, endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(bloomScale)
                    .opacity(bloomOpacity)
                    .blur(radius: 8)

                // ── Subtle lens flare ──
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(red: 0.8, green: 0.15, blue: 0.1).opacity(0.04), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: w * 1.5, height: 2)
                    .rotationEffect(.degrees(-20))
                    .opacity(bloomOpacity * 0.6)
            }
            .opacity(exitOpacity)
        }
        .ignoresSafeArea()
        .onAppear {
            generateStars()
            startAnimation()
        }
    }

    // MARK: - Generate Starfield

    private func generateStars() {
        stars = (0..<120).map { i in
            Star(
                id: i,
                x: CGFloat.random(in: -0.05...1.05),
                y: CGFloat.random(in: -0.05...1.05),
                size: CGFloat.random(in: 0.5...2.5),
                brightness: Double.random(in: 0.3...1.0),
                twinkleSpeed: Double.random(in: 0.5...3.0),
                depth: i < 50 ? 0 : (i < 90 ? 1 : 2)
            )
        }
    }

    // MARK: - Animation Sequence

    private func startAnimation() {

        // Phase 1 (0s): Stars fade in
        withAnimation(.easeOut(duration: 1.2)) {
            nebulaReveal = 1.0
            twinkle = true
        }

        // Phase 2 (0.5s): Nebula starts breathing
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(0.5)) {
            nebulaBreathe = 1.0
        }

        // Phase 3 (0.3s): Slow nebula rotation drift
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false).delay(0.3)) {
            nebulaRotation = 1.0
        }

        // Phase 4 (0.6s): Bloom appears at center
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) {
            bloomScale = 1.0
            bloomOpacity = 1.0
        }

        // Phase 5 (0.8s): Galaxy spiral fades in and rotates
        withAnimation(.easeOut(duration: 0.6).delay(0.8)) {
            spiralOpacity = 1.0
        }
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false).delay(0.8)) {
            spiralRotation = 360
        }

        // Phase 6 (0.5s): Subtle parallax drift
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(0.5)) {
            layer1Offset = CGSize(width: 8, height: -5)
            layer2Offset = CGSize(width: -6, height: 4)
        }

        // Phase 7 (2.4s): Graceful exit — everything fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeInOut(duration: 0.6)) {
                exitOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                onFinish()
            }
        }
    }
}

//
//  HomeView.swift
//  Scarlet
//
//  Home dashboard with premium glassmorphism design.
//  Shows the hero banner, quick actions, and a signing CTA card.
//

import SwiftUI

/// Home dashboard with ambient glow effects and quick action cards.
struct HomeView: View {
    @ObservedObject var signingState: SigningState
    var switchToLibrary: () -> Void

    @State private var animatePulse = false
    @State private var animateGlow = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient scarlet glow
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.scarletRed.opacity(0.25),
                                Color.scarletDark.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 250)
                    .offset(y: -60)
                    .blur(radius: 30)
                    .scaleEffect(animateGlow ? 1.05 : 0.95)
                    .animation(
                        .easeInOut(duration: 4).repeatForever(autoreverses: true),
                        value: animateGlow
                    )
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.top, 8)

                    heroBanner
                        .padding(.top, 24)
                        .padding(.horizontal, 16)

                    quickActionsSection
                        .padding(.top, 28)
                        .padding(.horizontal, 16)

                    signingCTASection
                        .padding(.top, 28)
                        .padding(.horizontal, 16)

                    infoCardsSection
                        .padding(.top, 28)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear {
            animateGlow = true
            animatePulse = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scarlet")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("iOS App Signing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.glassFill)
                    .frame(width: 42, height: 42)
                    .overlay(Circle().stroke(Color.glassBorder, lineWidth: 0.5))
                Image(systemName: "gear")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.scarletRed.opacity(0.35),
                            Color.scarletDark.opacity(0.25),
                            Color.scarletPink.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 180)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.scarletRed.opacity(0.2), lineWidth: 0.5))

            HStack {
                Spacer()
                Image(systemName: "signature")
                    .font(.system(size: 80, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.08))
                    .rotationEffect(.degrees(-10))
                    .offset(x: -20, y: -20)
            }

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .scarletPink], startPoint: .top, endPoint: .bottom)
                    )
                Text("Sign & Install")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("Powered by zsign")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(24)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Actions")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                quickActionCard(icon: "square.and.pencil", title: "Sign IPA", color: .scarletRed) {
                    switchToLibrary()
                }
                quickActionCard(icon: "doc.text.magnifyingglass", title: "View Logs", color: .blue) {}
                quickActionCard(icon: "gearshape.2", title: "Options", color: .purple) {}
            }
        }
    }

    private func quickActionCard(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signing CTA

    private var signingCTASection: some View {
        Button {
            switchToLibrary()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.scarletRed.opacity(0.2), lineWidth: 3)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: animatePulse ? 0.75 : 0.0)
                        .stroke(
                            LinearGradient(colors: [.scarletRed, .scarletPink], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.5), value: animatePulse)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.scarletRed)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Signing")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("Import IPA & sign with certificate")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.scarletRed.opacity(0.6))
            }
            .padding(18)
            .glassCardRed(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Cards

    private var infoCardsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Features")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            featureRow(icon: "lock.shield.fill", title: "P12 & PEM Certificates", subtitle: "OpenSSL-powered parsing", color: .orange)
            featureRow(icon: "cpu", title: "ARM64 & FAT Binaries", subtitle: "Universal Mach-O support", color: .blue)
            featureRow(icon: "bolt.fill", title: "Fast Signing", subtitle: "Native C++ zsign engine", color: .yellow)
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }
}

//
//  HomeView.swift
//  Scarlet
//
//  Home dashboard with premium liquid glass design.
//

import SwiftUI

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
                                Color.scarletRed.opacity(0.20),
                                Color.scarletDark.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 220
                        )
                    )
                    .frame(width: 400, height: 260)
                    .offset(y: -60)
                    .blur(radius: 40)
                    .scaleEffect(animateGlow ? 1.05 : 0.95)
                    .animation(
                        .easeInOut(duration: 4).repeatForever(autoreverses: true),
                        value: animateGlow
                    )
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Pinned header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scarlet")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("iOS App Signing")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.bgPrimary)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {

                    // Hero banner
                    heroBanner
                        .padding(.horizontal, 20)

                    // Quick Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK ACTIONS")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.horizontal, 20)

                        HStack(spacing: 10) {
                            quickActionCard(icon: "square.and.pencil", title: "Sign IPA", color: .scarletRed) {
                                switchToLibrary()
                            }
                            quickActionCard(icon: "doc.text.magnifyingglass", title: "View Logs", color: .blue) {}
                            quickActionCard(icon: "gearshape.2", title: "Options", color: .purple) {}
                        }
                        .padding(.horizontal, 20)
                    }

                    // Start Signing CTA
                    signingCTACard
                        .padding(.horizontal, 20)

                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FEATURES")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.horizontal, 20)

                        featureRow(icon: "lock.shield.fill", title: "P12 & PEM Certificates", subtitle: "OpenSSL-powered parsing", color: .orange)
                        featureRow(icon: "cpu", title: "ARM64 & FAT Binaries", subtitle: "Universal Mach-O support", color: .blue)
                        featureRow(icon: "bolt.fill", title: "Fast Signing", subtitle: "Native C++ zsign engine", color: .yellow)
                    }
                    .padding(.bottom, 80)
                }
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

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.scarletRed.opacity(0.30),
                            Color.scarletDark.opacity(0.20),
                            Color(white: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                )

            // Background watermark
            HStack {
                Spacer()
                Image(systemName: "signature")
                    .font(.system(size: 70, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.06))
                    .rotationEffect(.degrees(-10))
                    .offset(x: -20, y: -20)
            }

            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .scarletPink], startPoint: .top, endPoint: .bottom)
                    )
                Text("Sign & Install")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("Powered by zsign")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(22)
        }
    }

    // MARK: - Quick Actions

    private func quickActionCard(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color.opacity(0.8))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signing CTA

    private var signingCTACard: some View {
        Button { switchToLibrary() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.scarletRed.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: animatePulse ? 0.75 : 0.0)
                        .stroke(
                            LinearGradient(colors: [.scarletRed, .scarletPink],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.5), value: animatePulse)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.scarletRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start Signing")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Import IPA & sign with certificate")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.scarletRed.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.scarletRed.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.scarletRed.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Rows

    private func featureRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
}

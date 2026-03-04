//
//  ResultView.swift
//  Scarlet
//
//  Full-screen success view displayed after a successful signing.
//  Shows an animated check ring, file info, and share/dismiss actions.
//

import SwiftUI
import UIKit

/// Wrapper to make URL Identifiable for fullScreenCover.
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Displays the signing result with glassmorphism design and share functionality.
struct ResultView: View {
    let outputURL: IdentifiableURL
    let onDismiss: () -> Void

    @State private var animateRing = false
    @State private var animateCheck = false
    @State private var showShare = false
    @State private var fileSize: String = ""

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Success glow
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.successGreen.opacity(0.20), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .frame(width: 350, height: 200)
                    .blur(radius: 30)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Success ring (like the signing progress, but completed)
                ZStack {
                    Circle()
                        .fill(Color.successGreen.opacity(0.05))
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)

                    Circle()
                        .stroke(Color.glassFill, lineWidth: 6)
                        .frame(width: 150, height: 150)

                    Circle()
                        .trim(from: 0, to: animateRing ? 1.0 : 0)
                        .stroke(
                            AngularGradient(
                                colors: [.successGreen.opacity(0.5), .successGreen, .successGreen.opacity(0.8)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.successGreen)
                        .scaleEffect(animateCheck ? 1.0 : 0.0)
                }

                VStack(spacing: 8) {
                    Text(L("Signed Successfully"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(L("Your IPA has been re-signed"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.top, 28)

                Spacer()
                    .frame(height: 36)

                // File info card
                VStack(spacing: 0) {
                    infoRow(icon: "doc.fill", label: L("File"), value: outputURL.url.lastPathComponent)
                    Divider().background(Color.glassBorder).padding(.horizontal, 16)
                    infoRow(icon: "internaldrive", label: L("Size"), value: fileSize)
                    Divider().background(Color.glassBorder).padding(.horizontal, 16)
                    infoRow(icon: "folder.fill", label: L("Location"), value: L("App Documents"))
                }
                .glassCard(cornerRadius: 20)
                .padding(.horizontal, 20)

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button {
                        showShare = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                            Text(L("Share Signed IPA"))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient.scarletButtonGradient)
                        )
                        .shadow(color: .scarletRed.opacity(0.35), radius: 20, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDismiss()
                    } label: {
                        Text(L("Done"))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.scarletRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.scarletRed.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.scarletRed.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadFileInfo()
            withAnimation(.easeInOut(duration: 1.0)) {
                animateRing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    animateCheck = true
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [outputURL.url])
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.scarletRed)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func loadFileInfo() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}


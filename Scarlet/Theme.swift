//
//  Theme.swift
//  Scarlet
//
//  Design system defining the app's color palette, gradients,
//  and glassmorphism modifiers used throughout the UI.
//

import SwiftUI

// MARK: - Color Palette

extension Color {

    // MARK: Primary Reds

    /// Core scarlet brand color.
    static let scarletRed   = Color(red: 0.89, green: 0.12, blue: 0.22)
    /// Darker shade for gradients and depth.
    static let scarletDark  = Color(red: 0.58, green: 0.06, blue: 0.10)
    /// Lighter accent for highlights.
    static let scarletLight = Color(red: 1.0, green: 0.30, blue: 0.35)
    /// Pink tint for gradient endpoints.
    static let scarletPink  = Color(red: 1.0, green: 0.42, blue: 0.50)

    // MARK: Surfaces

    /// Primary background color (near-black).
    static let bgPrimary         = Color(red: 0.06, green: 0.06, blue: 0.08)
    /// Secondary background for elevated surfaces.
    static let bgSecondary       = Color(red: 0.10, green: 0.10, blue: 0.13)
    /// Card background.
    static let cardBackground    = Color(red: 0.13, green: 0.13, blue: 0.16)
    /// Surface background alias.
    static let surfaceBackground = Color(red: 0.06, green: 0.06, blue: 0.08)

    // MARK: Glass

    /// Semi-transparent fill for glass effects.
    static let glassFill   = Color.white.opacity(0.06)
    /// Subtle border for glass surfaces.
    static let glassBorder = Color.white.opacity(0.10)

    // MARK: Status

    /// Success indicator color.
    static let successGreen = Color(red: 0.24, green: 0.82, blue: 0.44)
    /// Warning indicator color.
    static let warningAmber = Color(red: 1.0, green: 0.76, blue: 0.03)
}

// MARK: - Gradients

extension LinearGradient {

    /// Full scarlet gradient (dark → red → pink).
    static let scarletGradient = LinearGradient(
        colors: [.scarletDark, .scarletRed, .scarletPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Button-style gradient (red → dark, vertical).
    static let scarletButtonGradient = LinearGradient(
        colors: [.scarletRed, .scarletDark],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Subtle background accent gradient.
    static let subtleGradient = LinearGradient(
        colors: [
            Color.scarletRed.opacity(0.15),
            Color.scarletDark.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glass surface gradient (white fade).
    static let glassGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color.white.opacity(0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glass Card Modifier

/// Applies a frosted-glass card effect with material background,
/// gradient overlay, and subtle white border stroke.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var borderOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient.glassGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Glass Card Red Modifier

/// Applies a scarlet-tinted glass card effect with material background,
/// red gradient overlay, and scarlet border stroke.
struct GlassCardRed: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.scarletRed.opacity(0.20),
                                        Color.scarletDark.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.scarletRed.opacity(0.25), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - View Extensions

extension View {

    /// Applies a neutral glass card background.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Applies a scarlet-tinted glass card background.
    func glassCardRed(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardRed(cornerRadius: cornerRadius))
    }
}

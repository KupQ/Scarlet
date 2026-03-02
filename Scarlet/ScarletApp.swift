//
//  ScarletApp.swift
//  Scarlet
//
//  The main entry point for the Scarlet IPA signing application.
//  Configures the app scene with a dark color scheme.
//

import SwiftUI

/// Scarlet — iOS IPA Signing App
@main
struct ScarletApp: App {
    @State private var showSplash = !UserDefaults.standard.bool(forKey: "splashShown")

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

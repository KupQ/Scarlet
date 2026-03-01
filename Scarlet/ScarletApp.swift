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
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

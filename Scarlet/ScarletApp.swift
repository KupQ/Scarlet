//
//  ScarletApp.swift
//  Scarlet
//
//  The main entry point for the Scarlet IPA signing application.
//  Handles app launch, splash screen, and incoming IPA files
//  shared from other apps via Open In / Share Sheet.
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
            .onOpenURL { url in
                handleIncomingIPA(url)
            }
        }
    }

    /// Handles .ipa files opened via Share Sheet / Open In from other apps.
    private func handleIncomingIPA(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "ipa" else { return }

        // Security-scoped access for files from other apps
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Copy to a temporary location first (shared files may be transient)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
        } catch {
            FileLogger.shared.log("Failed to copy shared IPA: \(error.localizedDescription)")
            return
        }

        // Import into library
        Task { @MainActor in
            ImportedAppsManager.shared.importIPA(from: tmp)
        }
    }
}

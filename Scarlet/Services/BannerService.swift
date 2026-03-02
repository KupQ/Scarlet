//
//  BannerService.swift
//  Scarlet
//
//  Fetches hero banner slides from a remote JSON endpoint.
//  Slides contain title, subtitle, button text, button URL,
//  and optional background image URL — all configurable.
//

import Foundation
import SwiftUI

// MARK: - Models

struct BannerSlide: Codable, Identifiable {
    let id: String?
    let title: String
    let subtitle: String?
    let buttonText: String?
    let buttonURL: String?
    let imageURL: String?

    var safeId: String { id ?? title }
}

struct BannerResponse: Codable {
    let slides: [BannerSlide]
}

// MARK: - Service

class BannerService: ObservableObject {
    static let shared = BannerService()

    /// Remote endpoint for banner slides JSON.
    private let bannerURL = URL(string: "https://nekoo.eu.org/scarlet/banner.json")!

    @Published var slides: [BannerSlide] = []
    @Published var isLoaded = false

    /// In-memory image cache: URL string → UIImage
    @Published var imageCache: [String: UIImage] = [:]

    private init() {
        loadFallback()
        Task { await refresh() }
    }

    // MARK: - Fetch

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: bannerURL)
            let response = try JSONDecoder().decode(BannerResponse.self, from: data)
            guard !response.slides.isEmpty else { return }

            await MainActor.run {
                self.slides = response.slides
                self.isLoaded = true
            }

            FileLogger.shared.log("BannerService: loaded \(response.slides.count) slide(s)")

            // Pre-fetch images
            for slide in response.slides {
                if let imgURL = slide.imageURL, let url = URL(string: imgURL) {
                    await loadImage(from: url, key: imgURL)
                }
            }
        } catch {
            FileLogger.shared.log("BannerService: fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Image loading

    private func loadImage(from url: URL, key: String) async {
        guard imageCache[key] == nil else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    imageCache[key] = image
                }
            }
        } catch {
            FileLogger.shared.log("BannerService: image load failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Fallback

    /// Default slide shown when API is unreachable.
    private func loadFallback() {
        slides = [
            BannerSlide(
                id: "default",
                title: "Sign & Install",
                subtitle: "Powered by zsign",
                buttonText: nil,
                buttonURL: nil,
                imageURL: nil
            )
        ]
    }
}

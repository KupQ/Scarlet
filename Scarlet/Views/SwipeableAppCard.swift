//
//  SwipeableAppCard.swift
//  Scarlet
//
//  Generic card wrapper that supports swipe-left-to-delete.
//  Reveals a red Delete button on partial swipe, or instant-deletes
//  on a full swipe past the trigger threshold.
//

import SwiftUI

// MARK: - Swipeable App Card

/// A generic card wrapper that adds swipe-to-delete gesture support.
///
/// Wrap any card content to enable:
/// - **Partial swipe** (> 60pt): Reveals a "Delete" button
/// - **Full swipe** (> 140pt): Instantly deletes with slide-off animation
/// - **Tap while revealed**: Snaps the card back to its default position
struct SwipeableAppCard<Content: View>: View {
    let app: ImportedApp
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    // MARK: State

    @State private var offset: CGFloat = 0
    @State private var showDelete = false

    // MARK: Constants

    private let deleteWidth: CGFloat = 80
    private let triggerThreshold: CGFloat = 140

    // MARK: Body

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackground
            mainCard
        }
        .clipped()
    }

    // MARK: - Delete Background

    /// Red delete button revealed behind the card on swipe.
    private var deleteBackground: some View {
        HStack {
            Spacer()
            Button {
                performDelete()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.scarletRed.opacity(0.8))
                .frame(width: deleteWidth, height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.scarletRed.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .opacity(showDelete ? 1 : 0)
            .scaleEffect(showDelete ? 1 : 0.5)
        }
        .padding(.trailing, 4)
    }

    // MARK: - Main Card

    /// The content card with drag gesture and tap handler.
    private var mainCard: some View {
        content()
            .offset(x: offset)
            .gesture(swipeGesture)
            .onTapGesture {
                if offset < 0 {
                    snapBack()
                } else {
                    onTap()
                }
            }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let translation = value.translation.width
                if translation < 0 {
                    offset = translation
                    showDelete = abs(translation) > 30
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                if abs(translation) > triggerThreshold {
                    performDelete()
                } else if abs(translation) > 60 {
                    revealDeleteButton()
                } else {
                    snapBack()
                }
            }
    }

    // MARK: - Actions

    private func performDelete() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            offset = -UIScreen.main.bounds.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDelete()
        }
    }

    private func revealDeleteButton() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = -deleteWidth
            showDelete = true
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = 0
            showDelete = false
        }
    }
}

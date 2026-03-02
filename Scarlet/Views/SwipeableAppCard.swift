//
//  SwipeableAppCard.swift
//  Scarlet
//
//  Generic card wrapper that supports swipe-left-to-reveal-delete.
//  Partial swipe reveals a Delete button; tap it to confirm deletion.
//  Swiping back or tapping the card snaps it closed.
//

import SwiftUI

// MARK: - Swipeable App Card

/// A generic card wrapper that adds swipe-to-delete gesture support.
///
/// - **Partial swipe left** (> 50pt): Reveals a "Delete" button
/// - **Tap Delete button**: Confirms and performs deletion
/// - **Swipe right or tap card**: Snaps back to closed position
/// - No auto-delete on full swipe — always requires explicit tap
struct SwipeableAppCard<Content: View>: View {
    let app: ImportedApp
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    // MARK: State

    @State private var offset: CGFloat = 0
    @State private var showDelete = false
    @State private var isDeleting = false

    // MARK: Constants

    private let deleteWidth: CGFloat = 80
    private let revealThreshold: CGFloat = 50

    // MARK: Body

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackground
            mainCard
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Delete Background

    private var deleteBackground: some View {
        HStack {
            Spacer()
            Button {
                performDelete()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(L("Delete"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.scarletRed.opacity(0.8))
                .frame(width: deleteWidth, height: .infinity)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .opacity(showDelete ? 1 : 0)
            .scaleEffect(showDelete ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showDelete)
        }
        .background(Color.scarletRed.opacity(0.03))
    }

    // MARK: - Main Card

    private var mainCard: some View {
        content()
            .offset(x: offset)
            .highPriorityGesture(swipeGesture)
            .onTapGesture {
                if showDelete {
                    snapBack()
                } else {
                    onTap()
                }
            }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .local)
            .onChanged { value in
                guard !isDeleting else { return }
                let tx = value.translation.width

                if showDelete {
                    // Already revealed — allow dragging back or further left
                    let newOffset = -deleteWidth + tx
                    offset = min(0, newOffset)
                } else {
                    // Only allow left swipe
                    if tx < 0 {
                        // Rubber-band resistance past deleteWidth
                        let clamped = abs(tx)
                        if clamped > deleteWidth {
                            let excess = clamped - deleteWidth
                            offset = -(deleteWidth + excess * 0.3)
                        } else {
                            offset = tx
                        }
                    } else {
                        offset = 0
                    }
                }
                showDelete = offset < -30
            }
            .onEnded { value in
                guard !isDeleting else { return }

                if offset < -revealThreshold {
                    // Reveal delete button — snap to deleteWidth
                    revealDeleteButton()
                } else {
                    // Not enough swipe — snap back
                    snapBack()
                }
            }
    }

    // MARK: - Actions

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            offset = -UIScreen.main.bounds.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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

//
//  SwipeableSignedCard.swift
//  Scarlet
//
//  Swipe-left wrapper for signed apps — reveals Share + Delete buttons.
//  Matches the design of SwipeableAppCard but with two actions.
//

import SwiftUI

struct SwipeableSignedCard<Content: View>: View {
    let onShare: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var showActions = false
    @State private var isDeleting = false

    private let actionsWidth: CGFloat = 140  // two buttons: share + delete
    private let revealThreshold: CGFloat = 50

    var body: some View {
        ZStack(alignment: .trailing) {
            actionsBackground
            mainCard
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Actions Background

    private var actionsBackground: some View {
        HStack(spacing: 0) {
            Spacer()

            // Share button
            Button {
                snapBack()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onShare()
                }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L("Share"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(width: actionsWidth / 2)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                performDelete()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L("Delete"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.scarletRed.opacity(0.9))
                .frame(width: actionsWidth / 2)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        }
        .opacity(showActions ? 1 : 0)
        .scaleEffect(showActions ? 1 : 0.5)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showActions)
        .background(Color.scarletRed.opacity(0.03))
    }

    // MARK: - Main Card

    private var mainCard: some View {
        content()
            .offset(x: offset)
            .highPriorityGesture(swipeGesture)
            .onTapGesture {
                if showActions {
                    snapBack()
                }
            }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .local)
            .onChanged { value in
                guard !isDeleting else { return }
                let tx = value.translation.width

                if showActions {
                    let newOffset = -actionsWidth + tx
                    offset = min(0, newOffset)
                } else {
                    if tx < 0 {
                        let clamped = abs(tx)
                        if clamped > actionsWidth {
                            let excess = clamped - actionsWidth
                            offset = -(actionsWidth + excess * 0.3)
                        } else {
                            offset = tx
                        }
                    } else {
                        offset = 0
                    }
                }
                showActions = offset < -30
            }
            .onEnded { _ in
                guard !isDeleting else { return }

                if offset < -revealThreshold {
                    revealActions()
                } else {
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

    private func revealActions() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = -actionsWidth
            showActions = true
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = 0
            showActions = false
        }
    }
}

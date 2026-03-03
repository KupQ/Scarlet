//
//  InteractivePopGestureEnabler.swift
//  Scarlet
//
//  Re-enables iOS swipe-right-to-go-back gesture when
//  the navigation bar is hidden (.navigationBarHidden(true)).
//

import SwiftUI
import UIKit

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        InteractivePopController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private class InteractivePopController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Walk up to find the NavigationController and re-enable the gesture
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }
}

//
//  DocumentPicker.swift
//  Scarlet
//
//  UIKit document picker wrapped for SwiftUI.
//  Used for importing IPA, P12, and mobileprovision files.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Picker

/// SwiftUI wrapper around `UIDocumentPickerViewController`.
///
/// Presents a system file picker configured for the given content types.
/// The selected file URL is passed to the `onPicked` closure.
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}

// MARK: - Custom UTTypes

extension UTType {
    /// IPA archive file type.
    static let ipa = UTType(filenameExtension: "ipa") ?? .data
    /// P12 certificate file type.
    static let p12 = UTType(filenameExtension: "p12") ?? .data
    /// Mobile provisioning profile file type.
    static let mobileprovision = UTType(filenameExtension: "mobileprovision") ?? .data
}

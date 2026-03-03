//
//  FileLogger.swift
//  Scarlet
//
//  Thread-safe file logger that writes timestamped entries
//  to scarlet_debug.log in the app's Documents directory.
//

import Foundation

/// Thread-safe logger that persists messages to disk.
///
/// Usage:
/// ```swift
/// FileLogger.shared.log("Something happened")
/// ```
///
/// In DEBUG builds, messages are also printed to the console.
final class FileLogger {
    static let shared = FileLogger()

    private let logURL: URL
    private let queue = DispatchQueue(label: "com.scarlet.logger")

    // MARK: - Initialization

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        logURL = docs.appendingPathComponent("scarlet_debug.log")
    }

    // MARK: - Logging

    /// Appends a timestamped message to the log file.
    /// - Parameter message: The message to log.
    func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        queue.sync { [logURL] in
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
        #if DEBUG
        print("[Scarlet] \(message)")
        #endif
    }
}

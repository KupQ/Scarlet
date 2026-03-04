//
//  IPAParser.swift
//  Scarlet
//
//  Parses IPA archives to extract metadata (name, version, bundle ID)
//  and app icons. Uses targeted ZIP entry reading — does NOT extract
//  the entire IPA, keeping memory usage minimal for older devices.
//

import Foundation
import UIKit
import Compression

// MARK: - IPA Metadata

/// Metadata extracted from an IPA file's `Info.plist`.
struct IPAMetadata {
    let appName: String
    let bundleIdentifier: String
    let version: String
    let iconData: Data?
    let fileSize: Int64
    let fileName: String
}

// MARK: - IPA Parser

/// Parses IPA files by reading ZIP entries directly — no full extraction.
enum IPAParser {

    /// Parses an IPA file and extracts its metadata and icon.
    static func parse(ipaURL: URL) -> IPAMetadata? {

        let accessing = ipaURL.startAccessingSecurityScopedResource()
        defer { if accessing { ipaURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let fileSize = (try? fm.attributesOfItem(atPath: ipaURL.path)[.size] as? Int64) ?? 0

        guard fm.fileExists(atPath: ipaURL.path) else {
            return nil
        }

        // Read specific entries from the ZIP without full extraction
        guard let entries = readZIPEntries(from: ipaURL) else {
            return nil
        }

        // Find Info.plist
        guard let plistEntry = entries.first(where: {
            $0.name.hasSuffix("/Info.plist") && $0.name.hasPrefix("Payload/") &&
            $0.name.components(separatedBy: "/").count == 3 // Payload/App.app/Info.plist
        }) else {
            return nil
        }

        // Extract the .app directory name from the path
        let pathParts = plistEntry.name.components(separatedBy: "/")
        let appDirName = pathParts.count >= 2 ? pathParts[1] : "Unknown.app"

        // Decompress Info.plist
        guard let plistData = decompressEntry(plistEntry, from: ipaURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: plistData, format: nil
              ) as? [String: Any] else {
            return nil
        }

        // Extract metadata fields
        let appName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appDirName.replacingOccurrences(of: ".app", with: "")

        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? "1.0"

        let bundleId = (plist["CFBundleIdentifier"] as? String) ?? "unknown"


        // Extract icon
        let iconNames = extractIconNames(from: plist)
        let iconData = extractLargestIconFromZIP(
            entries: entries, ipaURL: ipaURL,
            appPrefix: "Payload/\(appDirName)/", iconNames: iconNames
        )

        return IPAMetadata(
            appName: appName,
            bundleIdentifier: bundleId,
            version: version,
            iconData: iconData,
            fileSize: fileSize,
            fileName: ipaURL.lastPathComponent
        )
    }

    // MARK: - ZIP Entry Reading (No Full Extraction)

    private struct ZIPEntry {
        let name: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let method: UInt16        // 0 = stored, 8 = deflate
        let localHeaderOffset: UInt32
    }

    /// Reads the ZIP central directory to list all entries without extracting.
    private static func readZIPEntries(from url: URL) -> [ZIPEntry]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        // Find end-of-central-directory record (last 22+ bytes)
        // Signature: PK\x05\x06
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count > 22 else { return nil }

        var eocdOffset = -1
        for i in stride(from: count - 22, through: max(0, count - 65557), by: -1) {
            if bytes[i] == 0x50 && bytes[i+1] == 0x4B &&
               bytes[i+2] == 0x05 && bytes[i+3] == 0x06 {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0 else { return nil }

        // Parse EOCD
        let cdSize = UInt32(bytes[eocdOffset+12]) | UInt32(bytes[eocdOffset+13]) << 8 |
                     UInt32(bytes[eocdOffset+14]) << 16 | UInt32(bytes[eocdOffset+15]) << 24
        let cdOffset = UInt32(bytes[eocdOffset+16]) | UInt32(bytes[eocdOffset+17]) << 8 |
                       UInt32(bytes[eocdOffset+18]) << 16 | UInt32(bytes[eocdOffset+19]) << 24

        guard Int(cdOffset) + Int(cdSize) <= count else { return nil }

        var entries: [ZIPEntry] = []
        var pos = Int(cdOffset)
        let endPos = pos + Int(cdSize)

        while pos + 46 <= endPos {
            // Central directory file header signature: PK\x01\x02
            guard bytes[pos] == 0x50, bytes[pos+1] == 0x4B,
                  bytes[pos+2] == 0x01, bytes[pos+3] == 0x02 else { break }

            let method = UInt16(bytes[pos+10]) | UInt16(bytes[pos+11]) << 8
            let compSize = UInt32(bytes[pos+20]) | UInt32(bytes[pos+21]) << 8 |
                           UInt32(bytes[pos+22]) << 16 | UInt32(bytes[pos+23]) << 24
            let uncompSize = UInt32(bytes[pos+24]) | UInt32(bytes[pos+25]) << 8 |
                             UInt32(bytes[pos+26]) << 16 | UInt32(bytes[pos+27]) << 24
            let nameLen = UInt16(bytes[pos+28]) | UInt16(bytes[pos+29]) << 8
            let extraLen = UInt16(bytes[pos+30]) | UInt16(bytes[pos+31]) << 8
            let commentLen = UInt16(bytes[pos+32]) | UInt16(bytes[pos+33]) << 8
            let localHdrOff = UInt32(bytes[pos+42]) | UInt32(bytes[pos+43]) << 8 |
                              UInt32(bytes[pos+44]) << 16 | UInt32(bytes[pos+45]) << 24

            let nameStart = pos + 46
            let nameEnd = nameStart + Int(nameLen)
            guard nameEnd <= count else { break }

            if let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) {
                entries.append(ZIPEntry(
                    name: name,
                    compressedSize: compSize,
                    uncompressedSize: uncompSize,
                    method: method,
                    localHeaderOffset: localHdrOff
                ))
            }

            pos = nameEnd + Int(extraLen) + Int(commentLen)
        }

        return entries
    }

    /// Decompresses a single ZIP entry from the file.
    private static func decompressEntry(_ entry: ZIPEntry, from url: URL) -> Data? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { fileHandle.closeFile() }

        // Seek to local file header
        fileHandle.seek(toFileOffset: UInt64(entry.localHeaderOffset))
        let localHeader = fileHandle.readData(ofLength: 30)
        guard localHeader.count == 30 else { return nil }

        let localBytes = [UInt8](localHeader)
        guard localBytes[0] == 0x50, localBytes[1] == 0x4B,
              localBytes[2] == 0x03, localBytes[3] == 0x04 else { return nil }

        let localNameLen = UInt16(localBytes[26]) | UInt16(localBytes[27]) << 8
        let localExtraLen = UInt16(localBytes[28]) | UInt16(localBytes[29]) << 8

        // Skip name and extra fields
        fileHandle.seek(toFileOffset: UInt64(entry.localHeaderOffset) + 30 +
                       UInt64(localNameLen) + UInt64(localExtraLen))

        let compressedData = fileHandle.readData(ofLength: Int(entry.compressedSize))

        if entry.method == 0 {
            // Stored — no compression
            return compressedData
        } else if entry.method == 8 {
            // Deflate
            return decompressDeflate(compressedData, expectedSize: Int(entry.uncompressedSize))
        }

        return nil
    }

    /// Decompresses deflate-compressed data using Apple's Compression framework.
    private static func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        // Use raw deflate (no zlib header)
        let capacity = max(expectedSize, data.count * 4)
        var output = Data(count: capacity)

        let decompressed = output.withUnsafeMutableBytes { outBuf -> Int in
            data.withUnsafeBytes { inBuf -> Int in
                guard let src = inBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dst = outBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                let size = compression_decode_buffer(
                    dst, capacity,
                    src, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
                return size
            }
        }

        guard decompressed > 0 else { return nil }
        output.count = decompressed
        return output
    }

    // MARK: - Icon Extraction

    private static func extractIconNames(from plist: [String: Any]) -> [String] {
        var names = [String]()

        if let arr = plist["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: arr)
        }
        if let icon = plist["CFBundleIconFile"] as? String, !names.contains(icon) {
            names.append(icon)
        }
        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for file in files where !names.contains(file) {
                names.append(file)
            }
        }
        if let icons = plist["CFBundleIcons~ipad"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for file in files where !names.contains(file) {
                names.append(file)
            }
        }
        return names
    }

    /// Finds the largest icon PNG from ZIP entries (no full extraction).
    private static func extractLargestIconFromZIP(
        entries: [ZIPEntry], ipaURL: URL,
        appPrefix: String, iconNames: [String]
    ) -> Data? {
        // Find icon entries in the ZIP
        let pngEntries = entries.filter { entry in
            guard entry.name.hasPrefix(appPrefix),
                  entry.name.hasSuffix(".png"),
                  entry.uncompressedSize > 0 else { return false }

            let fileName = (entry.name as NSString).lastPathComponent

            let matches = iconNames.contains { name in
                let baseName = name.replacingOccurrences(of: ".png", with: "")
                return fileName == name || fileName.hasPrefix(baseName)
            }

            return matches || (iconNames.isEmpty && fileName.lowercased().contains("appicon"))
        }

        // Fallback to any icon-like PNG
        let candidates = pngEntries.isEmpty ?
            entries.filter { $0.name.hasPrefix(appPrefix) &&
                           ($0.name as NSString).lastPathComponent.lowercased().contains("icon") &&
                           $0.name.hasSuffix(".png") && $0.uncompressedSize > 0 } :
            pngEntries

        // Pick the largest
        guard let bestEntry = candidates.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else {
            return nil
        }

        guard let rawData = decompressEntry(bestEntry, from: ipaURL) else { return nil }
        return normalizePNG(rawData)
    }

    // MARK: - PNG Normalization

    private static func normalizePNG(_ data: Data) -> Data {
        data.withUnsafeBytes { rawBuf -> Data in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return data
            }

            var outPtr: UnsafeMutablePointer<UInt8>?
            var outLen: UInt = 0

            let result = png_normalize_cgbi(ptr, UInt(data.count), &outPtr, &outLen)
            if result == 0, let outPtr, outLen > 0 {
                let normalized = Data(bytes: outPtr, count: Int(outLen))
                free(outPtr)
                return normalized
            }
            return data
        }
    }
}

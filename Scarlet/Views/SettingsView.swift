//
//  SettingsView.swift
//  Scarlet
//
//  Settings view for certificate management, provisioning profiles,
//  zsign signing options, and app information.
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings view with certificate management and zsign configuration.
struct SettingsView: View {
    @ObservedObject var settings = SigningSettings.shared

    @State private var showCertPicker = false
    @State private var showProfilePicker = false
    @State private var showImportSuccess = false
    @State private var importMessage = ""

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text(L("Settings"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Certificate Section
                    certificateSection

                    // zsign Options Section
                    zsignOptionsSection

                    // About Section
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showCertPicker) {
            DocumentPicker(contentTypes: [.p12, .data]) { url in
                do {
                    try settings.importCertificate(from: url)
                    importMessage = String(format: L("Certificate imported: %@"), url.lastPathComponent)
                    showImportSuccess = true
                } catch {
                    importMessage = String(format: L("Import failed: %@"), error.localizedDescription)
                    showImportSuccess = true
                }
            }
        }
        .sheet(isPresented: $showProfilePicker) {
            DocumentPicker(contentTypes: [.mobileprovision, .data]) { url in
                do {
                    try settings.importProfile(from: url)
                    importMessage = String(format: L("Profile imported: %@"), url.lastPathComponent)
                    showImportSuccess = true
                } catch {
                    importMessage = String(format: L("Import failed: %@"), error.localizedDescription)
                    showImportSuccess = true
                }
            }
        }
        .alert(L("Import"), isPresented: $showImportSuccess) {
            Button(L("OK")) {}
        } message: {
            Text(importMessage)
        }
    }

    // MARK: - Certificate Section

    private var certificateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "lock.shield.fill", title: L("Certificates"), color: .orange)

            // Import Certificate
            if settings.hasCertificate {
                // Show current cert
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.successGreen.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.successGreen)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.savedCertName ?? L("Certificate"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(L("Imported · P12"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.successGreen)
                    }

                    Spacer()

                    Button {
                        settings.removeCertificate()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(10)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }

            // Import button
            Button { showCertPicker = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.scarletRed)
                    Text(settings.hasCertificate ? L("Replace Certificate") : L("Import Certificate (.p12)"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)

            // Certificate Password
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.glassFill)
                        .frame(width: 50, height: 50)
                    Image(systemName: "key.fill")
                        .font(.system(size: 20))
                        .foregroundColor(!settings.savedCertPassword.isEmpty ? .scarletRed : .gray)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Certificate Password"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    SecureField(L("Enter password"), text: $settings.savedCertPassword)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .textContentType(.password)
                }
            }
            .padding(14)
            .glassCard(cornerRadius: 18)

            // Import Profile
            if settings.hasProfile {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.successGreen.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.successGreen)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.savedProfileName ?? L("Profile"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(L("Imported · mobileprovision"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.successGreen)
                    }

                    Spacer()

                    Button {
                        settings.removeProfile()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(10)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }

            Button { showProfilePicker = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    Text(settings.hasProfile ? L("Replace Profile") : L("Import Profile (.mobileprovision)"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - zsign Options

    private var zsignOptionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "gearshape.2.fill", title: L("Signing Options"), color: .purple)

            // Bundle ID
            settingsTextField(
                icon: "app.badge",
                title: L("Bundle ID"),
                placeholder: L("Keep original"),
                text: $settings.bundleId
            )

            // Display Name
            settingsTextField(
                icon: "textformat",
                title: L("Display Name"),
                placeholder: L("Keep original"),
                text: $settings.displayName
            )

            // Version
            settingsTextField(
                icon: "number",
                title: L("Version"),
                placeholder: L("Keep original"),
                text: $settings.version
            )

            // Zip Compression
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.glassFill)
                            .frame(width: 50, height: 50)
                        Image(systemName: "archivebox")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Zip Compression"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(L("Level")) \(settings.zipCompression) — \(compressionLabel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    Spacer()
                }

                Picker(L("Compression"), selection: $settings.zipCompression) {
                    Text(L("0 (Store)")).tag(0)
                    Text(L("1 (Fast)")).tag(1)
                    Text(L("3 (Normal)")).tag(3)
                    Text(L("6 (Good)")).tag(6)
                    Text(L("9 (Best)")).tag(9)
                }
                .pickerStyle(.segmented)
                .tint(.scarletRed)
            }
            .padding(14)
            .glassCard(cornerRadius: 18)

            // Remove Plugins Toggle
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.glassFill)
                        .frame(width: 50, height: 50)
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 20))
                        .foregroundColor(.yellow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Remove Plugins"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(L("Strip app extensions"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }

                Spacer()

                Toggle("", isOn: $settings.removePlugins)
                    .labelsHidden()
                    .tint(.scarletRed)
            }
            .padding(14)
            .glassCard(cornerRadius: 18)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "info.circle.fill", title: L("About"), color: .gray)

            VStack(spacing: 0) {
                aboutRow(label: L("Engine"), value: "zsign (C++)")
                Divider().background(Color.glassBorder).padding(.horizontal, 16)
                aboutRow(label: L("OpenSSL"), value: L("Bundled"))
                Divider().background(Color.glassBorder).padding(.horizontal, 16)
                aboutRow(label: L("Version"), value: "1.0")
            }
            .glassCard(cornerRadius: 18)
        }
    }

    // MARK: - Components

    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func settingsTextField(
        icon: String,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.glassFill)
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(!text.wrappedValue.isEmpty ? .scarletRed : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                TextField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var compressionLabel: String {
        switch settings.zipCompression {
        case 0: return L("Fastest")
        case 1...3: return L("Fast")
        case 4...6: return L("Normal")
        case 7...9: return L("Smallest")
        default: return L("Store")
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ASCSetupSheet: View {

    @Bindable var model: ASCSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    Text("Create a key in App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys. Give it the Sales or Finance role — it only needs to read reports. The .p8 file can be downloaded once, so keep a copy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SwiftUI.Section("Key") {
                    TextField("Issuer ID", text: $model.issuerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("Key ID", text: $model.keyID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                SwiftUI.Section {
                    TextField("Vendor number", text: $model.vendorNumber)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Vendor number")
                } footer: {
                    Text("Shown in Payments and Financial Reports, top left, under your team name.")
                }

                SwiftUI.Section {
                    TextEditor(text: $model.privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if model.privateKey.isEmpty {
                                Text(model.keyPlaceholder)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        model.isImporting = true
                    } label: {
                        Label("Import .p8 file", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("Stored in this device's Keychain. It never leaves the device except to sign requests to Apple.")
                }

                if let error = model.error {
                    SwiftUI.Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if model.isConfigured {
                    SwiftUI.Section {
                        Button("Disconnect and delete key", role: .destructive) {
                            model.isConfirmingDisconnect = true
                        }
                    }
                }
            }
            .navigationTitle("App Store Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() { dismiss() }
                    }
                    .disabled(!model.canSave)
                }
            }
            .fileImporter(
                isPresented: $model.isImporting,
                allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .plainText, .data]
            ) { result in
                model.importKey(result)
            }
            .confirmationDialog("Delete the stored key?", isPresented: $model.isConfirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    model.disconnect()
                    dismiss()
                }
            }
        }
    }
}

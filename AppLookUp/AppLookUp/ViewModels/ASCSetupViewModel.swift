import Foundation
import Observation

/// The App Store Connect key form: editing, .p8 import, validation and saving.
@Observable
@MainActor
final class ASCSetupViewModel: Identifiable {

    var issuerID: String
    var keyID: String
    var vendorNumber: String
    var privateKey = ""
    var isImporting = false
    var isConfirmingDisconnect = false
    private(set) var error: String?

    private let store: EarningsStore
    private let onDisconnect: () -> Void

    init(store: EarningsStore, onDisconnect: @escaping () -> Void = {}) {
        self.store = store
        self.onDisconnect = onDisconnect
        issuerID = store.issuerID
        keyID = store.keyID
        vendorNumber = store.vendorNumber
    }

    var isConfigured: Bool { store.isConfigured }
    var hasPrivateKey: Bool { store.hasPrivateKey }

    var canSave: Bool {
        !issuerID.isEmpty && !keyID.isEmpty && !vendorNumber.isEmpty
            && (!privateKey.isEmpty || store.hasPrivateKey)
    }

    var keyPlaceholder: String {
        store.hasPrivateKey
            ? "Key stored in Keychain. Paste a new one to replace it."
            : "Paste the contents of AuthKey_XXXXXXXXXX.p8"
    }

    /// Returns true when the credentials were stored and the sheet can close.
    func save() -> Bool {
        do {
            try store.saveCredentials(
                issuerID: issuerID,
                keyID: keyID,
                vendorNumber: vendorNumber,
                privateKey: privateKey.isEmpty ? nil : privateKey
            )
            Task { await store.load() }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func importKey(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                privateKey = text
                error = nil
                // AuthKey_ABC123XYZ.p8 carries the Key ID in its name.
                let name = url.deletingPathExtension().lastPathComponent
                if keyID.isEmpty, name.hasPrefix("AuthKey_") {
                    keyID = String(name.dropFirst("AuthKey_".count))
                }
            } else {
                error = "Couldn't read that file."
            }
        case let .failure(failure):
            error = failure.localizedDescription
        }
    }

    func disconnect() {
        store.disconnect()
        onDisconnect()
    }
}

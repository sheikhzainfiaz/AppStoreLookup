import Foundation

/// Where the App Store Connect key lives: the three IDs in UserDefaults, the .p8 in the Keychain.
struct ASCCredentialStore {

    struct IDs {
        var issuerID: String
        var keyID: String
        var vendorNumber: String
    }

    private let defaults: UserDefaults
    private static let keyAccount = "privateKey"
    private static let issuerKey = "asc.issuerID"
    private static let keyIDKey = "asc.keyID"
    private static let vendorKey = "asc.vendorNumber"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadIDs() -> IDs {
        IDs(
            issuerID: defaults.string(forKey: Self.issuerKey) ?? "",
            keyID: defaults.string(forKey: Self.keyIDKey) ?? "",
            vendorNumber: defaults.string(forKey: Self.vendorKey) ?? ""
        )
    }

    func saveIDs(_ ids: IDs) {
        defaults.set(ids.issuerID, forKey: Self.issuerKey)
        defaults.set(ids.keyID, forKey: Self.keyIDKey)
        defaults.set(ids.vendorNumber, forKey: Self.vendorKey)
    }

    var privateKey: String? { Keychain.read(account: Self.keyAccount) }

    func savePrivateKey(_ key: String) {
        Keychain.save(key, account: Self.keyAccount)
    }

    func deleteAll() {
        Keychain.delete(account: Self.keyAccount)
        for key in [Self.issuerKey, Self.keyIDKey, Self.vendorKey] {
            defaults.removeObject(forKey: key)
        }
    }
}

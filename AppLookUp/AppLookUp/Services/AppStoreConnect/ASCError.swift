import Foundation

// MARK: - Errors

enum ASCError: LocalizedError {
    case missingCredentials
    case badPrivateKey
    case badVendorNumber
    case unauthorized
    case forbidden(String?)
    case noSales
    case notReady(String)
    case api(status: Int, detail: String?)
    case unreadableReport

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Add your App Store Connect API key to load earnings."
        case .badPrivateKey:
            "That private key couldn't be read. Paste the full contents of the .p8 file, including the BEGIN and END lines."
        case .badVendorNumber:
            "The vendor number is the all-digit ID shown in Payments and Financial Reports."
        case .unauthorized:
            "App Store Connect rejected the key (401). Check the Issuer ID and Key ID match the .p8 file, and that the key hasn't been revoked."
        case let .forbidden(detail):
            "This key isn't allowed to read sales reports (403). Use a key with the Sales, Finance or Admin role.\(detail.map { " \($0)" } ?? "")"
        case .noSales:
            "No sales that month."
        case let .notReady(detail):
            detail.isEmpty ? "That month's report isn't available yet." : detail
        case let .api(status, detail):
            "App Store Connect returned HTTP \(status).\(detail.map { " \($0)" } ?? "")"
        case .unreadableReport:
            "The report came back in a format this app couldn't read."
        }
    }
}


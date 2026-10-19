import Foundation

// MARK: - Report rows

enum ProductKind: Sendable {
    case download, redownload, update, inAppPurchase, subscription, other

    /// Apple's Product Type Identifiers, from the Sales and Trends reference.
    init(productType: String) {
        switch productType.uppercased() {
        case "1", "1F", "1T", "F1", "1E", "1EP", "1EU", "1-B", "F1-B":
            self = .download
        case "3", "3F", "3T", "F3":
            self = .redownload
        case "7", "7F", "7T", "F7":
            self = .update
        case "IAY", "IAY-M", "IA9", "IA9-M", "IAC", "IAC-M":
            self = .subscription
        case let other where other.hasPrefix("IA") || other.hasPrefix("FI"):
            self = .inAppPurchase
        default:
            self = .other
        }
    }

    var isApp: Bool { self == .download || self == .redownload || self == .update }
}

struct SalesRow: Sendable {
    let sku: String
    let title: String
    let kind: ProductKind
    let units: Double
    let proceedsPerUnit: Double
    let proceedsCurrency: String
    let customerPrice: Double
    let customerCurrency: String
    let countryCode: String
    let appleID: Int?
    let parentIdentifier: String

    /// In-app purchases point at their app through the parent's SKU.
    var appKey: String { parentIdentifier.isEmpty ? sku : parentIdentifier }
    var proceeds: Double { units * proceedsPerUnit }
    var gross: Double { units * customerPrice }
}

// MARK: - Aggregation

struct KnownApp: Sendable {
    let appleID: Int
    let title: String
}

/// One app's month, with every in-app purchase and subscription rolled up under it.
struct AppEarnings: Identifiable, Sendable {

    let key: String
    var appleID: Int?
    var title: String

    var downloads = 0.0
    var redownloads = 0.0
    var updates = 0.0

    /// By currency of proceeds. Earnings, after Apple's commission.
    var proceeds: [String: Double] = [:]
    var inAppProceeds: [String: Double] = [:]
    var subscriptionProceeds: [String: Double] = [:]
    /// By customer currency. What buyers paid, before Apple's cut.
    var gross: [String: Double] = [:]

    var proceedsByCountry: [String: [String: Double]] = [:]
    var downloadsByCountry: [String: Double] = [:]

    var id: String { key }
}

// MARK: - State

struct EarningsMonth: Identifiable, Sendable {

    enum State: Sendable {
        case loading
        case loaded([AppEarnings])
        case noSales
        case notReady(String)
        case failed(String)
    }

    /// "2026-08", the format the API takes.
    let key: String
    let date: Date
    var state: State

    var id: String { key }

    var apps: [AppEarnings] {
        if case let .loaded(apps) = state { return apps }
        return []
    }

    var isLoaded: Bool {
        switch state {
        case .loaded, .noSales: true
        default: false
        }
    }

    var shortLabel: String { date.formatted(.dateTime.month(.abbreviated)) }
    var longLabel: String { date.formatted(.dateTime.month(.wide).year()) }
}

struct OwnedAppActuals: Sendable {
    let month: EarningsMonth
    let worldwideUSD: Double?
    let countryUSD: Double?
    let countryDownloads: Double
    let worldwideDownloads: Double
}


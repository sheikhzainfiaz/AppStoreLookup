import Foundation

/// One app's earnings across the loaded months. Stateless: everything derives from the store,
/// so building a fresh one per render costs nothing and never goes stale.
@MainActor
struct AppEarningsDetailViewModel {

    struct Point: Identifiable {
        let key: String
        let label: String
        let usd: Double
        var id: String { key }
    }

    struct CountryRow: Identifiable {
        let storefront: Storefront
        let usd: Double
        let downloads: Double
        var id: String { storefront.code }
    }

    static let countryLimit = 25

    let key: String
    let monthKey: String?
    let store: EarningsStore

    private var history: [(month: EarningsMonth, app: AppEarnings?)] { store.history(for: key) }

    var month: EarningsMonth? { store.month(monthKey) }

    /// This app in the selected month, if it sold or downloaded anything.
    var current: AppEarnings? {
        month?.apps.first { $0.key == key }
    }

    private var anyEntry: AppEarnings? {
        current ?? history.compactMap(\.app).first
    }

    private var listing: AppStoreApp? {
        anyEntry?.appleID.flatMap { store.listings[$0] }
    }

    var title: String { listing?.trackName ?? anyEntry?.title ?? key }
    var navigationTitle: String { listing?.trackName ?? anyEntry?.title ?? "App" }
    var artworkURL: URL? { listing?.artworkURL }
    var appleID: Int? { anyEntry?.appleID }

    var points: [Point] {
        history.reversed().compactMap { entry -> Point? in
            guard entry.month.isLoaded else { return nil }
            let usd = entry.app.flatMap { store.usd($0.proceeds) } ?? 0
            return Point(key: entry.month.key, label: entry.month.shortLabel, usd: usd)
        }
    }

    var rows: [(String, String)] {
        guard let app = current else { return [] }
        var rows: [(String, String)] = []
        rows.append(("Earnings", store.usd(app.proceeds).map { formatUSD($0, cents: true) } ?? "—"))
        if let gross = store.usd(app.gross), gross != 0 {
            rows.append(("Gross sales", formatUSD(gross, cents: true)))
        }
        if let iap = store.usd(app.inAppProceeds), iap != 0 {
            rows.append(("In-app purchases", formatUSD(iap, cents: true)))
        }
        if let subscriptions = store.usd(app.subscriptionProceeds), subscriptions != 0 {
            rows.append(("Subscriptions", formatUSD(subscriptions, cents: true)))
        }
        rows.append(("Downloads", Int(app.downloads).formatted()))
        if app.redownloads > 0 { rows.append(("Re-downloads", Int(app.redownloads).formatted())) }
        if app.updates > 0 { rows.append(("Updates", Int(app.updates).formatted())) }
        if app.downloads > 0, let usd = store.usd(app.proceeds), usd > 0 {
            rows.append(("Per download", formatUSD(usd / app.downloads, cents: true)))
        }
        let currencies = app.proceeds.filter { $0.value != 0 }.count
        if currencies > 1 { rows.append(("Paid in", "\(currencies) currencies")) }
        return rows
    }

    /// Every storefront with proceeds or downloads, biggest first.
    var countries: [CountryRow] {
        guard let current else { return [] }
        let codes = Set(current.proceedsByCountry.keys).union(current.downloadsByCountry.keys)
        return codes
            .map { code in
                CountryRow(
                    storefront: Storefront.named(code),
                    usd: store.usd(current.proceedsByCountry[code] ?? [:]) ?? 0,
                    downloads: current.downloadsByCountry[code] ?? 0
                )
            }
            .sorted { ($0.usd, $0.downloads) > ($1.usd, $1.downloads) }
    }

    /// Where "Open App Store report" should land: the app's best-earning storefront.
    var reportTarget: (query: String, country: String)? {
        guard let id = appleID else { return nil }
        return (String(id), store.topCountry(for: id) ?? "us")
    }
}

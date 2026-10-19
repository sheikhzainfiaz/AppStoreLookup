import Foundation
import Observation

/// Your App Store Connect connection and the monthly reports it has loaded. Shared: the Earnings
/// tab shows these figures, and the Lookup report uses them as actuals when the app is yours.
@Observable
@MainActor
final class EarningsStore {

    static let shared = EarningsStore(credentials: ASCCredentialStore(), currency: .shared)

    private(set) var issuerID: String
    private(set) var keyID: String
    private(set) var vendorNumber: String
    private(set) var hasPrivateKey: Bool

    private(set) var months: [EarningsMonth] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastLoaded: Date?
    /// Names and icons from the public lookup, keyed by Apple ID.
    private(set) var listings: [Int: AppStoreApp] = [:]

    /// The month worth opening on: the newest with sales, else the newest that loaded at all.
    /// Kept across reloads while it's still in range, so the view doesn't jump around.
    private(set) var suggestedMonthKey: String?

    private let credentials: ASCCredentialStore
    private let currency: CurrencyConverter

    private init(credentials: ASCCredentialStore, currency: CurrencyConverter) {
        self.credentials = credentials
        self.currency = currency
        let ids = credentials.loadIDs()
        issuerID = ids.issuerID
        keyID = ids.keyID
        vendorNumber = ids.vendorNumber
        hasPrivateKey = credentials.privateKey != nil
    }

    var isConfigured: Bool {
        !issuerID.isEmpty && !keyID.isEmpty && !vendorNumber.isEmpty && hasPrivateKey
    }

    // MARK: Credentials

    /// Pass `privateKey: nil` to keep the stored key and change only the IDs.
    func saveCredentials(issuerID: String, keyID: String, vendorNumber: String, privateKey: String?) throws {
        let issuer = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let vendor = vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !issuer.isEmpty, !key.isEmpty else { throw ASCError.missingCredentials }
        guard !vendor.isEmpty, vendor.allSatisfy(\.isNumber) else { throw ASCError.badVendorNumber }

        if let privateKey, !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try ASCToken.signingKey(from: privateKey) // validate before storing
            credentials.savePrivateKey(privateKey)
            hasPrivateKey = true
        }
        guard hasPrivateKey else { throw ASCError.badPrivateKey }

        self.issuerID = issuer
        self.keyID = key
        self.vendorNumber = vendor
        credentials.saveIDs(.init(issuerID: issuer, keyID: key, vendorNumber: vendor))
    }

    func disconnect() {
        credentials.deleteAll()
        issuerID = ""
        keyID = ""
        vendorNumber = ""
        hasPrivateKey = false
        months = []
        listings = [:]
        suggestedMonthKey = nil
        errorMessage = nil
        lastLoaded = nil
    }

    // MARK: Loading

    func load(monthCount: Int = 6) async {
        guard !isLoading else { return }
        guard isConfigured, let privateKey = credentials.privateKey else {
            errorMessage = ASCError.missingCredentials.errorDescription
            return
        }

        isLoading = true
        errorMessage = nil

        let token: String
        do {
            token = try ASCToken.make(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        let recent = Self.recentMonths(count: monthCount)
        months = recent.map { EarningsMonth(key: $0.key, date: $0.date, state: .loading) }

        await currency.refresh()

        var rowsByMonth: [String: [SalesRow]] = [:]

        for (index, month) in recent.enumerated() {
            do {
                rowsByMonth[month.key] = try await SalesReportService.monthly(
                    reportDate: month.key, vendorNumber: vendorNumber, token: token
                )
            } catch ASCError.noSales {
                months[index].state = .noSales
            } catch let ASCError.notReady(detail) {
                months[index].state = .notReady(detail.isEmpty ? "Not available yet." : detail)
            } catch let error as ASCError {
                switch error {
                case .unauthorized, .forbidden:
                    // Every other month will fail the same way; stop and say why.
                    errorMessage = error.localizedDescription
                    for rest in index..<months.count { months[rest].state = .failed("Not loaded.") }
                    isLoading = false
                    return
                default:
                    months[index].state = .failed(error.localizedDescription)
                }
            } catch {
                months[index].state = .failed(error.localizedDescription)
            }
        }

        let known = EarningsAggregator.knownApps(in: rowsByMonth.values.flatMap { $0 })
        for index in months.indices {
            guard let rows = rowsByMonth[months[index].key] else { continue }
            let apps = EarningsAggregator.aggregate(rows, knownApps: known)
            months[index].state = apps.isEmpty ? .noSales : .loaded(apps)
        }

        if suggestedMonthKey == nil || !months.contains(where: { $0.key == suggestedMonthKey }) {
            suggestedMonthKey = months.first { !$0.apps.isEmpty }?.key ?? months.first(where: \.isLoaded)?.key
        }

        lastLoaded = .now
        isLoading = false

        await loadListings(known: known)
    }

    /// Icons and store names: one batched call, then a per-app retry in its best country for
    /// anything the US store doesn't carry.
    private func loadListings(known: [String: KnownApp]) async {
        let ids = Array(Set(known.values.map(\.appleID)))
        var found = await AppStoreLookupService.lookupMany(ids)

        for id in ids where found[id] == nil {
            guard let country = topCountry(for: id), country != "us" else { continue }
            if let app = try? await AppStoreLookupService.lookup(String(id), country: country) {
                found[id] = app
            }
        }
        listings = found
    }

    // MARK: Queries

    func usd(_ amounts: [String: Double]) -> Double? {
        currency.toUSD(amounts)
    }

    func month(_ key: String?) -> EarningsMonth? {
        months.first { $0.key == key }
    }

    /// The month before `month`, for month-over-month change.
    func month(before month: EarningsMonth) -> EarningsMonth? {
        guard let index = months.firstIndex(where: { $0.key == month.key }), index + 1 < months.count else {
            return nil
        }
        return months[index + 1]
    }

    func totalProceedsUSD(_ month: EarningsMonth) -> Double? {
        guard month.isLoaded else { return nil }
        var total = 0.0
        for app in month.apps {
            guard let value = usd(app.proceeds) else { return nil }
            total += value
        }
        return total
    }

    func totalGrossUSD(_ month: EarningsMonth) -> Double? {
        guard month.isLoaded else { return nil }
        var total = 0.0
        for app in month.apps {
            guard let value = usd(app.gross) else { return nil }
            total += value
        }
        return total
    }

    func totalDownloads(_ month: EarningsMonth) -> Double {
        month.apps.reduce(0) { $0 + $1.downloads }
    }

    /// The same app across every loaded month, newest first.
    func history(for key: String) -> [(month: EarningsMonth, app: AppEarnings?)] {
        months.map { month in (month, month.apps.first { $0.key == key }) }
    }

    /// The storefront where an app earns most — the natural one to open its report in.
    func topCountry(for appleID: Int) -> String? {
        for month in months {
            guard let app = month.apps.first(where: { $0.appleID == appleID }) else { continue }
            let ranked = app.proceedsByCountry
                .compactMap { code, amounts in usd(amounts).map { (code, $0) } }
                .max { $0.1 < $1.1 }
            if let code = ranked?.0 { return code }
            if let code = app.downloadsByCountry.max(by: { $0.value < $1.value })?.key { return code }
        }
        return nil
    }

    /// Actual figures for one app in the most recent month that has it — used by the Lookup
    /// report to show real numbers instead of an estimate when the app is yours.
    func actuals(for trackID: Int, country: String) -> OwnedAppActuals? {
        for month in months {
            guard let app = month.apps.first(where: { $0.appleID == trackID }) else { continue }
            let local = app.proceedsByCountry[country] ?? [:]
            return OwnedAppActuals(
                month: month,
                worldwideUSD: usd(app.proceeds),
                countryUSD: usd(local),
                countryDownloads: app.downloadsByCountry[country] ?? 0,
                worldwideDownloads: app.downloads
            )
        }
        return nil
    }

    private static func recentMonths(count: Int) -> [(key: String, date: Date)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"

        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now

        // The label date sits mid-month so no time zone can push it into a neighbouring month.
        return (1...max(count, 1)).compactMap { offset -> (key: String, date: Date)? in
            guard
                let start = calendar.date(byAdding: .month, value: -offset, to: startOfThisMonth),
                let middle = calendar.date(byAdding: .day, value: 14, to: start)
            else { return nil }
            return (formatter.string(from: start), middle)
        }
    }
}

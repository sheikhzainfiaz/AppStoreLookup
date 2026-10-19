//
//  AppStoreConnect.swift
//  Applookup
//
//  v2: actual earnings, from App Store Connect.
//
//  Apple never publishes what another developer's app earns. The only real figures are your
//  own, in App Store Connect, and the API exposes them as Sales and Trends reports:
//
//    GET https://api.appstoreconnect.apple.com/v1/salesReports
//        ?filter[reportType]=SALES&filter[reportSubType]=SUMMARY&filter[frequency]=MONTHLY
//        &filter[reportDate]=2026-08&filter[vendorNumber]=…&filter[version]=1_1
//
//  The response is a gzipped, tab-separated file: one row per product × country × price.
//  "Developer Proceeds" is what you earn per unit after Apple's commission, in the currency
//  Apple pays that storefront in — so a month's total is Σ units × proceeds, per currency.
//

import CryptoKit
import Foundation
import Security

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

// MARK: - Keychain

/// The .p8 key can read your sales data, so it lives in the Keychain, not UserDefaults.
enum Keychain {

    private static let service = "com.zain.Applookup.appstoreconnect"

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Token

/// App Store Connect wants a short-lived ES256 JWT signed with your API key.
enum ASCToken {

    static func make(issuerID: String, keyID: String, privateKey: String) throws -> String {
        let key = try signingKey(from: privateKey)

        // Back-date slightly for clock skew; Apple caps a token's life at 20 minutes.
        let now = Int(Date.now.timeIntervalSince1970)
        let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now - 30,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        ]

        let encodedHeader = base64URL(try JSONSerialization.data(withJSONObject: header, options: .sortedKeys))
        let encodedPayload = base64URL(try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        // JWT's ES256 wants the raw 64-byte r‖s signature, which is exactly rawRepresentation.
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    /// Accepts the .p8 file as-is, or just its base64 body.
    static func signingKey(from text: String) throws -> P256.Signing.PrivateKey {
        let body = text
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .filter { !$0.isWhitespace }

        guard !body.isEmpty else { throw ASCError.badPrivateKey }

        if let der = Data(base64Encoded: body),
           let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return key
        }
        let pem = "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----"
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return key
        }
        throw ASCError.badPrivateKey
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Gzip

/// Foundation has no gzip reader, but a gzip file is just a header, a raw DEFLATE stream and an
/// 8-byte trailer — and Apple's `.zlib` algorithm is raw DEFLATE. Strip the wrapper, inflate.
enum Gzip {

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)

        // Already plain text (or URLSession inflated it for us via Content-Encoding).
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }
        guard bytes[2] == 8 else { throw ASCError.unreadableReport } // 8 = DEFLATE

        let flags = bytes[3]
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { throw ASCError.unreadableReport }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            index += 2
        }

        let end = bytes.count - 8
        guard index < end else { throw ASCError.unreadableReport }

        let deflated = Data(bytes[index..<end]) as NSData
        return try deflated.decompressed(using: .zlib) as Data
    }
}

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

enum SalesReportParser {

    /// Columns are found by header name, not position, so a new column in a future report
    /// version doesn't silently shift every figure.
    static func parse(_ text: String) -> [SalesRow] {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { return [] }

        let header = headerLine
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func column(_ name: String) -> Int? { header.firstIndex(of: name) }

        guard
            let unitsColumn = column("Units"),
            let proceedsColumn = column("Developer Proceeds"),
            let typeColumn = column("Product Type Identifier")
        else { return [] }

        let skuColumn = column("SKU")
        let titleColumn = column("Title")
        let proceedsCurrencyColumn = column("Currency of Proceeds")
        let priceColumn = column("Customer Price")
        let customerCurrencyColumn = column("Customer Currency")
        let countryColumn = column("Country Code")
        let appleIDColumn = column("Apple Identifier")
        let parentColumn = column("Parent Identifier")

        return lines.dropFirst().compactMap { line -> SalesRow? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)

            func value(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index].trimmingCharacters(in: .whitespaces)
            }
            func number(_ index: Int?) -> Double {
                Double(value(index).replacingOccurrences(of: ",", with: "")) ?? 0
            }

            let type = value(typeColumn)
            guard !type.isEmpty else { return nil }

            return SalesRow(
                sku: value(skuColumn),
                title: value(titleColumn),
                kind: ProductKind(productType: type),
                units: number(unitsColumn),
                proceedsPerUnit: number(proceedsColumn),
                proceedsCurrency: value(proceedsCurrencyColumn).uppercased(),
                customerPrice: number(priceColumn),
                customerCurrency: value(customerCurrencyColumn).uppercased(),
                countryCode: value(countryColumn).lowercased(),
                appleID: Int(value(appleIDColumn)),
                parentIdentifier: value(parentColumn)
            )
        }
    }
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

enum EarningsAggregator {

    /// SKU → Apple ID and title. Built across all loaded months, because a month where an app
    /// had in-app sales but no downloads has no app row to name it by.
    static func knownApps(in rows: [SalesRow]) -> [String: KnownApp] {
        var known: [String: KnownApp] = [:]
        for row in rows where row.kind.isApp && row.parentIdentifier.isEmpty {
            if let id = row.appleID, !row.sku.isEmpty {
                known[row.sku] = KnownApp(appleID: id, title: row.title)
            }
        }
        return known
    }

    static func aggregate(_ rows: [SalesRow], knownApps: [String: KnownApp]) -> [AppEarnings] {
        var apps: [String: AppEarnings] = [:]

        for row in rows {
            let key = row.appKey
            var entry = apps[key] ?? AppEarnings(
                key: key,
                appleID: knownApps[key]?.appleID,
                title: knownApps[key]?.title ?? (row.kind.isApp ? row.title : "SKU \(key)")
            )

            if row.kind.isApp {
                if entry.appleID == nil { entry.appleID = row.appleID }
                if entry.title.hasPrefix("SKU "), !row.title.isEmpty { entry.title = row.title }
            }

            switch row.kind {
            case .download:
                entry.downloads += row.units
                entry.downloadsByCountry[row.countryCode, default: 0] += row.units
            case .redownload:
                entry.redownloads += row.units
            case .update:
                entry.updates += row.units
            case .inAppPurchase:
                entry.inAppProceeds[row.proceedsCurrency, default: 0] += row.proceeds
            case .subscription:
                entry.subscriptionProceeds[row.proceedsCurrency, default: 0] += row.proceeds
            case .other:
                break
            }

            if row.proceeds != 0 {
                entry.proceeds[row.proceedsCurrency, default: 0] += row.proceeds
                entry.proceedsByCountry[row.countryCode, default: [:]][row.proceedsCurrency, default: 0] += row.proceeds
            }
            if row.gross != 0 {
                entry.gross[row.customerCurrency, default: 0] += row.gross
            }

            apps[key] = entry
        }
        return Array(apps.values)
    }
}

// MARK: - Service

enum SalesReportService {

    static func monthly(reportDate: String, vendorNumber: String, token: String) async throws -> [SalesRow] {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
        components.queryItems = [
            URLQueryItem(name: "filter[frequency]", value: "MONTHLY"),
            URLQueryItem(name: "filter[reportDate]", value: reportDate),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[reportType]", value: "SALES"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[version]", value: "1_1"),
        ]
        guard let url = components.url else { throw ASCError.unreadableReport }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/a-gzip", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200:
            let raw = try Gzip.decompress(data)
            guard let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) else {
                throw ASCError.unreadableReport
            }
            return SalesReportParser.parse(text)
        case 401:
            throw ASCError.unauthorized
        case 403:
            throw ASCError.forbidden(detail(in: data))
        case 404:
            // Apple uses 404 both for "nothing sold" and "not generated yet"; the detail says which.
            let detail = detail(in: data) ?? ""
            if detail.localizedCaseInsensitiveContains("no sales") { throw ASCError.noSales }
            throw ASCError.notReady(detail)
        default:
            throw ASCError.api(status: status, detail: detail(in: data))
        }
    }

    private static func detail(in data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = root["errors"] as? [[String: Any]],
            let first = errors.first
        else { return nil }
        return (first["detail"] as? String) ?? (first["title"] as? String)
    }
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

@Observable
@MainActor
final class EarningsModel {

    static let shared = EarningsModel()

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

    var selectedMonthKey: String?
    var showingSetup = false

    private let defaults = UserDefaults.standard
    private static let keyAccount = "privateKey"

    private init() {
        issuerID = defaults.string(forKey: "asc.issuerID") ?? ""
        keyID = defaults.string(forKey: "asc.keyID") ?? ""
        vendorNumber = defaults.string(forKey: "asc.vendorNumber") ?? ""
        hasPrivateKey = Keychain.read(account: Self.keyAccount) != nil
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
            Keychain.save(privateKey, account: Self.keyAccount)
            hasPrivateKey = true
        }
        guard hasPrivateKey else { throw ASCError.badPrivateKey }

        self.issuerID = issuer
        self.keyID = key
        self.vendorNumber = vendor
        defaults.set(issuer, forKey: "asc.issuerID")
        defaults.set(key, forKey: "asc.keyID")
        defaults.set(vendor, forKey: "asc.vendorNumber")
    }

    func disconnect() {
        Keychain.delete(account: Self.keyAccount)
        for key in ["asc.issuerID", "asc.keyID", "asc.vendorNumber"] {
            defaults.removeObject(forKey: key)
        }
        issuerID = ""
        keyID = ""
        vendorNumber = ""
        hasPrivateKey = false
        months = []
        listings = [:]
        selectedMonthKey = nil
        errorMessage = nil
        lastLoaded = nil
    }

    // MARK: Loading

    func load(monthCount: Int = 6) async {
        guard !isLoading else { return }
        guard isConfigured, let privateKey = Keychain.read(account: Self.keyAccount) else {
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

        await RevenueModel.shared.refreshRates()

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

        if selectedMonthKey == nil || !months.contains(where: { $0.key == selectedMonthKey }) {
            selectedMonthKey = months.first { !$0.apps.isEmpty }?.key ?? months.first(where: \.isLoaded)?.key
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

    var selectedMonth: EarningsMonth? {
        months.first { $0.key == selectedMonthKey }
    }

    /// The month before the selected one, for month-over-month change.
    var previousMonth: EarningsMonth? {
        guard let index = months.firstIndex(where: { $0.key == selectedMonthKey }), index + 1 < months.count else {
            return nil
        }
        return months[index + 1]
    }

    func usd(_ amounts: [String: Double]) -> Double? {
        RevenueModel.shared.toUSD(amounts)
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

struct OwnedAppActuals: Sendable {
    let month: EarningsMonth
    let worldwideUSD: Double?
    let countryUSD: Double?
    let countryDownloads: Double
    let worldwideDownloads: Double
}

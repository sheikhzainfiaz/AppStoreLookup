//
//  SalesReportService.swift
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

import Foundation

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


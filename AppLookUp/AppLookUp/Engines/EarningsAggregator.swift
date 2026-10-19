import Foundation

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


import Foundation

/// One storefront's answer. `unconfirmed` is kept separate from `notLive` on purpose: Apple's
/// lookup endpoint throttles hard, and a throttled request must never be reported as
/// "not available here".
struct StorefrontAvailability: Identifiable, Sendable {

    enum Status: Sendable {
        case live(AppStoreApp)
        case notLive
        case unconfirmed
    }

    let storefront: Storefront
    let status: Status

    var id: String { storefront.code }

    var app: AppStoreApp? {
        if case let .live(app) = status { return app }
        return nil
    }

    var isLive: Bool { app != nil }

    var isUnconfirmed: Bool {
        if case .unconfirmed = status { return true }
        return false
    }
}

struct AvailabilityReport: Sendable {

    let query: String
    let results: [StorefrontAvailability]
    let checkedAt: Date
    /// True when the sweep was stopped before every storefront answered.
    let isPartial: Bool

    private static func byName(_ lhs: StorefrontAvailability, _ rhs: StorefrontAvailability) -> Bool {
        lhs.storefront.name.localizedStandardCompare(rhs.storefront.name) == .orderedAscending
    }

    var live: [StorefrontAvailability] { results.filter(\.isLive).sorted(by: Self.byName) }
    var notLive: [StorefrontAvailability] {
        results.filter { !$0.isLive && !$0.isUnconfirmed }.sorted(by: Self.byName)
    }
    var unconfirmed: [StorefrontAvailability] { results.filter(\.isUnconfirmed).sorted(by: Self.byName) }

    var isLiveAnywhere: Bool { results.contains(where: \.isLive) }

    enum Verdict: Sendable {
        case live
        case notLiveAnywhere
        /// Nothing live, but some storefronts never answered cleanly.
        case notFoundYet
    }

    var verdict: Verdict {
        if isLiveAnywhere { return .live }
        return unconfirmed.isEmpty ? .notLiveAnywhere : .notFoundYet
    }

    /// The listing to feature: the US one if it's live there, otherwise the storefront where
    /// the most people have rated it — the listing most people actually see.
    var featured: StorefrontAvailability? {
        let live = results.filter(\.isLive)
        return live.first { $0.storefront.code == "us" }
            ?? live.max { ($0.app?.userRatingCount ?? 0) < ($1.app?.userRatingCount ?? 0) }
    }

    struct RegionGroup: Identifiable, Sendable {
        let region: StoreRegion
        let items: [StorefrontAvailability]
        var id: StoreRegion { region }
    }

    /// Storefronts grouped the way Apple groups them.
    func grouped(_ items: [StorefrontAvailability]) -> [RegionGroup] {
        StoreRegion.allCases.compactMap { region -> RegionGroup? in
            let matching = items.filter { $0.storefront.region == region }
            return matching.isEmpty ? nil : RegionGroup(region: region, items: matching)
        }
    }

    /// Plain-text list for sharing — "Live in 142 storefronts: …".
    var shareText: String {
        let name = featured?.app?.trackName ?? query
        let countries = live.map { "\($0.storefront.flag) \($0.storefront.name)" }.joined(separator: "\n")
        return "\(name) is live in \(live.count) of \(results.count) App Store storefronts:\n\n\(countries)"
    }
}


import Foundation

struct AppReview: Identifiable, Sendable {
    let id: String
    let author: String
    let title: String
    let body: String
    let rating: Int
    let version: String?
    let updated: Date?
}

enum ReviewSort: String, CaseIterable, Identifiable, Sendable {
    case mostRecent = "mostrecent"
    case mostHelpful = "mosthelpful"
    case mostFavorable = "mostfavorable"
    case mostCritical = "mostcritical"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mostRecent: "Recent"
        case .mostHelpful: "Helpful"
        case .mostFavorable: "Favorable"
        case .mostCritical: "Critical"
        }
    }

    /// Not every storefront serves every sort — some only answer on `mostrecent`. When one
    /// comes back empty we refetch the recent feed and order it here instead, so a tab never
    /// dead-ends. Helpfulness isn't in the feed at all, so length stands in for it.
    func ordered(_ reviews: [AppReview]) -> [AppReview] {
        switch self {
        case .mostRecent:
            reviews.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        case .mostHelpful:
            reviews.sorted { $0.body.count > $1.body.count }
        case .mostFavorable:
            reviews.sorted { $0.rating > $1.rating }
        case .mostCritical:
            reviews.sorted { $0.rating < $1.rating }
        }
    }
}

// MARK: - Aggregation

/// The star breakdown Apple shows on the product page isn't in any public endpoint. This is the
/// distribution of the reviews actually fetched, which skews positive next to the real one —
/// people who write a review are not a random sample of people who tap a star.
struct ReviewDigest: Sendable {

    let reviews: [AppReview]

    var counts: [Int: Int] {
        Dictionary(grouping: reviews, by: \.rating).mapValues(\.count)
    }

    var average: Double? {
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }

    func share(of stars: Int) -> Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(counts[stars] ?? 0) / Double(reviews.count)
    }

    /// Versions mentioned most often, newest complaints first — useful for spotting a bad release.
    var recentVersions: [String] {
        var seen: [String] = []
        for review in reviews.sorted(by: { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }) {
            if let version = review.version, !seen.contains(version) { seen.append(version) }
        }
        return Array(seen.prefix(5))
    }
}


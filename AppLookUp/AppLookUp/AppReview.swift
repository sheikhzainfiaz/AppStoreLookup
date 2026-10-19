import Foundation

// MARK: - Model
//
// Apple exposes review text through the same legacy RSS family as the charts:
//
//   https://itunes.apple.com/{country}/rss/customerreviews/page={n}/id={id}/sortby={sort}/json
//
// Reviews are per-storefront like ratings, 50 to a page, and the feed stops at page 10 — so
// 500 is the ceiling per country no matter how many the app actually has. Sorting by most
// recent and sweeping a few storefronts is the way to get breadth.

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

enum ReviewError: LocalizedError {
    case feedEmpty
    case badResponse

    var errorDescription: String? {
        switch self {
        case .feedEmpty: "No reviews in this storefront yet."
        case .badResponse: "Apple's review feed didn't return anything readable."
        }
    }
}

// MARK: - Service

enum ReviewService {

    static let maxPage = 10
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func reviews(
        trackID: Int,
        country: String,
        page: Int = 1,
        sort: ReviewSort = .mostRecent
    ) async throws -> [AppReview] {

        let path = "https://itunes.apple.com/\(country)/rss/customerreviews"
            + "/page=\(min(page, maxPage))/id=\(trackID)/sortby=\(sort.rawValue)/json"

        guard let url = URL(string: path) else { throw ReviewError.badResponse }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feed = root["feed"] as? [String: Any]
        else { throw ReviewError.badResponse }

        let rawEntries: [[String: Any]]
        if let array = feed["entry"] as? [[String: Any]] {
            rawEntries = array
        } else if let single = feed["entry"] as? [String: Any] {
            rawEntries = [single]
        } else {
            throw ReviewError.feedEmpty
        }

        // Page 1 leads with an entry describing the app itself rather than a review.
        // It has no im:rating, so filtering on that removes it without special-casing.
        let reviews = rawEntries.compactMap(parse(entry:))
        if reviews.isEmpty { throw ReviewError.feedEmpty }
        return reviews
    }

    private static func parse(entry: [String: Any]) -> AppReview? {
        guard
            let ratingText = label(entry["im:rating"]),
            let rating = Int(ratingText),
            let body = label(entry["content"]),
            let id = label(entry["id"])
        else { return nil }

        let author = (entry["author"] as? [String: Any])
            .flatMap { label($0["name"]) } ?? "Anonymous"

        return AppReview(
            id: id,
            author: author,
            title: label(entry["title"]) ?? "",
            body: body,
            rating: rating,
            version: label(entry["im:version"]),
            updated: label(entry["updated"]).flatMap(parseDate)
        )
    }

    /// Nearly every field in this feed is wrapped as `{ "label": "…" }`.
    private static func label(_ value: Any?) -> String? {
        (value as? [String: Any])?["label"] as? String
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
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

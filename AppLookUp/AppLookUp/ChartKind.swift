import Foundation

// MARK: - Chart placement
//
// Apple publishes its top charts as a keyless public feed. The *legacy* endpoint is the one
// worth using: the newer rss.marketingtools.apple.com API dropped genre filtering and returns
// 404 for top-grossing, and category charts are where a niche app is actually visible.
//
//   https://itunes.apple.com/{country}/rss/{chart}/limit={n}/genre={id}/json
//
// Drop the genre segment for the overall chart. Depth caps at 200.

enum ChartKind: String, CaseIterable, Identifiable, Sendable {
    case free = "topfreeapplications"
    case paid = "toppaidapplications"
    case grossing = "topgrossingapplications"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "Top Free"
        case .paid: "Top Paid"
        case .grossing: "Top Grossing"
        }
    }
}

struct ChartPlacement: Identifiable, Sendable {

    enum Position: Sendable {
        case ranked(Int)
        case outsideTop(Int)
        case feedUnavailable
    }

    let chart: ChartKind
    let scopeName: String
    let genreID: Int?
    let position: Position

    var id: String { "\(chart.rawValue)-\(genreID ?? 0)" }

    var rank: Int? {
        if case let .ranked(rank) = position { return rank }
        return nil
    }

    var summary: String {
        switch position {
        case let .ranked(rank): "#\(rank)"
        case let .outsideTop(depth): "outside top \(depth)"
        case .feedUnavailable: "no chart"
        }
    }
}

enum ChartRankService {

    /// Apple returns an empty body to plain server agents, so the feed needs a browser UA.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Checks all three charts, overall and inside the app's own category.
    static func placements(
        for app: AppStoreApp,
        country: String,
        depth: Int = 200
    ) async -> [ChartPlacement] {

        var scopes: [(name: String, genreID: Int?)] = [("Overall", nil)]
        if let genreID = app.primaryGenreId {
            scopes.append((app.primaryGenreName ?? "Category", genreID))
        }

        var placements: [ChartPlacement] = []

        // Sequential on purpose: six 200-entry feeds fired at once is a reliable way to get
        // rate-limited, and the whole sweep still finishes in a couple of seconds.
        for scope in scopes {
            for chart in ChartKind.allCases {
                let position = await position(
                    of: app.trackId,
                    chart: chart,
                    country: country,
                    genreID: scope.genreID,
                    depth: depth
                )
                placements.append(
                    ChartPlacement(
                        chart: chart,
                        scopeName: scope.name,
                        genreID: scope.genreID,
                        position: position
                    )
                )
            }
        }
        return placements
    }

    /// The full ranked list, used by the calibration sampler.
    static func chartEntries(
        chart: ChartKind,
        country: String,
        genreID: Int?,
        depth: Int = 200
    ) async -> [(rank: Int, trackID: Int)] {

        var path = "https://itunes.apple.com/\(country)/rss/\(chart.rawValue)/limit=\(depth)"
        if let genreID { path += "/genre=\(genreID)" }
        path += "/json"

        guard let url = URL(string: path) else { return [] }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let ids = parseIDs(from: data)
        else { return [] }

        return ids.enumerated().compactMap { index, id in
            Int(id).map { (rank: index + 1, trackID: $0) }
        }
    }

    private static func position(
        of trackID: Int,
        chart: ChartKind,
        country: String,
        genreID: Int?,
        depth: Int
    ) async -> ChartPlacement.Position {

        var path = "https://itunes.apple.com/\(country)/rss/\(chart.rawValue)/limit=\(depth)"
        if let genreID { path += "/genre=\(genreID)" }
        path += "/json"

        guard let url = URL(string: path) else { return .feedUnavailable }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let ids = parseIDs(from: data)
        else { return .feedUnavailable }

        if let index = ids.firstIndex(of: String(trackID)) {
            return .ranked(index + 1)
        }
        return ids.isEmpty ? .feedUnavailable : .outsideTop(ids.count)
    }

    /// The legacy feed nests IDs four levels deep under keys containing colons, which Codable
    /// handles badly. Pulling them out by hand is shorter than the model it would need.
    private static func parseIDs(from data: Data) -> [String]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feed = root["feed"] as? [String: Any]
        else { return nil }

        guard let entries = feed["entry"] as? [[String: Any]] else {
            // A chart with a single entry decodes as a dictionary, and an empty one omits the key.
            if let single = feed["entry"] as? [String: Any] {
                return [id(in: single)].compactMap { $0 }
            }
            return []
        }

        return entries.compactMap(id(in:))
    }

    private static func id(in entry: [String: Any]) -> String? {
        (entry["id"] as? [String: Any])
            .flatMap { $0["attributes"] as? [String: Any] }
            .flatMap { $0["im:id"] as? String }
    }
}

// MARK: - Ratings velocity

/// One day's reading of an app's cumulative rating count in one storefront.
struct RatingSnapshot: Codable, Sendable, Identifiable {
    let date: Date
    let count: Int
    let average: Double
    var id: Date { date }
}

/// Ratings velocity is the only download-shaped signal you can measure yourself rather than
/// buy. `userRatingCount` is cumulative, so the day-over-day delta is genuine new ratings.
@MainActor
final class RatingHistoryStore {

    static let shared = RatingHistoryStore()
    private let defaults = UserDefaults.standard
    private let prefix = "ratingHistory."

    private init() {}

    private func key(trackID: Int, country: String) -> String {
        "\(prefix)\(trackID).\(country)"
    }

    func history(trackID: Int, country: String) -> [RatingSnapshot] {
        guard let data = defaults.data(forKey: key(trackID: trackID, country: country)) else { return [] }
        let decoded = (try? JSONDecoder().decode([RatingSnapshot].self, from: data)) ?? []
        return decoded.sorted { $0.date < $1.date }
    }

    /// Keeps one reading per calendar day; a second lookup the same day overwrites the first.
    func record(trackID: Int, country: String, count: Int, average: Double) {
        var entries = history(trackID: trackID, country: country)
        let today = Calendar.current.startOfDay(for: .now)

        entries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
        entries.append(RatingSnapshot(date: .now, count: count, average: average))
        entries = entries.suffix(180)

        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key(trackID: trackID, country: country))
        }
    }

    func reset(trackID: Int, country: String) {
        defaults.removeObject(forKey: key(trackID: trackID, country: country))
    }
}

/// A download range inferred from ratings velocity.
///
/// The conversion rests on one uncertain number: what share of installs leave a rating. Since
/// iOS 11's native prompt that typically lands somewhere between 0.5% and 2%, varying with how
/// aggressively the app asks, its category, and its country. So this reports a range, not a
/// figure — a point estimate here would be false precision.
struct DownloadEstimate: Sendable {

    static let lowestRatingRate = 0.005
    static let highestRatingRate = 0.020

    let ratingsPerDay: Double
    let spanDays: Double
    let sampleCount: Int

    var lowDailyInstalls: Int { Int((ratingsPerDay / Self.highestRatingRate).rounded()) }
    var highDailyInstalls: Int { Int((ratingsPerDay / Self.lowestRatingRate).rounded()) }

    /// Under a week of readings, day-of-week effects dominate and the number swings wildly.
    var isReliable: Bool { spanDays >= 7 }

    init?(history: [RatingSnapshot]) {
        guard let first = history.first, let last = history.last, history.count >= 2 else { return nil }

        let span = last.date.timeIntervalSince(first.date) / 86_400
        guard span >= 0.5 else { return nil }

        let delta = Double(last.count - first.count)
        guard delta >= 0 else { return nil } // Apple occasionally resets counts on a store change.

        ratingsPerDay = delta / span
        spanDays = span
        sampleCount = history.count
    }
}

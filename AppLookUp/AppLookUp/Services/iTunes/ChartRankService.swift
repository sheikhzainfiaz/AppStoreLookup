import Foundation

// Apple publishes its top charts as a keyless public feed. The *legacy* endpoint is the one
// worth using: the newer rss.marketingtools.apple.com API dropped genre filtering and returns
// 404 for top-grossing, and category charts are where a niche app is actually visible.
//
//   https://itunes.apple.com/{country}/rss/{chart}/limit={n}/genre={id}/json
//
// Drop the genre segment for the overall chart. Depth caps at 200.

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


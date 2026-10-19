import Foundation
import Observation

/// Persists earnings anchors — your own apps' real monthly proceeds — and answers the questions
/// `RevenueEngine` asks of them. Shared across screens.
@Observable
@MainActor
final class RevenueAnchorStore {

    static let shared = RevenueAnchorStore()

    private(set) var anchors: [RevenueAnchor] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "revenue.anchors"

    private init() {
        if let data = defaults.data(forKey: storageKey) {
            anchors = (try? JSONDecoder().decode([RevenueAnchor].self, from: data)) ?? []
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(anchors) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: Anchors

    /// One anchor per app per storefront; saving again replaces the old reading.
    func addAnchor(_ anchor: RevenueAnchor) {
        anchors.removeAll { $0.trackID == anchor.trackID && $0.country == anchor.country }
        anchors.append(anchor)
        persist()
    }

    func removeAnchor(_ anchor: RevenueAnchor) {
        anchors.removeAll { $0.id == anchor.id }
        persist()
    }

    func clearAnchors() {
        anchors = []
        persist()
    }

    // MARK: Queries

    /// (rank, monthly proceeds) pairs for one grossing chart. Strictly the same storefront:
    /// #50 in the US and #50 in Pakistan are different orders of magnitude.
    func rankedPoints(country: String, genreID: Int?) -> [(rank: Int, value: Double)] {
        anchors.compactMap { anchor -> (rank: Int, value: Double)? in
            guard anchor.country == country, anchor.monthlyProceedsUSD > 0 else { return nil }
            if let genreID {
                guard anchor.genreID == genreID, let rank = anchor.categoryGrossingRank else { return nil }
                return (rank, anchor.monthlyProceedsUSD)
            }
            guard let rank = anchor.overallGrossingRank else { return nil }
            return (rank, anchor.monthlyProceedsUSD)
        }
    }

    /// Prefers anchors from the same category and storefront, widening only if it has to.
    func proceedsPerDownload(country: String, genreID: Int?) -> PerDownloadRate? {
        let tiers: [[RevenueAnchor]] = [
            anchors.filter { $0.country == country && $0.genreID == genreID },
            anchors.filter { $0.genreID == genreID },
        ]
        for (index, tier) in tiers.enumerated() {
            let values = tier.compactMap(\.proceedsPerDownload).sorted()
            guard !values.isEmpty else { continue }
            let median = values.count.isMultiple(of: 2)
                ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2
                : values[values.count / 2]
            return PerDownloadRate(
                median: median,
                lowest: values.first!,
                highest: values.last!,
                sampleCount: values.count,
                isExactMatch: index == 0
            )
        }
        // A different category's monetisation is no guide at all, so no final "any anchor" tier.
        return nil
    }
}

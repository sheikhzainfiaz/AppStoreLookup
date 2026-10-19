import Foundation
import Observation

/// Persists everything the download calibration learns: anchors from your own apps, fitted rank
/// curves, and the chart sample waiting for its second pass. Shared across screens.
@MainActor
@Observable
final class DownloadCalibrationStore {

    static let shared = DownloadCalibrationStore()

    private(set) var anchors: [CalibrationAnchor] = []
    private(set) var curves: [RankCurve] = []
    private(set) var pendingSamples: [ChartSample] = []

    private let defaults = UserDefaults.standard

    private init() {
        anchors = load([CalibrationAnchor].self, key: "calibration.anchors") ?? []
        curves = load([RankCurve].self, key: "calibration.curves") ?? []
        pendingSamples = load([ChartSample].self, key: "calibration.samples") ?? []
    }

    // MARK: Persistence

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Anchors

    func addAnchor(_ anchor: CalibrationAnchor) {
        anchors.append(anchor)
        save(anchors, key: "calibration.anchors")
    }

    func removeAnchor(_ anchor: CalibrationAnchor) {
        anchors.removeAll { $0.id == anchor.id }
        save(anchors, key: "calibration.anchors")
    }

    /// Prefers anchors from the same category and storefront, widening only if it has to —
    /// a productivity app in Germany is a poor guide to a game in Brazil.
    func ratingRate(country: String, genreID: Int?) -> RatingRate? {
        let tiers: [[CalibrationAnchor]] = [
            anchors.filter { $0.country == country && $0.genreID == genreID },
            anchors.filter { $0.genreID == genreID },
            anchors.filter { $0.country == country },
            anchors,
        ]

        for tier in tiers {
            let rates = tier.compactMap(\.ratingRate).filter { $0 > 0 }
            guard !rates.isEmpty else { continue }

            let sorted = rates.sorted()
            let median = sorted.count.isMultiple(of: 2)
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]

            return RatingRate(
                median: median,
                lowest: sorted.first!,
                highest: sorted.last!,
                sampleCount: sorted.count,
                isExactMatch: tier.allSatisfy { $0.country == country && $0.genreID == genreID }
            )
        }
        return nil
    }

    // MARK: Curves

    func curve(country: String, genreID: Int?) -> RankCurve? {
        curves.first { $0.country == country && $0.genreID == genreID }
            ?? curves.first { $0.country == country }
    }

    func storeCurve(_ curve: RankCurve) {
        curves.removeAll { $0.country == curve.country && $0.genreID == curve.genreID }
        curves.append(curve)
        save(curves, key: "calibration.curves")
    }

    // MARK: Samples

    func storeSample(_ sample: ChartSample) {
        pendingSamples.removeAll { $0.country == sample.country && $0.genreID == sample.genreID }
        pendingSamples.append(sample)
        save(pendingSamples, key: "calibration.samples")
    }

    func pendingSample(country: String, genreID: Int?) -> ChartSample? {
        pendingSamples.first { $0.country == country && $0.genreID == genreID }
    }

    func clearAll() {
        anchors = []
        curves = []
        pendingSamples = []
        for key in ["calibration.anchors", "calibration.curves", "calibration.samples"] {
            defaults.removeObject(forKey: key)
        }
    }
}


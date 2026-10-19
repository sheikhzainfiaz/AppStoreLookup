//
//  CalibrationAnchor.swift
//  Applookup
//
//  Created by Sheikh Zain Fiaz on 19/09/2026.
//


import Foundation

// MARK: - The method
//
// Nobody can read install counts off a public endpoint. What you *can* do is calibrate.
//
//   1. ANCHOR. You know your own app's real daily downloads from App Store Connect. This app
//      already measures its ratings velocity. Divide, and you have the true rating rate for
//      your category and storefront — the one number every "estimated downloads" product
//      guesses at. One anchor replaces the 0.5–2% band with a measured constant.
//
//   2. SHAPE. Sampling the top charts gives (rank, ratings-per-day) pairs for dozens of apps
//      at no cost beyond lookups. Fitting a power law to those yields the rank curve's shape,
//      which lets you estimate an app you've seen only once, from its chart position alone.
//
//   3. CROSS-CHECK. Velocity and rank are independent estimators. When they agree, confidence
//      is high. When they diverge, that divergence is itself the finding — usually paid UA,
//      a rating prompt change, or a chart manipulation.
//
// This is the same shape as what the paid intelligence platforms do. They have thousands of
// anchors; you have yours. For peers in your own category that's a narrower, better-matched
// calibration than a global model.

// MARK: - Anchor

/// One day where both the real download count and the measured ratings velocity are known.
struct CalibrationAnchor: Codable, Identifiable, Sendable {

    var id = UUID()
    var appName: String
    var trackID: Int
    var country: String
    var genreID: Int?
    /// Actual units from App Store Connect Sales and Trends.
    var dailyDownloads: Double
    /// Measured here from the cumulative rating-count delta.
    var ratingsPerDay: Double
    var recordedAt = Date()

    /// The share of installs that leave a rating — measured, not assumed.
    var ratingRate: Double? {
        guard dailyDownloads > 0, ratingsPerDay >= 0 else { return nil }
        return ratingsPerDay / dailyDownloads
    }
}

// MARK: - Rank curve

/// App Store chart position follows a power law: value(rank) = scale × rank^(-exponent).
/// Fitted in ratings-per-day, then converted to downloads by the anchored rating rate.
struct RankCurve: Codable, Sendable {

    var scale: Double
    var exponent: Double
    var rSquared: Double
    var sampleCount: Int
    var country: String
    var genreID: Int?
    var fittedAt: Date

    /// Typical iOS chart decay when there's nothing better to go on.
    static let assumedExponent = 0.9

    func ratingsPerDay(atRank rank: Int) -> Double {
        guard rank > 0 else { return scale }
        return scale * pow(Double(rank), -exponent)
    }

    var isTrustworthy: Bool { rSquared >= 0.5 && sampleCount >= 8 }

    /// Ordinary least squares on log–log, which is what a power law becomes when you take logs.
    static func fit(
        points: [(rank: Int, value: Double)],
        country: String,
        genreID: Int?
    ) -> RankCurve? {

        let usable = points.filter { $0.rank > 0 && $0.value > 0 }
        guard usable.count >= 4 else { return nil }

        let xs = usable.map { log(Double($0.rank)) }
        let ys = usable.map { log($0.value) }
        let n = Double(usable.count)

        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var covariance = 0.0
        var varianceX = 0.0
        for index in usable.indices {
            covariance += (xs[index] - meanX) * (ys[index] - meanY)
            varianceX += pow(xs[index] - meanX, 2)
        }
        guard varianceX > 0 else { return nil }

        let slope = covariance / varianceX
        let intercept = meanY - slope * meanX

        var residual = 0.0
        var totalVariance = 0.0
        for index in usable.indices {
            let predicted = intercept + slope * xs[index]
            residual += pow(ys[index] - predicted, 2)
            totalVariance += pow(ys[index] - meanY, 2)
        }
        let rSquared = totalVariance > 0 ? max(0, 1 - residual / totalVariance) : 0

        return RankCurve(
            scale: exp(intercept),
            // A rising chart means a falling value, so the exponent is the negated slope.
            exponent: -slope,
            rSquared: rSquared,
            sampleCount: usable.count,
            country: country,
            genreID: genreID,
            fittedAt: .now
        )
    }
}

// MARK: - Chart sampling

/// One reading of a charting app: where it sat and how many ratings it had at that moment.
struct ChartSampleEntry: Codable, Sendable {
    let trackID: Int
    let rank: Int
    let ratingCount: Int
    let date: Date
}

struct ChartSample: Codable, Sendable {
    var country: String
    var genreID: Int?
    var entries: [ChartSampleEntry]
    var takenAt: Date
}

// MARK: - Store

@MainActor
@Observable
final class DownloadModel {

    static let shared = DownloadModel()

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

struct RatingRate: Sendable {
    let median: Double
    let lowest: Double
    let highest: Double
    let sampleCount: Int
    /// True when every anchor behind this came from the same category and storefront.
    let isExactMatch: Bool
}

// MARK: - Estimate

struct CalibratedEstimate: Sendable {

    enum Source: Sendable {
        case measuredVelocity
        case rankCurve
        case agreement
        case conflict
        case uncalibrated

        var label: String {
            switch self {
            case .measuredVelocity: "From measured ratings velocity"
            case .rankCurve: "From chart position"
            case .agreement: "Velocity and rank agree"
            case .conflict: "Velocity and rank disagree"
            case .uncalibrated: "Uncalibrated range"
            }
        }
    }

    let daily: Double
    let low: Double
    let high: Double
    let source: Source
    let detail: String

    var isCalibrated: Bool { source != .uncalibrated }

    /// How far apart the two independent estimates landed, as a ratio ≥ 1.
    var divergence: Double? = nil
}

enum EstimateEngine {

    /// Divergence beyond this means the two methods are telling different stories, and the
    /// gap is usually paid installs the ratings prompt never sees.
    static let conflictThreshold = 2.5

    static func estimate(
        ratingsPerDay: Double?,
        rank: Int?,
        country: String,
        genreID: Int?,
        model: DownloadModel
    ) -> CalibratedEstimate {

        let rate = model.ratingRate(country: country, genreID: genreID)
        let curve = model.curve(country: country, genreID: genreID)

        // Without an anchor there's no measured rating rate, so fall back to the open range.
        guard let rate else {
            guard let ratingsPerDay, ratingsPerDay > 0 else {
                return CalibratedEstimate(
                    daily: 0, low: 0, high: 0, source: .uncalibrated,
                    detail: "Add an anchor from an app you own to turn these signals into numbers."
                )
            }
            return CalibratedEstimate(
                daily: ratingsPerDay / 0.01,
                low: ratingsPerDay / DownloadEstimate.highestRatingRate,
                high: ratingsPerDay / DownloadEstimate.lowestRatingRate,
                source: .uncalibrated,
                detail: "Assuming 0.5–2% of installs rate. Anchor it and this narrows sharply."
            )
        }

        let fromVelocity = ratingsPerDay.map { $0 / rate.median }
        let fromRank: Double? = {
            guard let rank, let curve, curve.isTrustworthy else { return nil }
            return curve.ratingsPerDay(atRank: rank) / rate.median
        }()

        let matchNote = rate.isExactMatch
            ? "\(rate.sampleCount) anchor\(rate.sampleCount == 1 ? "" : "s") in this category and store"
            : "\(rate.sampleCount) anchor\(rate.sampleCount == 1 ? "" : "s"), none from this exact category"

        switch (fromVelocity, fromRank) {
        case let (velocity?, rankEstimate?):
            let divergence = max(velocity, rankEstimate) / max(min(velocity, rankEstimate), 0.0001)
            let blended = sqrt(velocity * rankEstimate) // geometric mean; these are multiplicative

            return CalibratedEstimate(
                daily: blended,
                low: min(velocity, rankEstimate),
                high: max(velocity, rankEstimate),
                source: divergence <= conflictThreshold ? .agreement : .conflict,
                detail: divergence <= conflictThreshold
                    ? "Both methods land within \(String(format: "%.1f", divergence))×. \(matchNote)."
                    : "Rank implies \(String(format: "%.1f", divergence))× the velocity figure — often paid installs, which don't generate ratings at the organic rate.",
                divergence: divergence
            )

        case let (velocity?, nil):
            let measured = ratingsPerDay ?? 0
            return CalibratedEstimate(
                daily: velocity,
                low: measured / rate.highest,
                high: measured / rate.lowest,
                source: .measuredVelocity,
                detail: "Measured rating rate of \(String(format: "%.2f", rate.median * 100))%. \(matchNote)."
            )

        case let (nil, rankEstimate?):
            return CalibratedEstimate(
                daily: rankEstimate,
                low: rankEstimate / 2,
                high: rankEstimate * 2,
                source: .rankCurve,
                detail: "From the fitted chart curve. Wide band — one reading of rank carries much less than a measured delta."
            )

        case (nil, nil):
            return CalibratedEstimate(
                daily: 0, low: 0, high: 0, source: .uncalibrated,
                detail: "Look this app up again tomorrow, or fit a chart curve, to get a number."
            )
        }
    }
}
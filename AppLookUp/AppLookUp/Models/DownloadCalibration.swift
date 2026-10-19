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


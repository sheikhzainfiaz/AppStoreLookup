import Foundation

enum EstimateEngine {

    /// Divergence beyond this means the two methods are telling different stories, and the
    /// gap is usually paid installs the ratings prompt never sees.
    static let conflictThreshold = 2.5

    static func estimate(
        ratingsPerDay: Double?,
        rank: Int?,
        country: String,
        genreID: Int?,
        store: DownloadCalibrationStore
    ) -> CalibratedEstimate {

        let rate = store.ratingRate(country: country, genreID: genreID)
        let curve = store.curve(country: country, genreID: genreID)

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

//
//  RevenueEngine.swift
//  Applookup
//
//  v2: monthly earnings for apps you don't own.
//
//  The method mirrors the download calibration in DownloadCalibration.swift and EstimateEngine.swift:
//
//    1. ANCHOR. Your own app's real monthly proceeds in one storefront (from the Earnings tab,
//       or typed in from App Store Connect), saved with its Top Grossing rank that day.
//
//    2. RANK. Grossing charts follow a power law just like download charts. Two anchors at
//       different ranks fit the curve; one anchor plus the typical decay gives a wider band.
//       An app outside the top 200 still gets a ceiling: it earns less than whatever #200 does.
//
//    3. PER DOWNLOAD. Anchors that also carry their download count give proceeds-per-download
//       for the category, which multiplies against this app's calibrated download estimate.
//       Paid apps skip this step — price × 70–85% is the per-download figure.
//
//  Where both methods land, they're cross-checked exactly like velocity and rank are.
//  Everything here is per storefront, in US dollars, as developer proceeds (after Apple's cut).
//

import Foundation

// MARK: - Curve

struct PowerLaw: Sendable {
    let scale: Double
    let exponent: Double
    /// Residual standard deviation in log space; zero when there are only two points.
    let sigma: Double
    let count: Int

    func value(at rank: Double) -> Double { scale * pow(rank, -exponent) }

    static func fit(_ points: [(rank: Int, value: Double)]) -> PowerLaw? {
        let usable = points.filter { $0.rank > 0 && $0.value > 0 }
        guard usable.count >= 2 else { return nil }

        let xs = usable.map { log(Double($0.rank)) }
        let ys = usable.map { log($0.value) }
        let n = Double(usable.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var sxx = 0.0
        var sxy = 0.0
        for index in usable.indices {
            sxx += pow(xs[index] - meanX, 2)
            sxy += (xs[index] - meanX) * (ys[index] - meanY)
        }
        guard sxx > 0 else { return nil }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        var residual = 0.0
        for index in usable.indices {
            residual += pow(ys[index] - (intercept + slope * xs[index]), 2)
        }
        let sigma = usable.count > 2 ? sqrt(residual / (n - 2)) : 0

        return PowerLaw(scale: exp(intercept), exponent: -slope, sigma: sigma, count: usable.count)
    }
}

private struct Leg {
    let mid: Double
    let low: Double
    let high: Double
    let source: RevenueEstimate.Source
    let note: String
}

enum RevenueEngine {

    static let conflictThreshold = 2.5
    /// Typical grossing-chart decay, and the band either side of it for single-anchor scaling.
    static let assumedExponent = 0.9
    static let exponentBand = 0.7...1.1

    static func estimate(
        app: AppStoreApp,
        country: String,
        placements: [ChartPlacement],
        downloads: CalibratedEstimate?,
        store: RevenueAnchorStore,
        currency: CurrencyConverter
    ) -> RevenueEstimate {

        let rank = rankSignal(country: country, placements: placements, store: store)
        let perDownload = downloadLeg(app: app, country: country, downloads: downloads, store: store, currency: currency)
        let place = Storefront.named(country).name

        switch (rank.leg, perDownload) {

        case let (rankLeg?, downloadLeg?):
            let divergence = max(rankLeg.mid, downloadLeg.mid) / max(min(rankLeg.mid, downloadLeg.mid), 0.01)
            let agrees = divergence <= conflictThreshold
            return RevenueEstimate(
                monthly: sqrt(rankLeg.mid * downloadLeg.mid),
                low: min(rankLeg.mid, downloadLeg.mid),
                high: max(rankLeg.mid, downloadLeg.mid),
                source: agrees ? .agreement : .conflict,
                detail: agrees
                    ? "Both methods land within \(String(format: "%.1f", divergence))× of each other in \(place)."
                    : "Rank implies \(String(format: "%.1f", divergence))× what downloads do. Usually heavy in-app spending from few users, or paid installs inflating downloads."
            )

        case let (rankLeg?, nil):
            return RevenueEstimate(
                monthly: rankLeg.mid, low: rankLeg.low, high: rankLeg.high,
                source: rankLeg.source, detail: rankLeg.note
            )

        case let (nil, downloadLeg?):
            if let ceiling = rank.ceiling, downloadLeg.mid > ceiling {
                return RevenueEstimate(
                    monthly: ceiling, low: min(downloadLeg.low, ceiling), high: ceiling,
                    source: .belowChart,
                    detail: "\(downloadLeg.note) Capped at \(formatUSD(ceiling)): it isn't in the Top Grossing 200, and that's roughly what #200 earns."
                )
            }
            return RevenueEstimate(
                monthly: downloadLeg.mid, low: downloadLeg.low, high: downloadLeg.high,
                source: downloadLeg.source, detail: downloadLeg.note
            )

        case (nil, nil):
            if let ceiling = rank.ceiling {
                return RevenueEstimate(
                    monthly: ceiling, low: 0, high: ceiling, source: .belowChart,
                    detail: "Not in the Top Grossing 200 in \(place). Your anchors put #200 at about \(formatUSD(ceiling)) a month, so it earns less than that here."
                )
            }
            return RevenueEstimate(
                monthly: 0, low: 0, high: 0, source: .unavailable,
                detail: missingInputs(app: app, country: country, placements: placements, downloads: downloads, store: store)
            )
        }
    }

    // MARK: Rank

    private static func rankSignal(
        country: String,
        placements: [ChartPlacement],
        store: RevenueAnchorStore
    ) -> (leg: Leg?, ceiling: Double?) {

        // Category chart first: it's where most apps are visible and anchors match best.
        let grossing = placements
            .filter { $0.chart == .grossing }
            .sorted { ($0.genreID == nil ? 1 : 0) < ($1.genreID == nil ? 1 : 0) }

        var ceiling: Double?

        for placement in grossing {
            let points = store.rankedPoints(country: country, genreID: placement.genreID)
            guard !points.isEmpty else { continue }

            switch placement.position {
            case let .ranked(rank):
                if let leg = curveLeg(at: rank, points: points, scopeName: placement.scopeName) {
                    return (leg, nil)
                }
            case let .outsideTop(depth):
                if ceiling == nil {
                    ceiling = curveLeg(at: depth, points: points, scopeName: placement.scopeName)?.mid
                }
            case .feedUnavailable:
                continue
            }
        }
        return (nil, ceiling)
    }

    private static func curveLeg(at rank: Int, points: [(rank: Int, value: Double)], scopeName: String) -> Leg? {
        let usable = points.filter { $0.rank > 0 && $0.value > 0 }
        guard !usable.isEmpty, rank > 0 else { return nil }

        let target = Double(rank)
        let ranks = Set(usable.map(\.rank))

        if ranks.count >= 2, let fit = PowerLaw.fit(usable), (0.3...2.0).contains(fit.exponent) {
            let mid = fit.value(at: target)
            var spread = max(1.4, exp(fit.sigma * 1.5))
            let inside = Double(ranks.min()!)...Double(ranks.max()!)
            if !inside.contains(target) { spread *= 1.5 } // extrapolating past the anchors
            return Leg(
                mid: mid, low: mid / spread, high: mid * spread, source: .grossingRank,
                note: "#\(rank) Top Grossing in \(scopeName), on a curve fitted from \(fit.count) of your anchors (decay \(String(format: "%.2f", fit.exponent)))."
            )
        }

        // One anchor: scale by typical decay, and let the exponent's plausible range set the band.
        let nearest = usable.min { abs(log(Double($0.rank) / target)) < abs(log(Double($1.rank) / target)) }!
        let ratio = Double(nearest.rank) / target
        let mid = nearest.value * pow(ratio, assumedExponent)
        let a = nearest.value * pow(ratio, exponentBand.lowerBound)
        let b = nearest.value * pow(ratio, exponentBand.upperBound)
        return Leg(
            mid: mid, low: min(a, b, mid / 1.3), high: max(a, b, mid * 1.3), source: .grossingRank,
            note: "#\(rank) Top Grossing in \(scopeName), scaled from one anchor at #\(nearest.rank). An anchor at a different rank would fit the real curve and narrow this."
        )
    }

    // MARK: Downloads

    private static func downloadLeg(
        app: AppStoreApp,
        country: String,
        downloads: CalibratedEstimate?,
        store: RevenueAnchorStore,
        currency: CurrencyConverter
    ) -> Leg? {

        guard let downloads, downloads.daily > 0 else { return nil }

        let monthly = downloads.daily * 30
        let low = max(downloads.low, 0) * 30
        let high = max(downloads.high, downloads.daily) * 30
        let caveat = downloads.isCalibrated ? "" : " Downloads are uncalibrated, so the band is wide."
        let perMonth = Int(monthly.rounded()).formatted()

        // Paid upfront: the per-download figure is the price, minus Apple's 30% (15% on the
        // Small Business Program).
        if let price = app.price, price > 0, let priceUSD = currency.toUSD(price, currency: app.currency ?? "USD") {
            return Leg(
                mid: monthly * priceUSD * 0.775,
                low: low * priceUSD * 0.70,
                high: high * priceUSD * 0.85,
                source: .paidUpfront,
                note: "≈\(perMonth) downloads a month × \(app.priceLabel), keeping 70–85% after Apple's commission. Upfront sales only; in-app purchases aren't counted.\(caveat)"
            )
        }

        guard let rate = store.proceedsPerDownload(country: country, genreID: app.primaryGenreId) else { return nil }
        let match = rate.isExactMatch ? "this category and store" : "this category, other stores"
        return Leg(
            mid: monthly * rate.median,
            low: low * rate.lowest,
            high: high * rate.highest,
            source: .perDownload,
            note: "≈\(perMonth) downloads a month × \(formatUSD(rate.median, cents: true)) per download, from \(rate.sampleCount) anchor\(rate.sampleCount == 1 ? "" : "s") in \(match).\(caveat)"
        )
    }

    private static func missingInputs(
        app: AppStoreApp,
        country: String,
        placements: [ChartPlacement],
        downloads: CalibratedEstimate?,
        store: RevenueAnchorStore
    ) -> String {
        let place = Storefront.named(country).name
        if store.anchors.isEmpty {
            return "Apple doesn't publish earnings. Anchor one of your own apps below — with its real proceeds from the Earnings tab — and every app in the same charts becomes estimable."
        }
        if placements.isEmpty {
            return "Check the Top Grossing charts to place this app against your anchors."
        }
        if store.rankedPoints(country: country, genreID: nil).isEmpty,
           store.rankedPoints(country: country, genreID: app.primaryGenreId).isEmpty {
            return "None of your anchors are ranked on a \(place) Top Grossing chart. Anchor an app that charts here, or switch to a storefront you have anchors in."
        }
        if downloads == nil || (downloads?.daily ?? 0) == 0 {
            return "It isn't ranked on a chart your anchors cover, and there's no download estimate yet to fall back on."
        }
        return "Not enough overlap between this app and your anchors to produce a figure."
    }
}


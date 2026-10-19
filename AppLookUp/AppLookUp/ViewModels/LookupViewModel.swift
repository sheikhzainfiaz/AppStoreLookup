import Foundation
import Observation

/// One country opened from the map or the list.
struct StorefrontInspection: Identifiable {
    let storefront: Storefront
    var app: AppStoreApp?
    var failure: String?
    var isLoading = true
    var id: String { storefront.code }
}

/// The Lookup tab: one app in one storefront, and every signal the report derives from it.
@Observable
@MainActor
final class LookupViewModel {

    // MARK: State

    var query = ""
    var country = "us"

    private(set) var app: AppStoreApp?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// True when the last lookup failed only because the app isn't sold in the chosen
    /// storefront — the cue to offer a sweep of every other country.
    private(set) var lastLookupWasNotFound = false

    private(set) var world: WorldRatingSummary?
    private(set) var isScanningWorld = false
    private(set) var scanned = 0
    private(set) var scanTotal = Storefront.all.count

    var inspection: StorefrontInspection?

    private(set) var placements: [ChartPlacement] = []
    private(set) var isCheckingCharts = false
    private(set) var ratingHistory: [RatingSnapshot] = []

    var showingCalibration = false
    private(set) var isCalibrating = false
    private(set) var calibrationProgress = 0.0
    private(set) var calibrationStatus: String?

    /// Review text pages and sorts on its own, so it gets its own view model.
    let reviews = ReviewsViewModel()

    // MARK: Dependencies

    private let calibrationStore: DownloadCalibrationStore
    private let revenueStore: RevenueAnchorStore
    private let currency: CurrencyConverter
    private let historyStore: RatingHistoryStore

    convenience init() {
        self.init(
            calibrationStore: .shared,
            revenueStore: .shared,
            currency: .shared,
            historyStore: .shared
        )
    }

    init(
        calibrationStore: DownloadCalibrationStore,
        revenueStore: RevenueAnchorStore,
        currency: CurrencyConverter,
        historyStore: RatingHistoryStore
    ) {
        self.calibrationStore = calibrationStore
        self.revenueStore = revenueStore
        self.currency = currency
        self.historyStore = historyStore
    }

    // MARK: Lookup

    var storefront: Storefront { Storefront.named(country) }

    var canSubmit: Bool {
        !isLoading && AppStoreLookupService.identifier(from: query) != nil
    }

    func submit() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastLookupWasNotFound = false
        world = nil
        placements = []
        ratingHistory = []
        reviews.reset(to: nil)

        do {
            let found = try await AppStoreLookupService.lookup(query, country: country)
            app = found
            reviews.reset(to: .init(trackID: found.trackId, country: country))

            // Every lookup doubles as a datapoint. Enough of them and the deltas mean something.
            if let count = found.userRatingCount, let average = found.averageUserRating {
                historyStore.record(
                    trackID: found.trackId,
                    country: country,
                    count: count,
                    average: average
                )
            }
            ratingHistory = historyStore.history(trackID: found.trackId, country: country)
        } catch {
            app = nil
            errorMessage = error.localizedDescription
            if let lookupError = error as? LookupError, case .notFound = lookupError {
                lastLookupWasNotFound = true
            }
        }
        isLoading = false
    }

    /// The storefront picker re-runs the lookup, but only once there's a report to refresh.
    func countryChanged() async {
        guard app != nil else { return }
        await submit()
    }

    func clear() {
        query = ""
        app = nil
        errorMessage = nil
        lastLookupWasNotFound = false
        world = nil
        inspection = nil
        reviews.reset(to: nil)
    }

    // MARK: World

    func scanWorld() async {
        guard let app, !isScanningWorld else { return }
        isScanningWorld = true
        scanned = 0

        world = await AppStoreLookupService.ratingsAcrossStorefronts(for: app.trackId) { done, total in
            Task { @MainActor in
                self.scanned = done
                self.scanTotal = total
            }
        }
        isScanningWorld = false
    }

    /// Pull this app's full listing as it appears in one specific country.
    func inspect(_ storefront: Storefront) async {
        guard let app else { return }
        inspection = StorefrontInspection(storefront: storefront)

        do {
            let local = try await AppStoreLookupService.lookup(String(app.trackId), country: storefront.code)
            guard inspection?.storefront.code == storefront.code else { return }
            inspection?.app = local
        } catch {
            guard inspection?.storefront.code == storefront.code else { return }
            inspection?.failure = error.localizedDescription
        }
        inspection?.isLoading = false
    }

    /// Promote an inspected country to the main view.
    func makePrimary(_ storefront: Storefront) async {
        inspection = nil
        country = storefront.code
        await submit()
    }

    // MARK: Charts and velocity

    func checkCharts() async {
        guard let app, !isCheckingCharts else { return }
        isCheckingCharts = true
        placements = await ChartRankService.placements(for: app, country: country)
        isCheckingCharts = false
    }

    /// Scope names in the order the charts were read — "Overall", then the app's category.
    var placementScopes: [String] {
        var seen: [String] = []
        for placement in placements where !seen.contains(placement.scopeName) {
            seen.append(placement.scopeName)
        }
        return seen
    }

    func placements(in scope: String) -> [ChartPlacement] {
        placements.filter { $0.scopeName == scope }
    }

    var grossingPlacements: [ChartPlacement] {
        placements.filter { $0.chart == .grossing }
    }

    /// The best available chart position: overall Top Free, falling back to the category chart.
    var bestRank: Int? {
        placements.first { $0.genreID == nil && $0.chart == .free }?.rank
            ?? placements.first { $0.chart == .free }?.rank
    }

    var estimate: DownloadEstimate? { DownloadEstimate(history: ratingHistory) }

    func resetHistory() {
        guard let app else { return }
        historyStore.reset(trackID: app.trackId, country: country)
        ratingHistory = []
    }

    // MARK: Download calibration

    var calibrated: CalibratedEstimate? {
        guard let app else { return nil }
        return EstimateEngine.estimate(
            ratingsPerDay: estimate?.ratingsPerDay,
            rank: bestRank,
            country: country,
            genreID: app.primaryGenreId,
            store: calibrationStore
        )
    }

    var calibrationAnchors: [CalibrationAnchor] { calibrationStore.anchors }

    var hasCalibrationData: Bool {
        !calibrationStore.anchors.isEmpty || !calibrationStore.curves.isEmpty
    }

    /// The fitted rank curve for this app's chart, if one has been sampled.
    var currentCurve: RankCurve? {
        guard let app else { return nil }
        return calibrationStore.curve(country: country, genreID: app.primaryGenreId)
    }

    /// Turns the app on screen into an anchor, given its real download figure.
    func anchorCurrentApp(dailyDownloads: Double) {
        guard let app, let estimate, dailyDownloads > 0 else { return }
        calibrationStore.addAnchor(
            CalibrationAnchor(
                appName: app.trackName,
                trackID: app.trackId,
                country: country,
                genreID: app.primaryGenreId,
                dailyDownloads: dailyDownloads,
                ratingsPerDay: estimate.ratingsPerDay
            )
        )
    }

    func removeCalibrationAnchor(_ anchor: CalibrationAnchor) {
        calibrationStore.removeAnchor(anchor)
    }

    func clearCalibration() {
        calibrationStore.clearAll()
    }

    func runCalibration() async {
        guard let app, !isCalibrating else { return }
        isCalibrating = true
        calibrationProgress = 0
        calibrationStatus = nil

        let outcome = await ChartCalibrator.run(
            country: country,
            genreID: app.primaryGenreId,
            store: calibrationStore
        ) { done, total in
            Task { @MainActor in
                self.calibrationProgress = Double(done) / Double(max(total, 1))
            }
        }

        calibrationStatus = switch outcome {
        case let .baselineTaken(sampled):
            "Baseline taken across \(sampled) charting apps. Run this again tomorrow to fit the curve."
        case let .fitted(curve):
            "Curve fitted from \(curve.sampleCount) apps. Exponent \(String(format: "%.2f", curve.exponent)), R² \(String(format: "%.2f", curve.rSquared))."
        case let .tooSoon(hours):
            "Too soon — the deltas need about \(Int(hours.rounded())) more hours to mean anything."
        case let .notEnoughMovement(usable):
            "Only \(usable) apps gained ratings since the baseline. Try a busier chart or wait longer."
        case .chartUnavailable:
            "That chart feed returned nothing, so there was nothing to sample."
        }
        isCalibrating = false
    }

    // MARK: Earnings

    /// Monthly earnings in this storefront, from grossing rank and/or downloads × revenue per download.
    var earningsEstimate: RevenueEstimate? {
        guard let app else { return nil }
        return RevenueEngine.estimate(
            app: app,
            country: country,
            placements: placements,
            downloads: calibrated,
            store: revenueStore,
            currency: currency
        )
    }

    var revenueAnchors: [RevenueAnchor] { revenueStore.anchors }

    /// What an earnings anchor saved now would record, in words.
    var grossingRanksSummary: String {
        let ranked = placements.filter { $0.chart == .grossing && $0.rank != nil }
        guard !ranked.isEmpty else { return "not ranked on Top Grossing" }
        return ranked.map { "#\($0.rank!) \($0.scopeName)" }.joined(separator: ", ")
    }

    func loadExchangeRatesIfNeeded() async {
        await currency.refreshIfNeeded()
    }

    /// Saves the app on screen as an earnings anchor. Chart ranks are read from the current
    /// placements, so check charts first or the anchor can only feed the per-download method.
    func anchorEarnings(monthlyProceedsUSD: Double, monthlyDownloads: Double?) {
        guard let app, monthlyProceedsUSD > 0 else { return }
        let overall = placements.first { $0.chart == .grossing && $0.genreID == nil }?.rank
        let category = placements.first { $0.chart == .grossing && $0.genreID != nil }?.rank
        revenueStore.addAnchor(
            RevenueAnchor(
                appName: app.trackName,
                trackID: app.trackId,
                country: country,
                genreID: app.primaryGenreId,
                monthlyProceedsUSD: monthlyProceedsUSD,
                monthlyDownloads: monthlyDownloads,
                overallGrossingRank: overall,
                categoryGrossingRank: category
            )
        )
    }

    func removeRevenueAnchor(_ anchor: RevenueAnchor) {
        revenueStore.removeAnchor(anchor)
    }
}

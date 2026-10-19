import MapKit
import SwiftUI

// MARK: - State

/// One country opened from the map or the list.
struct StorefrontInspection: Identifiable {
    let storefront: Storefront
    var app: AppStoreApp?
    var failure: String?
    var isLoading = true
    var id: String { storefront.code }
}

@Observable
@MainActor
final class AppLookupModel {

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

    var reviewSort: ReviewSort = .mostRecent
    private(set) var reviews: [AppReview] = []
    private(set) var reviewPage = 0
    private(set) var isLoadingReviews = false
    private(set) var reviewNotice: String?

    /// Once the user has asked for reviews the section stays open, even if a sort comes back
    /// empty — otherwise the sort buttons vanish and there's no way back to a tab that works.
    private(set) var reviewsStarted = false
    private(set) var reviewsOrderedLocally = false

    var digest: ReviewDigest { ReviewDigest(reviews: reviews) }

    var canLoadMoreReviews: Bool {
        reviewPage > 0 && reviewPage < ReviewService.maxPage && reviewNotice == nil
    }

    func loadReviews(startingOver: Bool = false) async {
        guard let app, !isLoadingReviews else { return }

        reviewsStarted = true

        if startingOver {
            reviews = []
            reviewPage = 0
            reviewNotice = nil
            reviewsOrderedLocally = false
        }

        isLoadingReviews = true
        let nextPage = reviewPage + 1
        let sort = reviewSort

        do {
            let page = try await fetchReviewPage(trackID: app.trackId, page: nextPage, sort: sort)

            // Bail out if the user switched tabs while this was in flight.
            guard reviewSort == sort else {
                isLoadingReviews = false
                return
            }

            // The feed repeats entries near its tail, so dedupe rather than append blindly.
            let existing = Set(reviews.map(\.id))
            reviews += page.filter { !existing.contains($0.id) }
            if reviewsOrderedLocally { reviews = sort.ordered(reviews) }
            reviewPage = nextPage

            if nextPage == ReviewService.maxPage {
                reviewNotice = "Apple's feed stops at 500 reviews per storefront."
            }
        } catch {
            guard reviewSort == sort else {
                isLoadingReviews = false
                return
            }
            reviewNotice = reviews.isEmpty
                ? error.localizedDescription
                : "That's everything this storefront's feed will return."
        }
        isLoadingReviews = false
    }

    /// Falls back to the recent feed, ordered locally, when a storefront won't serve this sort.
    private func fetchReviewPage(trackID: Int, page: Int, sort: ReviewSort) async throws -> [AppReview] {
        if !reviewsOrderedLocally {
            do {
                return try await ReviewService.reviews(
                    trackID: trackID, country: country, page: page, sort: sort
                )
            } catch where sort != .mostRecent {
                reviewsOrderedLocally = true
            }
        }

        let recent = try await ReviewService.reviews(
            trackID: trackID, country: country, page: page, sort: .mostRecent
        )
        return sort.ordered(recent)
    }

    /// Re-tapping the active tab retries it, which matters when the first attempt failed.
    func changeSort(to sort: ReviewSort) async {
        reviewSort = sort
        await loadReviews(startingOver: true)
    }

    var estimate: DownloadEstimate? { DownloadEstimate(history: ratingHistory) }

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
        reviews = []
        reviewPage = 0
        reviewNotice = nil
        reviewsStarted = false
        reviewsOrderedLocally = false

        do {
            let found = try await AppStoreLookupService.lookup(query, country: country)
            app = found

            // Every lookup doubles as a datapoint. Enough of them and the deltas mean something.
            if let count = found.userRatingCount, let average = found.averageUserRating {
                RatingHistoryStore.shared.record(
                    trackID: found.trackId,
                    country: country,
                    count: count,
                    average: average
                )
            }
            ratingHistory = RatingHistoryStore.shared.history(trackID: found.trackId, country: country)
        } catch {
            app = nil
            errorMessage = error.localizedDescription
            if let lookupError = error as? LookupError, case .notFound = lookupError {
                lastLookupWasNotFound = true
            }
        }
        isLoading = false
    }

    func checkCharts() async {
        guard let app, !isCheckingCharts else { return }
        isCheckingCharts = true
        placements = await ChartRankService.placements(for: app, country: country)
        isCheckingCharts = false
    }

    var showingCalibration = false
    private(set) var isCalibrating = false
    private(set) var calibrationProgress = 0.0
    private(set) var calibrationStatus: String?

    var calibration: DownloadModel { DownloadModel.shared }

    /// The best available chart position: overall Top Free, falling back to the category chart.
    var bestRank: Int? {
        placements.first { $0.genreID == nil && $0.chart == .free }?.rank
            ?? placements.first { $0.chart == .free }?.rank
    }

    var calibrated: CalibratedEstimate? {
        guard let app else { return nil }
        return EstimateEngine.estimate(
            ratingsPerDay: estimate?.ratingsPerDay,
            rank: bestRank,
            country: country,
            genreID: app.primaryGenreId,
            model: DownloadModel.shared
        )
    }

    /// Monthly earnings in this storefront, from grossing rank and/or downloads × revenue per download.
    var earningsEstimate: RevenueEstimate? {
        guard let app else { return nil }
        return RevenueEngine.estimate(
            app: app,
            country: country,
            placements: placements,
            downloads: calibrated,
            model: RevenueModel.shared
        )
    }

    /// Saves the app on screen as an earnings anchor. Chart ranks are read from the current
    /// placements, so check charts first or the anchor can only feed the per-download method.
    func anchorEarnings(monthlyProceedsUSD: Double, monthlyDownloads: Double?) {
        guard let app, monthlyProceedsUSD > 0 else { return }
        let overall = placements.first { $0.chart == .grossing && $0.genreID == nil }?.rank
        let category = placements.first { $0.chart == .grossing && $0.genreID != nil }?.rank
        RevenueModel.shared.addAnchor(
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

    /// Turns the app on screen into an anchor, given its real download figure.
    func anchorCurrentApp(dailyDownloads: Double) {
        guard let app, let estimate, dailyDownloads > 0 else { return }
        DownloadModel.shared.addAnchor(
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

    func runCalibration() async {
        guard let app, !isCalibrating else { return }
        isCalibrating = true
        calibrationProgress = 0
        calibrationStatus = nil

        let outcome = await ChartCalibrator.run(
            country: country,
            genreID: app.primaryGenreId,
            model: DownloadModel.shared
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

    func resetHistory() {
        guard let app else { return }
        RatingHistoryStore.shared.reset(trackID: app.trackId, country: country)
        ratingHistory = []
    }

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

    func clear() {
        query = ""
        app = nil
        errorMessage = nil
        lastLookupWasNotFound = false
        world = nil
        inspection = nil
    }
}

// MARK: - Map helpers

extension Storefront {
    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

extension StorefrontRating {
    /// Green where people like it, red where they don't, grey where it isn't sold.
    var tint: Color {
        guard let average else {
            return isAvailable ? .gray : .secondary
        }
        if average >= 4.5 { return .green }
        if average >= 4.0 { return .mint }
        if average >= 3.0 { return .orange }
        return .red
    }
}

// MARK: - Root

enum RootTab: Hashable {
    case lookup, availability, earnings
}

struct AppLookupView: View {

    @State private var model = AppLookupModel()
    @State private var availability = AvailabilityModel()
    @State private var selection: RootTab = .lookup

    var body: some View {
        TabView(selection: $selection) {
            Tab("Lookup", systemImage: "magnifyingglass", value: RootTab.lookup) {
                LookupScreen(model: model, onFindWhereLive: findWhereLive)
            }
            Tab("Availability", systemImage: "globe", value: RootTab.availability) {
                AvailabilityScreen(model: availability, onOpenReport: openReport)
            }
            Tab("Earnings", systemImage: "chart.bar.xaxis", value: RootTab.earnings) {
                EarningsScreen(earnings: EarningsModel.shared, onOpenReport: openReport)
            }
        }
    }

    /// From a failed lookup: carry the query over and sweep every storefront.
    private func findWhereLive() {
        availability.query = model.query
        selection = .availability
        availability.start()
    }

    /// From the other tabs: open the full report for one app in one storefront.
    private func openReport(query: String, country: String) {
        model.query = query
        model.country = country
        selection = .lookup
        Task { await model.submit() }
    }
}

private struct LookupScreen: View {

    @Bindable var model: AppLookupModel
    let onFindWhereLive: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SearchBar(model: model)

                    if let message = model.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            MessageBox(text: message, symbol: "exclamationmark.triangle")

                            if model.lastLookupWasNotFound {
                                Button(action: onFindWhereLive) {
                                    Label("Check every storefront for this app", systemImage: "globe")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let app = model.app {
                        AppReport(app: app, model: model)
                            .transition(.opacity)
                    } else {
                        StartHint()
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("App Store Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: model.app?.trackId)
            .sheet(isPresented: $model.showingCalibration) {
                CalibrationSheet(model: model)
            }
            .sheet(item: $model.inspection) { inspection in
                CountrySheet(storefront: inspection.storefront, model: model)
            }
        }
    }
}

// MARK: - Search

private struct SearchBar: View {

    @Bindable var model: AppLookupModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("App ID, bundle ID, or App Store link", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { Task { await model.submit() } }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif

                if !model.query.isEmpty {
                    Button {
                        model.clear()
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.card, in: .rect(cornerRadius: 12))

            HStack(spacing: 12) {
                Picker("Storefront", selection: $model.country) {
                    ForEach(Storefront.everywhere) { store in
                        Text("\(store.flag)  \(store.name)").tag(store.code)
                    }
                }
                .labelsHidden()
                .onChange(of: model.country) {
                    guard model.app != nil else { return }
                    Task { await model.submit() }
                }

                Spacer()

                Button("Look up") {
                    focused = false
                    Task { await model.submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSubmit)
            }
        }
    }
}

private struct StartHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste anything that identifies an app.")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ExampleRow(label: "Numeric ID", value: "904237743")
                ExampleRow(label: "Bundle ID", value: "com.culturedcode.ThingsiPhone")
                ExampleRow(label: "Store link", value: "apps.apple.com/us/app/things-3/id904237743")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct ExampleRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Report

private struct AppReport: View {

    let app: AppStoreApp
    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            AppHeader(app: app)
            RatingsPanel(app: app, model: model)
            WorldSection(model: model)

            if !app.allScreenshots.isEmpty {
                Screenshots(urls: app.allScreenshots)
            }

            if let notes = app.releaseNotes, !notes.isEmpty {
                ReportSection("What's new in \(app.version ?? "this version")") {
                    ExpandableText(notes)
                }
            }

            if let description = app.appDescription, !description.isEmpty {
                ReportSection("Description") {
                    ExpandableText(description)
                }
            }

            ReportSection("Details") {
                DetailGrid(app: app)
            }

            DownloadsNote(model: model)
            EarningsSection(model: model)
            ReviewsSection(model: model)

            if let link = app.trackViewUrl, let url = URL(string: link) {
                Link(destination: url) {
                    Label("Open in the App Store", systemImage: "arrow.up.right.square")
                }
                .font(.subheadline)
            }
        }
    }
}

struct AppHeader: View {

    let app: AppStoreApp

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: app.artworkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 20).fill(.quaternary)
            }
            .frame(width: 96, height: 96)
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.separator, lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(app.trackName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)

                Text(app.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Tag(app.priceLabel)
                    if let genre = app.primaryGenreName { Tag(genre) }
                    if let age = app.contentAdvisoryRating { Tag(age) }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Ratings

private struct RatingsPanel: View {

    let app: AppStoreApp
    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                RatingBlock(
                    title: Storefront.named(model.country).name,
                    average: app.averageUserRating,
                    count: app.userRatingCount
                )
                Divider().frame(height: 62)
                RatingBlock(
                    title: "Version \(app.version ?? "current")",
                    average: app.averageUserRatingForCurrentVersion,
                    count: app.userRatingCountForCurrentVersion
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

struct RatingBlock: View {

    let title: String
    let average: Double?
    let count: Int?

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(average.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .monospacedDigit()

            Stars(value: average ?? 0)

            Text(count.map { "\($0.formatted()) ratings" } ?? "Not yet rated")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct Stars: View {

    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5) { index in
                Image(systemName: symbol(at: index))
                    .font(.caption2)
            }
        }
        .foregroundStyle(.orange)
    }

    private func symbol(at index: Int) -> String {
        let filled = value - Double(index)
        if filled >= 0.75 { return "star.fill" }
        if filled >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - World

private struct WorldSection: View {

    let model: AppLookupModel
    @State private var showingList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Ratings around the world")
                Spacer()
                if model.world != nil {
                    Picker("View", selection: $showingList) {
                        Image(systemName: "map").tag(false)
                        Image(systemName: "list.bullet").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                }
            }

            if let world = model.world {
                WorldTotals(world: world)

                if showingList {
                    WorldList(world: world, model: model)
                } else {
                    WorldMap(world: world, model: model)
                    MapLegend()
                }

                Text("Tap a country to load that storefront's listing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.isScanningWorld {
                VStack(spacing: 10) {
                    ProgressView(value: Double(model.scanned), total: Double(model.scanTotal))
                    Text("Checked \(model.scanned) of \(model.scanTotal) storefronts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple stores ratings separately in every country. Sweep all \(Storefront.all.count) storefronts to see where this app is sold and how it scores in each.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await model.scanWorld() }
                    } label: {
                        Label("Scan storefronts", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct WorldTotals: View {

    let world: WorldRatingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                Totals(
                    value: world.weightedAverage.map { String(format: "%.2f", $0) } ?? "—",
                    label: "Pooled average"
                )
                Divider().frame(height: 38)
                Totals(value: world.totalRatings.formatted(), label: "Ratings counted")
                Divider().frame(height: 38)
                Totals(value: "\(world.rated.count)", label: "Stores rated")
                Divider().frame(height: 38)
                Totals(value: "\(world.unavailable.count)", label: "Not on sale")
            }

            if let best = world.best, let worst = world.worst, best.id != worst.id {
                HStack(spacing: 6) {
                    Text("Strongest \(best.storefront.flag) \(best.storefront.name)")
                    Text("·").foregroundStyle(.tertiary)
                    Text("Weakest \(worst.storefront.flag) \(worst.storefront.name)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private struct Totals: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WorldMap: View {

    let world: WorldRatingSummary
    let model: AppLookupModel

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25, longitude: 15),
            span: MKCoordinateSpan(latitudeDelta: 130, longitudeDelta: 170)
        )
    )

    private var heaviest: Int { max(world.rated.first?.count ?? 1, 1) }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(world.results) { rating in
                Annotation(rating.storefront.name, coordinate: rating.storefront.coordinate) {
                    Pin(rating: rating, scale: scale(for: rating)) {
                        Task { await model.inspect(rating.storefront) }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Bubble area tracks rating volume, on a log scale so small stores stay visible.
    private func scale(for rating: StorefrontRating) -> Double {
        guard rating.count > 0 else { return 0.55 }
        let normalized = log10(Double(rating.count) + 1) / log10(Double(heaviest) + 1)
        return 0.6 + normalized * 0.75
    }

    private struct Pin: View {
        let rating: StorefrontRating
        let scale: Double
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Group {
                    if let average = rating.average {
                        Text(String(format: "%.1f", average))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(rating.tint.gradient, in: .circle)
                    } else if rating.isAvailable {
                        Circle()
                            .fill(.gray)
                            .frame(width: 11, height: 11)
                    } else {
                        Circle()
                            .strokeBorder(.secondary.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                }
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
                }
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .scaleEffect(scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }

        private var label: String {
            switch rating.status {
            case let .rated(average, count):
                "\(rating.storefront.name): \(String(format: "%.1f", average)) stars from \(count) ratings"
            case .listedButUnrated:
                "\(rating.storefront.name): listed, no ratings yet"
            case .notAvailable:
                "\(rating.storefront.name): not on sale"
            }
        }
    }
}

private struct MapLegend: View {
    private let stops: [(Color, String)] = [
        (.green, "4.5+"), (.mint, "4.0"), (.orange, "3.0"), (.red, "under 3"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(stops, id: \.1) { color, label in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label)
                }
            }
            HStack(spacing: 4) {
                Circle().strokeBorder(.secondary, lineWidth: 1.2).frame(width: 8, height: 8)
                Text("not sold")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct WorldList: View {

    let world: WorldRatingSummary
    let model: AppLookupModel

    private var maxCount: Int { max(world.rated.first?.count ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(world.rated.enumerated()), id: \.element.id) { index, rating in
                if index > 0 { Divider() }
                Button {
                    Task { await model.inspect(rating.storefront) }
                } label: {
                    HStack(spacing: 10) {
                        Text(rating.storefront.flag)
                        Text(rating.storefront.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Capsule()
                            .fill(rating.tint.opacity(0.35))
                            .frame(width: 56 * fraction(rating.count), height: 6)
                            .frame(width: 56, alignment: .leading)

                        Text(rating.count.formatted())
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)

                        Text(String(format: "%.1f", rating.average ?? 0))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 26, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            if !world.unavailable.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Not on sale in \(world.unavailable.map(\.storefront.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fraction(_ count: Int) -> Double {
        max(0.08, Double(count) / Double(maxCount))
    }
}

// MARK: - Country detail

private struct CountrySheet: View {

    let storefront: Storefront
    let model: AppLookupModel
    @Environment(\.dismiss) private var dismiss

    /// Read through the model so the sheet keeps updating after it's presented —
    /// `.sheet(item:)` hands you a snapshot, not a live value.
    private var inspection: StorefrontInspection {
        model.inspection ?? StorefrontInspection(storefront: storefront)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if inspection.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let failure = inspection.failure {
                        MessageBox(text: failure, symbol: "xmark.circle")
                    } else if let app = inspection.app {
                        AppHeader(app: app)

                        HStack(alignment: .top, spacing: 0) {
                            RatingBlock(
                                title: "All versions",
                                average: app.averageUserRating,
                                count: app.userRatingCount
                            )
                            Divider().frame(height: 62)
                            RatingBlock(
                                title: "Version \(app.version ?? "current")",
                                average: app.averageUserRatingForCurrentVersion,
                                count: app.userRatingCountForCurrentVersion
                            )
                        }
                        .padding(.vertical, 16)
                        .background(Color.card, in: .rect(cornerRadius: 14))

                        ReportSection("Local listing") {
                            DetailGrid(app: app)
                        }

                        if let notes = app.releaseNotes, !notes.isEmpty {
                            ReportSection("What's new here") { ExpandableText(notes) }
                        }

                        Button {
                            Task { await model.makePrimary(storefront) }
                        } label: {
                            Label("Use this storefront", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("\(storefront.flag)  \(storefront.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Screenshots

private struct Screenshots: View {

    let urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Screenshots")

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(urls, id: \.self) { url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                                .frame(width: 150, height: 320)
                        }
                        .frame(height: 320)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }
}

// MARK: - Details

struct DetailGrid: View {

    let app: AppStoreApp

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []

        if let version = app.version { rows.append(("Version", version)) }
        if let updated = app.updatedOn {
            rows.append(("Updated", updated.formatted(date: .abbreviated, time: .omitted)))
        }
        if let released = app.releasedOn {
            rows.append(("First released", released.formatted(date: .abbreviated, time: .omitted)))
        }
        if let size = app.fileSize {
            rows.append(("Size", size.formatted(.byteCount(style: .file))))
        }
        if let minimum = app.minimumOsVersion { rows.append(("Requires", "iOS \(minimum) or later")) }
        rows.append(("Price", app.priceLabel))
        if let genres = app.genres, !genres.isEmpty {
            rows.append(("Categories", genres.joined(separator: ", ")))
        }
        if let seller = app.sellerName { rows.append(("Seller", seller)) }
        if let bundle = app.bundleId { rows.append(("Bundle ID", bundle)) }
        rows.append(("Track ID", String(app.trackId)))

        let languages = app.languageNames
        if !languages.isEmpty {
            let shown = languages.prefix(6).joined(separator: ", ")
            let extra = languages.count > 6 ? " +\(languages.count - 6) more" : ""
            rows.append(("Languages", shown + extra))
        }
        let devices = app.deviceFamilies
        if !devices.isEmpty { rows.append(("Devices", devices.joined(separator: ", "))) }

        if let advisories = app.advisories, !advisories.isEmpty {
            rows.append(("Advisories", advisories.joined(separator: ", ")))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 116) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)
                    Text(row.1)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Downloads

private struct DownloadsNote: View {

    let model: AppLookupModel

    private let estimators: [(String, String)] = [
        ("Appfigures", "https://docs.appfigures.com/api/reference/v2/estimates"),
        ("Sensor Tower", "https://sensortower.com"),
        ("AppTweak", "https://www.apptweak.com"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Download signals")

            CalibratedBlock(model: model)

            ChartRanks(model: model)
            Divider()
            Velocity(model: model)
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("For modelled estimates, these sell them through an API:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(estimators, id: \.0) { name, link in
                        if let url = URL(string: link) {
                            Link(name, destination: url).font(.footnote)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct ChartRanks: View {

    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chart position")
                .font(.subheadline.weight(.medium))

            if model.placements.isEmpty {
                Button {
                    Task { await model.checkCharts() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isCheckingCharts {
                            ProgressView().controlSize(.small)
                            Text("Reading charts…")
                        } else {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("Check top 200 charts")
                        }
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(model.isCheckingCharts)
            } else {
                ForEach(groupedScopes, id: \.self) { scope in
                    HStack(spacing: 8) {
                        Text(scope)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)

                        ForEach(model.placements.filter { $0.scopeName == scope }) { placement in
                            VStack(spacing: 2) {
                                Text(placement.summary)
                                    .font(.caption.weight(placement.rank == nil ? .regular : .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(placement.rank == nil ? .secondary : .primary)
                                Text(placement.chart.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var groupedScopes: [String] {
        var seen: [String] = []
        for placement in model.placements where !seen.contains(placement.scopeName) {
            seen.append(placement.scopeName)
        }
        return seen
    }
}

private struct Velocity: View {

    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ratings velocity")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if model.ratingHistory.count > 1 {
                    Button("Reset") { model.resetHistory() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
            }

            if let estimate = model.estimate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(estimate.ratingsPerDay, format: .number.precision(.fractionLength(1))) new ratings a day")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()

                    Text("≈ \(estimate.lowDailyInstalls.formatted())–\(estimate.highDailyInstalls.formatted()) installs a day")
                        .font(.subheadline)
                        .monospacedDigit()

                    Text("Assuming 0.5–2% of installs leave a rating. Measured over \(estimate.spanDays, format: .number.precision(.fractionLength(1))) days from \(estimate.sampleCount) readings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !estimate.isReliable {
                        Label("Under a week of data — day-of-week swings dominate this number.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(model.ratingHistory.isEmpty
                     ? "No readings yet."
                     : "Baseline saved. Look this app up again tomorrow and the daily rating delta becomes an install range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Reviews

private struct ReviewsSection: View {

    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Reviews")
                Spacer()
                if !model.reviews.isEmpty {
                    Text("\(model.reviews.count) loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !model.reviewsStarted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review text comes from a separate feed, 50 at a time, capped at 500 per storefront.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await model.loadReviews() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isLoadingReviews {
                                ProgressView().controlSize(.small)
                                Text("Loading…")
                            } else {
                                Image(systemName: "text.bubble")
                                Text("Load reviews")
                            }
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoadingReviews)
                }
            } else {
                SortBar(model: model)

                if model.reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.isLoadingReviews {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            Text(model.reviewNotice ?? "Nothing came back for this sort.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Try again") {
                                Task { await model.loadReviews(startingOver: true) }
                            }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    if model.reviewsOrderedLocally {
                        Label("This storefront only serves the recent feed, so these are ordered on device.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ReviewSpread(digest: model.digest)

                    ForEach(model.reviews) { review in
                        ReviewCard(review: review)
                    }

                    if let notice = model.reviewNotice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if model.canLoadMoreReviews {
                        Button {
                            Task { await model.loadReviews() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isLoadingReviews {
                                    ProgressView().controlSize(.small)
                                }
                                Text(model.isLoadingReviews ? "Loading…" : "Load 50 more")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingReviews)
                    }
                }
            }
        }
    }
}

private struct SortBar: View {

    let model: AppLookupModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReviewSort.allCases) { sort in
                    let isActive = model.reviewSort == sort
                    Button {
                        Task { await model.changeSort(to: sort) }
                    } label: {
                        // Padding and background belong inside the label, or only the glyph is tappable.
                        Text(sort.label)
                            .font(.caption.weight(isActive ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isActive ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary),
                                in: .capsule
                            )
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .disabled(model.isLoadingReviews)
    }
}

/// Apple's own star breakdown isn't in any public endpoint, so this is the spread of the
/// reviews we actually pulled — written reviews skew harder than tapped stars.
private struct ReviewSpread: View {

    let digest: ReviewDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 5, through: 1, by: -1)), id: \.self) { stars in
                HStack(spacing: 8) {
                    Text("\(stars)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(stars >= 4 ? Color.green : stars == 3 ? .orange : .red)
                            .opacity(0.65)
                            .frame(width: max(2, proxy.size.width * digest.share(of: stars)))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 7)

                    Text("\(digest.counts[stars] ?? 0)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            Text("Spread of loaded reviews, not Apple's full breakdown.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }
}

private struct ReviewCard: View {

    let review: AppReview
    @State private var expanded = false

    private var isLong: Bool { review.body.count > 280 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Stars(value: Double(review.rating))
                Text(review.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(review.body)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if isLong {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            HStack(spacing: 6) {
                Text(review.author)
                if let version = review.version {
                    Text("·").foregroundStyle(.tertiary)
                    Text("v\(version)")
                }
                if let updated = review.updated {
                    Text("·").foregroundStyle(.tertiary)
                    Text(updated.formatted(.relative(presentation: .named)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }
}

private struct CalibratedBlock: View {

    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let estimate = model.calibrated, estimate.isCalibrated, estimate.daily > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(estimate.daily.rounded()).formatted()) installs a day")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .monospacedDigit()

                    Text("\(Int(estimate.low.rounded()).formatted())–\(Int(estimate.high.rounded()).formatted()) range · \(Int((estimate.daily * 30).rounded()).formatted()) a month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    Image(systemName: symbol(for: estimate.source))
                    Text(estimate.source.label)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(color(for: estimate.source))

                Text(estimate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Apple never publishes install counts. Calibrate against an app you own and the signals below turn into numbers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let estimate = model.calibrated, estimate.daily > 0 {
                    Text("Uncalibrated: \(Int(estimate.low.rounded()).formatted())–\(Int(estimate.high.rounded()).formatted()) a day")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }

            Button {
                model.showingCalibration = true
            } label: {
                Label(
                    model.calibration.anchors.isEmpty ? "Set up calibration" : "Calibration",
                    systemImage: "slider.horizontal.3"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func symbol(for source: CalibratedEstimate.Source) -> String {
        switch source {
        case .agreement: "checkmark.seal"
        case .conflict: "exclamationmark.triangle"
        case .measuredVelocity: "waveform.path.ecg"
        case .rankCurve: "chart.line.uptrend.xyaxis"
        case .uncalibrated: "questionmark.circle"
        }
    }

    private func color(for source: CalibratedEstimate.Source) -> Color {
        switch source {
        case .agreement: .green
        case .conflict: .orange
        default: .secondary
        }
    }
}

// MARK: - Calibration

private struct CalibrationSheet: View {

    let model: AppLookupModel
    @Environment(\.dismiss) private var dismiss
    @State private var downloadsField = ""

    private var calibration: DownloadModel { model.calibration }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Every download-estimate product guesses what share of installs leave a rating. You don't have to guess — App Store Connect tells you your real numbers. Pair one of your own apps' actual daily downloads with the ratings velocity measured here, and that ratio becomes a measured constant for your category and storefront.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    AnchorForm(model: model, downloadsField: $downloadsField)

                    if !calibration.anchors.isEmpty {
                        ReportSection("Anchors") {
                            VStack(spacing: 0) {
                                ForEach(Array(calibration.anchors.enumerated()), id: \.element.id) { index, anchor in
                                    if index > 0 { Divider() }
                                    AnchorRow(anchor: anchor, calibration: calibration)
                                }
                            }
                            .background(Color.card, in: .rect(cornerRadius: 12))
                        }
                    }

                    CurveForm(model: model)

                    if !calibration.anchors.isEmpty || !calibration.curves.isEmpty {
                        Button("Clear all calibration data", role: .destructive) {
                            calibration.clearAll()
                        }
                        .font(.footnote)
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("Calibration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AnchorForm: View {

    let model: AppLookupModel
    @Binding var downloadsField: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Anchor this app")

            if let app = model.app, let estimate = model.estimate {
                Text("\(app.trackName) is gaining \(estimate.ratingsPerDay, format: .number.precision(.fractionLength(1))) ratings a day in \(Storefront.named(model.country).name).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TextField("Actual downloads per day", text: $downloadsField)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.card, in: .rect(cornerRadius: 10))

                    Button("Add") {
                        if let value = Double(downloadsField.filter(\.isNumber)) {
                            model.anchorCurrentApp(dailyDownloads: value)
                            downloadsField = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(downloadsField.filter(\.isNumber)) == nil)
                }

                Text("Take the figure from App Store Connect → Sales and Trends, averaged over the same days the velocity covers.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Look up an app you own and give it two days of readings first — an anchor needs a measured velocity to pair with your real numbers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AnchorRow: View {

    let anchor: CalibrationAnchor
    let calibration: DownloadModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(anchor.appName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(Storefront.named(anchor.country).flag) \(Int(anchor.dailyDownloads).formatted())/day · \(anchor.ratingsPerDay, format: .number.precision(.fractionLength(1))) ratings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let rate = anchor.ratingRate {
                Text("\(rate * 100, format: .number.precision(.fractionLength(2)))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }

            Button {
                calibration.removeAnchor(anchor)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

private struct CurveForm: View {

    let model: AppLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Rank curve")

            Text("Samples apps across the whole chart and watches how fast each gains ratings. Two passes a day apart give the curve's shape, which lets an app you've seen only once be estimated from its rank.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let app = model.app,
               let curve = model.calibration.curve(country: model.country, genreID: app.primaryGenreId) {
                HStack(spacing: 14) {
                    Stat(value: String(format: "%.2f", curve.exponent), label: "Exponent")
                    Stat(value: String(format: "%.2f", curve.rSquared), label: "R²")
                    Stat(value: "\(curve.sampleCount)", label: "Apps")
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.card, in: .rect(cornerRadius: 12))

                if !curve.isTrustworthy {
                    Label("Fit is loose — the rank estimate stays out until it tightens.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if model.isCalibrating {
                ProgressView(value: model.calibrationProgress)
            }

            Button {
                Task { await model.runCalibration() }
            } label: {
                Label(model.isCalibrating ? "Sampling…" : "Sample charts", systemImage: "chart.dots.scatter")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(model.isCalibrating || model.app == nil)

            if let status = model.calibrationStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct Stat: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Small pieces

struct ReportSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            content
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExpandableText: View {

    let text: String
    @State private var expanded = false

    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button(expanded ? "Show less" : "Show more") {
                withAnimation(.snappy) { expanded.toggle() }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
    }
}

struct MessageBox: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Colors

extension Color {
    #if os(iOS)
    static let surface = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    #else
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #endif
}

#Preview {
    AppLookupView()
}

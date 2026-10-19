import Foundation

// MARK: - Model

/// One app as returned by Apple's public iTunes Lookup endpoint.
/// Only the fields worth showing are decoded; the raw payload has ~50 more.
struct AppStoreApp: Decodable, Identifiable, Sendable {

    var id: Int { trackId }

    // Identity
    let trackId: Int
    let trackName: String
    let bundleId: String?
    let artistName: String
    let artistId: Int?
    let sellerName: String?
    let sellerUrl: String?
    let trackViewUrl: String?

    // Artwork
    let artworkUrl100: String?
    let artworkUrl512: String?
    let screenshotUrls: [String]?
    let ipadScreenshotUrls: [String]?

    // Ratings
    let averageUserRating: Double?
    let userRatingCount: Int?
    let averageUserRatingForCurrentVersion: Double?
    let userRatingCountForCurrentVersion: Int?

    // Price
    let price: Double?
    let formattedPrice: String?
    let currency: String?

    // Version
    let version: String?
    let releaseNotes: String?
    let releaseDate: String?
    let currentVersionReleaseDate: String?

    // Technical
    let fileSizeBytes: String?
    let minimumOsVersion: String?
    let contentAdvisoryRating: String?
    let advisories: [String]?
    let primaryGenreName: String?
    let primaryGenreId: Int?
    let genres: [String]?
    let languageCodesISO2A: [String]?
    let supportedDevices: [String]?
    let isGameCenterEnabled: Bool?

    let appDescription: String?

    enum CodingKeys: String, CodingKey {
        case trackId, trackName, bundleId, artistName, artistId, sellerName, sellerUrl, trackViewUrl
        case artworkUrl100, artworkUrl512, screenshotUrls, ipadScreenshotUrls
        case averageUserRating, userRatingCount
        case averageUserRatingForCurrentVersion, userRatingCountForCurrentVersion
        case price, formattedPrice, currency
        case version, releaseNotes, releaseDate, currentVersionReleaseDate
        case fileSizeBytes, minimumOsVersion, contentAdvisoryRating, advisories
        case primaryGenreName, primaryGenreId, genres, languageCodesISO2A, supportedDevices, isGameCenterEnabled
        case appDescription = "description"
    }
}

// MARK: - Derived values

extension AppStoreApp {

    var artworkURL: URL? {
        // artworkUrl512 is the largest Apple hands back; bump it to 1024 for retina.
        let raw = artworkUrl512 ?? artworkUrl100
        guard let raw else { return nil }
        return URL(string: raw.replacingOccurrences(of: "512x512", with: "1024x1024"))
    }

    var allScreenshots: [URL] {
        ((screenshotUrls ?? []) + (ipadScreenshotUrls ?? [])).compactMap(URL.init(string:))
    }

    var releasedOn: Date? { Self.parseDate(releaseDate) }
    var updatedOn: Date? { Self.parseDate(currentVersionReleaseDate) }

    var fileSize: Measurement<UnitInformationStorage>? {
        guard let bytes = fileSizeBytes, let value = Double(bytes) else { return nil }
        return Measurement(value: value, unit: .bytes)
    }

    var priceLabel: String {
        if let formattedPrice, !formattedPrice.isEmpty { return formattedPrice }
        return (price ?? 0) == 0 ? "Free" : "—"
    }

    var languageNames: [String] {
        (languageCodesISO2A ?? []).compactMap {
            Locale.current.localizedString(forLanguageCode: $0.lowercased())
        }
        .sorted()
    }

    /// `supportedDevices` is a long list of model identifiers like "iPhoneXS-iPhoneXS" and
    /// "iPodTouchSeventhGen-iPodTouchSeventhGen". Collapse them to readable families.
    var deviceFamilies: [String] {
        let known: [(prefix: String, name: String)] = [
            ("iPodTouch", "iPod touch"),
            ("iPhone", "iPhone"),
            ("iPadMini", "iPad mini"),
            ("iPadPro", "iPad Pro"),
            ("iPadAir", "iPad Air"),
            ("iPad", "iPad"),
            ("Watch", "Apple Watch"),
            ("AppleTV", "Apple TV"),
            ("Mac", "Mac"),
            ("RealityDevice", "Apple Vision Pro"),
        ]

        var found: [String] = []
        for identifier in supportedDevices ?? [] {
            // Order matters: iPadMini must win over iPad, iPodTouch over iPhone-style matching.
            guard let match = known.first(where: { identifier.hasPrefix($0.prefix) }) else { continue }
            if !found.contains(match.name) { found.append(match.name) }
        }
        return found
    }

    private static let formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [ISO8601DateFormatter(), withFraction]
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

// MARK: - Storefronts

struct Storefront: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { code }

    var flag: String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = UnicodeScalar(127_397 + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }

    /// Roughly 36 of Apple's 175 storefronts — the ones that carry most of the volume.
    /// Coordinates are country centroids, nudged apart where neighbours would overlap on a world map.
    static let all: [Storefront] = [
        .init(code: "us", name: "United States", latitude: 39.8, longitude: -98.6),
        .init(code: "ca", name: "Canada", latitude: 56.1, longitude: -106.3),
        .init(code: "mx", name: "Mexico", latitude: 23.6, longitude: -102.6),
        .init(code: "br", name: "Brazil", latitude: -14.2, longitude: -51.9),
        .init(code: "ar", name: "Argentina", latitude: -38.4, longitude: -63.6),
        .init(code: "cl", name: "Chile", latitude: -35.7, longitude: -71.5),
        .init(code: "gb", name: "United Kingdom", latitude: 54.5, longitude: -3.4),
        .init(code: "ie", name: "Ireland", latitude: 53.1, longitude: -8.6),
        .init(code: "fr", name: "France", latitude: 46.6, longitude: 2.2),
        .init(code: "de", name: "Germany", latitude: 51.4, longitude: 10.5),
        .init(code: "nl", name: "Netherlands", latitude: 52.4, longitude: 5.3),
        .init(code: "es", name: "Spain", latitude: 40.0, longitude: -3.7),
        .init(code: "it", name: "Italy", latitude: 42.5, longitude: 12.6),
        .init(code: "ch", name: "Switzerland", latitude: 46.8, longitude: 8.2),
        .init(code: "se", name: "Sweden", latitude: 62.0, longitude: 16.6),
        .init(code: "no", name: "Norway", latitude: 62.5, longitude: 9.5),
        .init(code: "dk", name: "Denmark", latitude: 56.3, longitude: 9.5),
        .init(code: "fi", name: "Finland", latitude: 63.9, longitude: 26.7),
        .init(code: "pl", name: "Poland", latitude: 51.9, longitude: 19.1),
        .init(code: "gr", name: "Greece", latitude: 38.5, longitude: 23.0),
        .init(code: "ua", name: "Ukraine", latitude: 48.9, longitude: 31.2),
        .init(code: "ru", name: "Russia", latitude: 61.5, longitude: 90.0),
        .init(code: "tr", name: "Türkiye", latitude: 39.0, longitude: 35.2),
        .init(code: "il", name: "Israel", latitude: 31.4, longitude: 34.6),
        .init(code: "ae", name: "United Arab Emirates", latitude: 23.8, longitude: 54.3),
        .init(code: "sa", name: "Saudi Arabia", latitude: 23.9, longitude: 45.1),
        .init(code: "eg", name: "Egypt", latitude: 26.8, longitude: 30.8),
        .init(code: "za", name: "South Africa", latitude: -30.6, longitude: 22.9),
        .init(code: "ng", name: "Nigeria", latitude: 9.1, longitude: 8.7),
        .init(code: "pk", name: "Pakistan", latitude: 30.4, longitude: 69.3),
        .init(code: "in", name: "India", latitude: 21.5, longitude: 79.0),
        .init(code: "cn", name: "China mainland", latitude: 35.9, longitude: 104.2),
        .init(code: "jp", name: "Japan", latitude: 37.2, longitude: 139.3),
        .init(code: "kr", name: "South Korea", latitude: 35.9, longitude: 127.8),
        .init(code: "hk", name: "Hong Kong", latitude: 22.3, longitude: 114.2),
        .init(code: "sg", name: "Singapore", latitude: 1.35, longitude: 103.8),
        .init(code: "th", name: "Thailand", latitude: 15.9, longitude: 101.0),
        .init(code: "vn", name: "Vietnam", latitude: 14.1, longitude: 108.3),
        .init(code: "ph", name: "Philippines", latitude: 12.9, longitude: 121.8),
        .init(code: "id", name: "Indonesia", latitude: -2.5, longitude: 117.9),
        .init(code: "au", name: "Australia", latitude: -25.3, longitude: 133.8),
        .init(code: "nz", name: "New Zealand", latitude: -41.5, longitude: 173.0),
    ]

    static func named(_ code: String) -> Storefront {
        let code = code.lowercased()
        return all.first { $0.code == code }
            ?? everywhere.first { $0.code == code }
            ?? .init(code: code, name: code.uppercased(), latitude: 0, longitude: 0)
    }
}

/// Ratings live per storefront, so the same app scores differently in every country —
/// and in some it isn't on sale at all.
struct StorefrontRating: Identifiable, Sendable {

    enum Status: Sendable {
        case rated(average: Double, count: Int)
        case listedButUnrated
        case notAvailable
    }

    let storefront: Storefront
    let status: Status
    var id: String { storefront.code }

    var average: Double? {
        if case let .rated(average, _) = status { return average }
        return nil
    }

    var count: Int {
        if case let .rated(_, count) = status { return count }
        return 0
    }

    var isAvailable: Bool {
        if case .notAvailable = status { return false }
        return true
    }
}

/// Aggregate view of one app across every storefront that was checked.
struct WorldRatingSummary: Sendable {

    let results: [StorefrontRating]

    /// Sorted by rating volume, biggest market first.
    var rated: [StorefrontRating] {
        results.filter { $0.average != nil }.sorted { $0.count > $1.count }
    }

    var unavailable: [StorefrontRating] { results.filter { !$0.isAvailable } }

    var totalRatings: Int { rated.reduce(0) { $0 + $1.count } }

    /// Ratings-weighted mean, which is the number Apple would show if it pooled every store.
    var weightedAverage: Double? {
        guard totalRatings > 0 else { return nil }
        let sum = rated.reduce(0.0) { $0 + ($1.average ?? 0) * Double($1.count) }
        return sum / Double(totalRatings)
    }

    var best: StorefrontRating? { rated.filter { $0.count >= 20 }.max { lhs, rhs in (lhs.average ?? 0) < (rhs.average ?? 0) } }
    var worst: StorefrontRating? { rated.filter { $0.count >= 20 }.min { lhs, rhs in (lhs.average ?? 0) < (rhs.average ?? 0) } }

    var isEmpty: Bool { results.isEmpty }
}

// MARK: - Errors

enum LookupError: LocalizedError {
    case emptyInput
    case notFound(query: String, country: String)
    case badStatus(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter an App Store ID, bundle ID, or App Store link."
        case let .notFound(query, country):
            "No app matching “\(query)” in the \(Storefront.named(country).name) store. It may be unavailable there — try another storefront."
        case let .badStatus(code):
            "Apple returned HTTP \(code). Wait a moment and look it up again."
        case .decoding:
            "Apple's response didn't match the expected format."
        }
    }
}

// MARK: - Service

enum AppStoreLookupService {

    private static let decoder = JSONDecoder()

    private struct Envelope: Decodable {
        let resultCount: Int
        let results: [AppStoreApp]
    }

    /// Accepts a numeric track ID, a bundle ID, or a pasted App Store URL.
    static func identifier(from input: String) -> (value: String, isBundleID: Bool)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // https://apps.apple.com/us/app/things-3/id904237743
        if let match = trimmed.range(of: #"id(\d{6,})"#, options: .regularExpression) {
            return (String(trimmed[match].dropFirst(2)), false)
        }
        if trimmed.allSatisfy(\.isNumber) {
            return (trimmed, false)
        }
        if trimmed.contains(".") {
            return (trimmed, true)
        }
        return nil
    }

    static func lookup(_ input: String, country: String) async throws -> AppStoreApp {
        guard let (value, isBundleID) = identifier(from: input) else {
            throw LookupError.emptyInput
        }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: isBundleID ? "bundleId" : "id", value: value),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LookupError.badStatus(http.statusCode)
        }

        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw LookupError.decoding
        }
        guard let app = envelope.results.first else {
            throw LookupError.notFound(query: value, country: country)
        }
        return app
    }

    /// One request for many apps. The lookup endpoint takes a comma-separated ID list, so the
    /// Earnings tab can fetch names and icons for a whole portfolio in a single call.
    static func lookupMany(_ ids: [Int], country: String = "us") async -> [Int: AppStoreApp] {
        guard !ids.isEmpty else { return [:] }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
        ]

        guard
            let url = components.url,
            let (data, _) = try? await URLSession.shared.data(from: url),
            let envelope = try? decoder.decode(Envelope.self, from: data)
        else { return [:] }

        return Dictionary(envelope.results.map { ($0.trackId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Sweeps every storefront so you can see where the app sells and where it's rated well.
    ///
    /// Apple throttles the lookup endpoint at roughly 20 requests a minute per IP, so this
    /// keeps only `maxConcurrent` calls in flight and retries once before writing a store off
    /// as unavailable — otherwise a throttled request looks identical to a missing listing.
    static func ratingsAcrossStorefronts(
        for trackID: Int,
        in storefronts: [Storefront] = Storefront.all,
        maxConcurrent: Int = 4,
        onProgress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> WorldRatingSummary {

        let total = storefronts.count
        var completed = 0
        var collected: [StorefrontRating] = []

        await withTaskGroup(of: StorefrontRating.self) { group in
            var next = 0

            func addTask(for storefront: Storefront) {
                group.addTask {
                    await probe(trackID: trackID, storefront: storefront)
                }
            }

            while next < min(maxConcurrent, total) {
                addTask(for: storefronts[next])
                next += 1
            }

            for await result in group {
                collected.append(result)
                completed += 1
                onProgress(completed, total)

                if next < total {
                    addTask(for: storefronts[next])
                    next += 1
                }
            }
        }

        return WorldRatingSummary(results: collected)
    }

    private static func probe(trackID: Int, storefront: Storefront) async -> StorefrontRating {
        for attempt in 0..<3 {
            do {
                let app = try await lookup(String(trackID), country: storefront.code)
                if let average = app.averageUserRating, let count = app.userRatingCount, count > 0 {
                    return .init(storefront: storefront, status: .rated(average: average, count: count))
                }
                return .init(storefront: storefront, status: .listedButUnrated)
            } catch LookupError.notFound {
                return .init(storefront: storefront, status: .notAvailable)
            } catch {
                // Almost always throttling. Back off and try again.
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(900 * (attempt + 1)))
                }
            }
        }
        return .init(storefront: storefront, status: .notAvailable)
    }
}

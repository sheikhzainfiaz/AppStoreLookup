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


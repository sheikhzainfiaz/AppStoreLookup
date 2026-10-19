import Foundation

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


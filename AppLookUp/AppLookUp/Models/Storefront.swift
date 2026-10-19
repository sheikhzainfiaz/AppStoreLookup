import Foundation

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


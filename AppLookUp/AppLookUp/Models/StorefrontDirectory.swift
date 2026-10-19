//
//  Storefronts.swift
//  Applookup
//
//  v2: the full App Store storefront directory.
//

import Foundation

/// Apple's own grouping on the "Choose your country or region" page.
enum StoreRegion: String, CaseIterable, Identifiable, Sendable {
    case northAmerica
    case latinAmerica
    case europe
    case africaMiddleEastIndia
    case asiaPacific

    var id: String { rawValue }

    var label: String {
        switch self {
        case .northAmerica: "United States & Canada"
        case .latinAmerica: "Latin America & the Caribbean"
        case .europe: "Europe"
        case .africaMiddleEastIndia: "Africa, Middle East & India"
        case .asiaPacific: "Asia Pacific"
        }
    }
}

/// Every storefront the App Store operates — 175 of them. `Storefront.all` stays as the
/// 42-country subset with map coordinates; this list is for availability checks, where
/// completeness matters more than plotting.
enum StorefrontDirectory {

    struct Entry: Sendable {
        let code: String
        let name: String
        let region: StoreRegion
    }

    static let entries: [Entry] = [
        // northAmerica
        .init(code: "us", name: "United States", region: .northAmerica),
        .init(code: "ca", name: "Canada", region: .northAmerica),
        // latinAmerica
        .init(code: "ai", name: "Anguilla", region: .latinAmerica),
        .init(code: "ag", name: "Antigua and Barbuda", region: .latinAmerica),
        .init(code: "ar", name: "Argentina", region: .latinAmerica),
        .init(code: "bs", name: "Bahamas", region: .latinAmerica),
        .init(code: "bb", name: "Barbados", region: .latinAmerica),
        .init(code: "bz", name: "Belize", region: .latinAmerica),
        .init(code: "bm", name: "Bermuda", region: .latinAmerica),
        .init(code: "bo", name: "Bolivia", region: .latinAmerica),
        .init(code: "br", name: "Brazil", region: .latinAmerica),
        .init(code: "vg", name: "British Virgin Islands", region: .latinAmerica),
        .init(code: "ky", name: "Cayman Islands", region: .latinAmerica),
        .init(code: "cl", name: "Chile", region: .latinAmerica),
        .init(code: "co", name: "Colombia", region: .latinAmerica),
        .init(code: "cr", name: "Costa Rica", region: .latinAmerica),
        .init(code: "dm", name: "Dominica", region: .latinAmerica),
        .init(code: "do", name: "Dominican Republic", region: .latinAmerica),
        .init(code: "ec", name: "Ecuador", region: .latinAmerica),
        .init(code: "sv", name: "El Salvador", region: .latinAmerica),
        .init(code: "gd", name: "Grenada", region: .latinAmerica),
        .init(code: "gt", name: "Guatemala", region: .latinAmerica),
        .init(code: "gy", name: "Guyana", region: .latinAmerica),
        .init(code: "hn", name: "Honduras", region: .latinAmerica),
        .init(code: "jm", name: "Jamaica", region: .latinAmerica),
        .init(code: "mx", name: "Mexico", region: .latinAmerica),
        .init(code: "ms", name: "Montserrat", region: .latinAmerica),
        .init(code: "ni", name: "Nicaragua", region: .latinAmerica),
        .init(code: "pa", name: "Panama", region: .latinAmerica),
        .init(code: "py", name: "Paraguay", region: .latinAmerica),
        .init(code: "pe", name: "Peru", region: .latinAmerica),
        .init(code: "kn", name: "St. Kitts and Nevis", region: .latinAmerica),
        .init(code: "lc", name: "St. Lucia", region: .latinAmerica),
        .init(code: "vc", name: "St. Vincent and the Grenadines", region: .latinAmerica),
        .init(code: "sr", name: "Suriname", region: .latinAmerica),
        .init(code: "tt", name: "Trinidad and Tobago", region: .latinAmerica),
        .init(code: "tc", name: "Turks and Caicos Islands", region: .latinAmerica),
        .init(code: "uy", name: "Uruguay", region: .latinAmerica),
        .init(code: "ve", name: "Venezuela", region: .latinAmerica),
        // europe
        .init(code: "al", name: "Albania", region: .europe),
        .init(code: "at", name: "Austria", region: .europe),
        .init(code: "by", name: "Belarus", region: .europe),
        .init(code: "be", name: "Belgium", region: .europe),
        .init(code: "ba", name: "Bosnia and Herzegovina", region: .europe),
        .init(code: "bg", name: "Bulgaria", region: .europe),
        .init(code: "hr", name: "Croatia", region: .europe),
        .init(code: "cy", name: "Cyprus", region: .europe),
        .init(code: "cz", name: "Czechia", region: .europe),
        .init(code: "dk", name: "Denmark", region: .europe),
        .init(code: "ee", name: "Estonia", region: .europe),
        .init(code: "fi", name: "Finland", region: .europe),
        .init(code: "fr", name: "France", region: .europe),
        .init(code: "ge", name: "Georgia", region: .europe),
        .init(code: "de", name: "Germany", region: .europe),
        .init(code: "gr", name: "Greece", region: .europe),
        .init(code: "hu", name: "Hungary", region: .europe),
        .init(code: "is", name: "Iceland", region: .europe),
        .init(code: "ie", name: "Ireland", region: .europe),
        .init(code: "it", name: "Italy", region: .europe),
        .init(code: "xk", name: "Kosovo", region: .europe),
        .init(code: "lv", name: "Latvia", region: .europe),
        .init(code: "lt", name: "Lithuania", region: .europe),
        .init(code: "lu", name: "Luxembourg", region: .europe),
        .init(code: "mt", name: "Malta", region: .europe),
        .init(code: "md", name: "Moldova", region: .europe),
        .init(code: "me", name: "Montenegro", region: .europe),
        .init(code: "nl", name: "Netherlands", region: .europe),
        .init(code: "mk", name: "North Macedonia", region: .europe),
        .init(code: "no", name: "Norway", region: .europe),
        .init(code: "pl", name: "Poland", region: .europe),
        .init(code: "pt", name: "Portugal", region: .europe),
        .init(code: "ro", name: "Romania", region: .europe),
        .init(code: "ru", name: "Russia", region: .europe),
        .init(code: "rs", name: "Serbia", region: .europe),
        .init(code: "sk", name: "Slovakia", region: .europe),
        .init(code: "si", name: "Slovenia", region: .europe),
        .init(code: "es", name: "Spain", region: .europe),
        .init(code: "se", name: "Sweden", region: .europe),
        .init(code: "ch", name: "Switzerland", region: .europe),
        .init(code: "tr", name: "Türkiye", region: .europe),
        .init(code: "ua", name: "Ukraine", region: .europe),
        .init(code: "gb", name: "United Kingdom", region: .europe),
        // africaMiddleEastIndia
        .init(code: "dz", name: "Algeria", region: .africaMiddleEastIndia),
        .init(code: "ao", name: "Angola", region: .africaMiddleEastIndia),
        .init(code: "am", name: "Armenia", region: .africaMiddleEastIndia),
        .init(code: "az", name: "Azerbaijan", region: .africaMiddleEastIndia),
        .init(code: "bh", name: "Bahrain", region: .africaMiddleEastIndia),
        .init(code: "bj", name: "Benin", region: .africaMiddleEastIndia),
        .init(code: "bw", name: "Botswana", region: .africaMiddleEastIndia),
        .init(code: "bf", name: "Burkina Faso", region: .africaMiddleEastIndia),
        .init(code: "cm", name: "Cameroon", region: .africaMiddleEastIndia),
        .init(code: "cv", name: "Cape Verde", region: .africaMiddleEastIndia),
        .init(code: "td", name: "Chad", region: .africaMiddleEastIndia),
        .init(code: "ci", name: "Côte d’Ivoire", region: .africaMiddleEastIndia),
        .init(code: "cd", name: "Congo (DRC)", region: .africaMiddleEastIndia),
        .init(code: "cg", name: "Congo (Republic)", region: .africaMiddleEastIndia),
        .init(code: "eg", name: "Egypt", region: .africaMiddleEastIndia),
        .init(code: "sz", name: "Eswatini", region: .africaMiddleEastIndia),
        .init(code: "ga", name: "Gabon", region: .africaMiddleEastIndia),
        .init(code: "gm", name: "Gambia", region: .africaMiddleEastIndia),
        .init(code: "gh", name: "Ghana", region: .africaMiddleEastIndia),
        .init(code: "gw", name: "Guinea-Bissau", region: .africaMiddleEastIndia),
        .init(code: "in", name: "India", region: .africaMiddleEastIndia),
        .init(code: "iq", name: "Iraq", region: .africaMiddleEastIndia),
        .init(code: "il", name: "Israel", region: .africaMiddleEastIndia),
        .init(code: "jo", name: "Jordan", region: .africaMiddleEastIndia),
        .init(code: "ke", name: "Kenya", region: .africaMiddleEastIndia),
        .init(code: "kw", name: "Kuwait", region: .africaMiddleEastIndia),
        .init(code: "lb", name: "Lebanon", region: .africaMiddleEastIndia),
        .init(code: "lr", name: "Liberia", region: .africaMiddleEastIndia),
        .init(code: "ly", name: "Libya", region: .africaMiddleEastIndia),
        .init(code: "mg", name: "Madagascar", region: .africaMiddleEastIndia),
        .init(code: "mw", name: "Malawi", region: .africaMiddleEastIndia),
        .init(code: "ml", name: "Mali", region: .africaMiddleEastIndia),
        .init(code: "mr", name: "Mauritania", region: .africaMiddleEastIndia),
        .init(code: "mu", name: "Mauritius", region: .africaMiddleEastIndia),
        .init(code: "ma", name: "Morocco", region: .africaMiddleEastIndia),
        .init(code: "mz", name: "Mozambique", region: .africaMiddleEastIndia),
        .init(code: "na", name: "Namibia", region: .africaMiddleEastIndia),
        .init(code: "ne", name: "Niger", region: .africaMiddleEastIndia),
        .init(code: "ng", name: "Nigeria", region: .africaMiddleEastIndia),
        .init(code: "om", name: "Oman", region: .africaMiddleEastIndia),
        .init(code: "qa", name: "Qatar", region: .africaMiddleEastIndia),
        .init(code: "rw", name: "Rwanda", region: .africaMiddleEastIndia),
        .init(code: "st", name: "São Tomé and Príncipe", region: .africaMiddleEastIndia),
        .init(code: "sa", name: "Saudi Arabia", region: .africaMiddleEastIndia),
        .init(code: "sn", name: "Senegal", region: .africaMiddleEastIndia),
        .init(code: "sc", name: "Seychelles", region: .africaMiddleEastIndia),
        .init(code: "sl", name: "Sierra Leone", region: .africaMiddleEastIndia),
        .init(code: "za", name: "South Africa", region: .africaMiddleEastIndia),
        .init(code: "tz", name: "Tanzania", region: .africaMiddleEastIndia),
        .init(code: "tn", name: "Tunisia", region: .africaMiddleEastIndia),
        .init(code: "ug", name: "Uganda", region: .africaMiddleEastIndia),
        .init(code: "ae", name: "United Arab Emirates", region: .africaMiddleEastIndia),
        .init(code: "ye", name: "Yemen", region: .africaMiddleEastIndia),
        .init(code: "zm", name: "Zambia", region: .africaMiddleEastIndia),
        .init(code: "zw", name: "Zimbabwe", region: .africaMiddleEastIndia),
        // asiaPacific
        .init(code: "af", name: "Afghanistan", region: .asiaPacific),
        .init(code: "au", name: "Australia", region: .asiaPacific),
        .init(code: "bt", name: "Bhutan", region: .asiaPacific),
        .init(code: "bn", name: "Brunei", region: .asiaPacific),
        .init(code: "kh", name: "Cambodia", region: .asiaPacific),
        .init(code: "cn", name: "China mainland", region: .asiaPacific),
        .init(code: "fj", name: "Fiji", region: .asiaPacific),
        .init(code: "hk", name: "Hong Kong", region: .asiaPacific),
        .init(code: "id", name: "Indonesia", region: .asiaPacific),
        .init(code: "jp", name: "Japan", region: .asiaPacific),
        .init(code: "kz", name: "Kazakhstan", region: .asiaPacific),
        .init(code: "kr", name: "South Korea", region: .asiaPacific),
        .init(code: "kg", name: "Kyrgyzstan", region: .asiaPacific),
        .init(code: "la", name: "Laos", region: .asiaPacific),
        .init(code: "mo", name: "Macao", region: .asiaPacific),
        .init(code: "my", name: "Malaysia", region: .asiaPacific),
        .init(code: "mv", name: "Maldives", region: .asiaPacific),
        .init(code: "fm", name: "Micronesia", region: .asiaPacific),
        .init(code: "mn", name: "Mongolia", region: .asiaPacific),
        .init(code: "mm", name: "Myanmar", region: .asiaPacific),
        .init(code: "nr", name: "Nauru", region: .asiaPacific),
        .init(code: "np", name: "Nepal", region: .asiaPacific),
        .init(code: "nz", name: "New Zealand", region: .asiaPacific),
        .init(code: "pk", name: "Pakistan", region: .asiaPacific),
        .init(code: "pw", name: "Palau", region: .asiaPacific),
        .init(code: "pg", name: "Papua New Guinea", region: .asiaPacific),
        .init(code: "ph", name: "Philippines", region: .asiaPacific),
        .init(code: "sg", name: "Singapore", region: .asiaPacific),
        .init(code: "sb", name: "Solomon Islands", region: .asiaPacific),
        .init(code: "lk", name: "Sri Lanka", region: .asiaPacific),
        .init(code: "tw", name: "Taiwan", region: .asiaPacific),
        .init(code: "tj", name: "Tajikistan", region: .asiaPacific),
        .init(code: "th", name: "Thailand", region: .asiaPacific),
        .init(code: "to", name: "Tonga", region: .asiaPacific),
        .init(code: "tm", name: "Turkmenistan", region: .asiaPacific),
        .init(code: "uz", name: "Uzbekistan", region: .asiaPacific),
        .init(code: "vu", name: "Vanuatu", region: .asiaPacific),
        .init(code: "vn", name: "Vietnam", region: .asiaPacific),
    ]

    static let regionByCode: [String: StoreRegion] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.code, $0.region) }
    )
}

extension Storefront {

    /// All 175 storefronts, alphabetical. Mapped countries keep their coordinates.
    static let everywhere: [Storefront] = StorefrontDirectory.entries
        .map { entry in
            all.first { $0.code == entry.code }
                ?? Storefront(code: entry.code, name: entry.name, latitude: 0, longitude: 0)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    var region: StoreRegion {
        StorefrontDirectory.regionByCode[code] ?? .asiaPacific
    }
}

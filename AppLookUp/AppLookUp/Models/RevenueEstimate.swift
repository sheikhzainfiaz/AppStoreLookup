import Foundation

// MARK: - Anchor

struct RevenueAnchor: Codable, Identifiable, Sendable {

    var id = UUID()
    var appName: String
    var trackID: Int
    var country: String
    var genreID: Int?
    /// Actual developer proceeds in this storefront for one month, in USD.
    var monthlyProceedsUSD: Double
    /// First-time downloads in this storefront over the same month, if known.
    var monthlyDownloads: Double?
    /// Top Grossing positions on the day the anchor was saved.
    var overallGrossingRank: Int?
    var categoryGrossingRank: Int?
    var recordedAt = Date()

    var proceedsPerDownload: Double? {
        guard let monthlyDownloads, monthlyDownloads > 0, monthlyProceedsUSD > 0 else { return nil }
        return monthlyProceedsUSD / monthlyDownloads
    }
}

struct PerDownloadRate: Sendable {
    let median: Double
    let lowest: Double
    let highest: Double
    let sampleCount: Int
    let isExactMatch: Bool
}

// MARK: - Estimate

struct RevenueEstimate: Sendable {

    enum Source: Sendable {
        case grossingRank
        case perDownload
        case paidUpfront
        case agreement
        case conflict
        case belowChart
        case unavailable

        var label: String {
            switch self {
            case .grossingRank: "From Top Grossing rank"
            case .perDownload: "From downloads × earnings per download"
            case .paidUpfront: "From downloads × price"
            case .agreement: "Rank and downloads agree"
            case .conflict: "Rank and downloads disagree"
            case .belowChart: "Below the Top Grossing 200"
            case .unavailable: "Not enough to estimate"
            }
        }

        var symbol: String {
            switch self {
            case .grossingRank: "chart.line.uptrend.xyaxis"
            case .perDownload: "arrow.down.circle"
            case .paidUpfront: "tag"
            case .agreement: "checkmark.seal"
            case .conflict: "exclamationmark.triangle"
            case .belowChart: "arrow.down.to.line"
            case .unavailable: "questionmark.circle"
            }
        }
    }

    /// USD developer proceeds per month in one storefront.
    let monthly: Double
    let low: Double
    let high: Double
    let source: Source
    let detail: String

    var hasNumber: Bool { source != .unavailable && monthly > 0 }
    var isCeilingOnly: Bool { source == .belowChart }
}


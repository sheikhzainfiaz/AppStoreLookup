import Foundation

enum ChartKind: String, CaseIterable, Identifiable, Sendable {
    case free = "topfreeapplications"
    case paid = "toppaidapplications"
    case grossing = "topgrossingapplications"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "Top Free"
        case .paid: "Top Paid"
        case .grossing: "Top Grossing"
        }
    }
}

struct ChartPlacement: Identifiable, Sendable {

    enum Position: Sendable {
        case ranked(Int)
        case outsideTop(Int)
        case feedUnavailable
    }

    let chart: ChartKind
    let scopeName: String
    let genreID: Int?
    let position: Position

    var id: String { "\(chart.rawValue)-\(genreID ?? 0)" }

    var rank: Int? {
        if case let .ranked(rank) = position { return rank }
        return nil
    }

    var summary: String {
        switch position {
        case let .ranked(rank): "#\(rank)"
        case let .outsideTop(depth): "outside top \(depth)"
        case .feedUnavailable: "no chart"
        }
    }
}


import SwiftUI

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


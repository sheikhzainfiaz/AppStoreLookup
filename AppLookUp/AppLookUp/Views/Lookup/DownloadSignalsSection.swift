import SwiftUI

// MARK: - Downloads

struct DownloadSignalsSection: View {

    let model: LookupViewModel

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

    let model: LookupViewModel

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
                ForEach(model.placementScopes, id: \.self) { scope in
                    HStack(spacing: 8) {
                        Text(scope)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)

                        ForEach(model.placements(in: scope)) { placement in
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
}

private struct Velocity: View {

    let model: LookupViewModel

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

private struct CalibratedBlock: View {

    let model: LookupViewModel

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
                    model.calibrationAnchors.isEmpty ? "Set up calibration" : "Calibration",
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


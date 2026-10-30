import SwiftUI

// MARK: - Calibration

struct CalibrationSheet: View {

    let model: LookupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var downloadsField = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Every download-estimate product guesses what share of installs leave a rating. You don't have to guess — App Store Connect tells you your real numbers. Pair one of your own apps' actual daily downloads with the ratings velocity measured here, and that ratio becomes a measured constant for your category and storefront.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    AnchorForm(model: model, downloadsField: $downloadsField)

                    if !model.calibrationAnchors.isEmpty {
                        ReportSection("Anchors") {
                            VStack(spacing: 0) {
                                ForEach(Array(model.calibrationAnchors.enumerated()), id: \.element.id) { index, anchor in
                                    if index > 0 { Divider() }
                                    AnchorRow(anchor: anchor) { model.removeCalibrationAnchor(anchor) }
                                }
                            }
                            .background(Color.card, in: .rect(cornerRadius: 12))
                        }
                    }

                    CurveForm(model: model)

                    if model.hasCalibrationData {
                        Button("Clear all calibration data", role: .destructive) {
                            model.clearCalibration( )
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

    let model: LookupViewModel
    @Binding var downloadsField: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Anchor this app")

            if let app = model.app, let estimate = model.estimate {
                Text("\(app.trackName) is gaining \(estimate.ratingsPerDay, format: .number.precision(.fractionLength(1))) ratings a day in \(model.storefront.name).")
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
                        if let value = NumericInput.wholeNumber(from: downloadsField) {
                            model.anchorCurrentApp(dailyDownloads: value)
                            downloadsField = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(NumericInput.wholeNumber(from: downloadsField) == nil)
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
    let onRemove: () -> Void

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
                onRemove()
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

    let model: LookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Rank curve")

            Text("Samples apps across the whole chart and watches how fast each gains ratings. Two passes a day apart give the curve's shape, which lets an app you've seen only once be estimated from its rank.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let curve = model.currentCurve {
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


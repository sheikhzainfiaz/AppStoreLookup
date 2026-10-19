//
//  EarningsSection.swift
//  Applookup
//
//  v2: the "Monthly earnings" card in the Lookup report.
//

import SwiftUI

struct EarningsSection: View {

    let model: LookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Monthly earnings")

            EstimateBlock(model: model)
            GrossingLine(model: model)

            Divider()

            OwnerAnchorForm(model: model)

            if !model.revenueAnchors.isEmpty {
                RevenueAnchorList(model: model)
            }

            Text("Earnings are developer proceeds — what's left after Apple's commission — in US dollars. Estimates cover this storefront only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
        .task {
            await model.loadExchangeRatesIfNeeded()
        }
    }
}

// MARK: - Estimate

private struct EstimateBlock: View {

    let model: LookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let estimate = model.earningsEstimate {
                if estimate.hasNumber {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.isCeilingOnly
                             ? "Under \(formatUSD(estimate.high)) a month"
                             : "≈ \(formatUSD(estimate.monthly)) a month")
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .monospacedDigit()

                        HStack(spacing: 6) {
                            if !estimate.isCeilingOnly {
                                Text("\(formatUSD(estimate.low))–\(formatUSD(estimate.high)) range")
                                Text("·").foregroundStyle(.tertiary)
                            }
                            Text("\(model.storefront.flag) \(model.storefront.name)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }

                Label(estimate.source.label, systemImage: estimate.source.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint(for: estimate.source))

                Text(estimate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func tint(for source: RevenueEstimate.Source) -> Color {
        switch source {
        case .agreement: .green
        case .conflict: .orange
        case .unavailable: .secondary
        default: .primary
        }
    }
}

/// Where the app sits on Top Grossing — the input the rank method needs.
private struct GrossingLine: View {

    let model: LookupViewModel

    private var grossing: [ChartPlacement] { model.grossingPlacements }

    var body: some View {
        if grossing.isEmpty {
            Button {
                Task { await model.checkCharts() }
            } label: {
                HStack(spacing: 8) {
                    if model.isCheckingCharts {
                        ProgressView().controlSize(.small)
                        Text("Reading charts…")
                    } else {
                        Image(systemName: "chart.bar.fill")
                        Text("Check Top Grossing charts")
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(model.isCheckingCharts)
        } else {
            HStack(spacing: 6) {
                Text("Top Grossing")
                    .foregroundStyle(.secondary)
                ForEach(grossing) { placement in
                    Text("\(placement.summary) \(placement.scopeName)")
                        .fontWeight(placement.rank == nil ? .regular : .semibold)
                        .foregroundStyle(placement.rank == nil ? .secondary : .primary)
                    if placement.id != grossing.last?.id {
                        Text("·").foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Anchoring

private struct OwnerAnchorForm: View {

    let model: LookupViewModel

    @State private var expanded = false
    @State private var proceedsField = ""
    @State private var downloadsField = ""
    @State private var saved = false

    private var place: Storefront { model.storefront }

    private var proceeds: Double? { NumericInput.decimal(from: proceedsField) }
    private var downloads: Double? { NumericInput.decimal(from: downloadsField) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter last month's real figures for \(place.flag) \(place.name) only. The anchor saves them with today's Top Grossing rank, and every app on the same charts gets an estimate from it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                field("Proceeds in \(place.name), USD / month", text: $proceedsField)
                field("Downloads in \(place.name) / month (optional)", text: $downloadsField)

                if model.placements.isEmpty {
                    Label("Check the charts first so the anchor records its grossing rank.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Will record: \(model.grossingRanksSummary).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(saved ? "Saved" : "Save as earnings anchor") {
                        model.anchorEarnings(monthlyProceedsUSD: proceeds ?? 0, monthlyDownloads: downloads)
                        saved = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((proceeds ?? 0) <= 0 || model.placements.isEmpty)

                    if saved {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("This is my app — anchor it", systemImage: "scope")
                .font(.subheadline.weight(.medium))
        }
        .onChange(of: model.app?.trackId) { resetFields() }
        .onChange(of: model.country) { resetFields() }
        .onChange(of: proceedsField) { saved = false }
    }

    /// Figures typed for one app or storefront never carry over to the next.
    private func resetFields() {
        saved = false
        proceedsField = ""
        downloadsField = ""
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface, in: .rect(cornerRadius: 10))
    }
}

private struct RevenueAnchorList: View {

    let model: LookupViewModel

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(model.revenueAnchors.enumerated()), id: \.element.id) { index, anchor in
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(anchor.appName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(summary(anchor))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(formatUSD(anchor.monthlyProceedsUSD))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                        Button {
                            model.removeRevenueAnchor(anchor)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                }
            }
        } label: {
            Text("Earnings anchors (\(model.revenueAnchors.count))")
                .font(.subheadline.weight(.medium))
        }
    }

    private func summary(_ anchor: RevenueAnchor) -> String {
        var parts = [Storefront.named(anchor.country).flag]
        if let rank = anchor.categoryGrossingRank { parts.append("#\(rank) category") }
        if let rank = anchor.overallGrossingRank { parts.append("#\(rank) overall") }
        if anchor.categoryGrossingRank == nil, anchor.overallGrossingRank == nil { parts.append("unranked") }
        if let perDownload = anchor.proceedsPerDownload { parts.append("\(formatUSD(perDownload, cents: true))/download") }
        parts.append(anchor.recordedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

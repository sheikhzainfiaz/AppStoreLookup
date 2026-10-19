//
//  EarningsScreen.swift
//  Applookup
//
//  v2: the Earnings tab — actual monthly earnings from App Store Connect.
//

import Charts
import SwiftUI

struct EarningsScreen: View {

    @Bindable var model: EarningsViewModel
    /// (query, storefront code) → open the full report in the Lookup tab.
    let onOpenReport: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !model.isConfigured {
                        ConnectCard(model: model)
                    } else {
                        if let message = model.errorMessage {
                            MessageBox(text: message, symbol: "exclamationmark.triangle")
                        }

                        if model.months.isEmpty && model.isLoading {
                            ProgressView("Loading reports…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                        } else if !model.months.isEmpty {
                            MonthOverview(model: model)
                            AppBreakdown(model: model)
                            SourceNote(lastLoaded: model.lastLoaded)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.isConfigured {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            model.presentSetup()
                        } label: {
                            Image(systemName: "key")
                        }
                        .accessibilityLabel("App Store Connect key")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.load() }
                        } label: {
                            if model.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(model.isLoading)
                        .accessibilityLabel("Reload")
                    }
                }
            }
            .refreshable { await model.load() }
            .task { await model.loadIfNeeded() }
            .sheet(item: $model.setup) { setup in
                ASCSetupSheet(model: setup)
            }
            .navigationDestination(for: String.self) { key in
                AppEarningsDetailView(model: model.detail(for: key), onOpenReport: onOpenReport)
            }
        }
    }
}

// MARK: - Not connected

private struct ConnectCard: View {

    let model: EarningsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text("Your real monthly earnings")
                .font(.title3.weight(.semibold))

            Text("Apple publishes no earnings for any app. The actual numbers live in App Store Connect, for the apps your team owns. Connect an API key and this tab shows what each of your apps earned, month by month — and the Lookup tab uses those figures to calibrate earnings estimates for competitors.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.presentSetup()
            } label: {
                Label("Connect App Store Connect", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Overview

private struct MonthOverview: View {

    let model: EarningsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = model.selectedSummary {
                Totals(summary: summary)
            }

            let bars = model.bars
            if !bars.isEmpty {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Month", bar.label),
                        y: .value("Earnings", bar.usd)
                    )
                    .foregroundStyle(bar.key == model.selectedMonth?.key ? Color.accentColor : Color.accentColor.opacity(0.35))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD").notation(.compactName))
                            }
                        }
                    }
                }
                .frame(height: 170)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.months) { month in
                        let isActive = model.isSelected(month)
                        Button {
                            model.select(month)
                        } label: {
                            Text(month.shortLabel)
                                .font(.caption.weight(isActive ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isActive ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary),
                                    in: .capsule
                                )
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .opacity(month.isLoaded ? 1 : 0.5)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }

    private struct Totals: View {

        let summary: EarningsViewModel.MonthSummary

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.month.longLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch summary.month.state {
                case .loading:
                    ProgressView().padding(.vertical, 8)
                case let .notReady(detail):
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                case let .failed(detail):
                    Label(detail, systemImage: "xmark.circle").font(.subheadline).foregroundStyle(.secondary)
                case .loaded, .noSales:
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(summary.proceedsUSD.map { formatUSD($0) } ?? "—")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let change = summary.change {
                            Text(change, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(change >= 0 ? .green : .red)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Earnings after Apple's cut")
                        if let gross = summary.grossUSD, gross > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(formatUSD(gross)) gross sales")
                        }
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(Int(summary.downloads).formatted()) downloads")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

// MARK: - Per app

private struct AppBreakdown: View {

    let model: EarningsViewModel

    var body: some View {
        if let month = model.selectedMonth, month.isLoaded {
            let rows = model.appRows
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("By app · \(month.longLabel)")

                if rows.isEmpty {
                    Text("No sales, downloads or in-app purchases that month.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().padding(.leading, 60) }
                            NavigationLink(value: row.app.key) {
                                AppEarningsRow(row: row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.card, in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}

private struct AppEarningsRow: View {

    let row: EarningsViewModel.AppRow

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: row.listing?.artworkURL, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.listing?.trackName ?? row.app.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(4, 110 * row.share), height: 5)

                Text("\(Int(row.app.downloads).formatted()) downloads")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(row.usd.map { formatUSD($0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct SourceNote: View {
    let lastLoaded: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From App Store Connect Sales and Trends (monthly summary). Earnings are developer proceeds: units × proceeds per unit, after Apple's commission and before tax adjustments. Other currencies are converted to USD at today's rates, so totals are close to — not identical to — what Apple pays out. The Payments and Financial Reports page is the final word on payouts.")
            if let lastLoaded {
                Text("Updated \(lastLoaded.formatted(.relative(presentation: .named))).")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

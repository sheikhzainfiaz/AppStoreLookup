import Charts
import SwiftUI

struct AppEarningsDetailView: View {

    let model: AppEarningsDetailViewModel
    let onOpenReport: (String, String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AppIcon(url: model.artworkURL, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let id = model.appleID {
                            Text("Apple ID \(String(id))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                let points = model.points
                if points.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Monthly earnings")
                        Chart(points) { point in
                            LineMark(x: .value("Month", point.label), y: .value("Earnings", point.usd))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", point.label), y: .value("Earnings", point.usd))
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
                        .frame(height: 160)
                    }
                    .padding(20)
                    .background(Color.card, in: .rect(cornerRadius: 14))
                }

                if model.current != nil, let month = model.month {
                    ReportSection(month.longLabel) {
                        DetailRows(rows: model.rows)
                    }
                } else if let month = model.month {
                    Text("Nothing for this app in \(month.longLabel).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                let countries = model.countries
                if !countries.isEmpty {
                    ReportSection("By storefront") {
                        VStack(spacing: 0) {
                            let limit = AppEarningsDetailViewModel.countryLimit
                            ForEach(Array(countries.prefix(limit).enumerated()), id: \.element.id) { index, country in
                                if index > 0 { Divider().padding(.leading, 44) }
                                HStack(spacing: 10) {
                                    Text(country.storefront.flag).frame(width: 24)
                                    Text(country.storefront.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(Int(country.downloads).formatted()) dl")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatUSD(country.usd))
                                        .font(.subheadline.weight(.medium))
                                        .frame(minWidth: 70, alignment: .trailing)
                                }
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            if countries.count > limit {
                                Text("+\(countries.count - limit) more storefronts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                            }
                        }
                        .background(Color.card, in: .rect(cornerRadius: 14))
                    }
                }

                if let target = model.reportTarget {
                    Button {
                        onOpenReport(target.query, target.country)
                    } label: {
                        Label("Open App Store report", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .background(Color.surface)
        .navigationTitle(model.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 16) }
                HStack {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

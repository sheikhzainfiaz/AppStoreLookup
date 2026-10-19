import SwiftUI

// MARK: - Report

struct AppReport: View {

    let app: AppStoreApp
    let model: LookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            AppHeader(app: app)
            RatingsPanel(app: app, model: model)
            WorldSection(model: model)

            if !app.allScreenshots.isEmpty {
                Screenshots(urls: app.allScreenshots)
            }

            if let notes = app.releaseNotes, !notes.isEmpty {
                ReportSection("What's new in \(app.version ?? "this version")") {
                    ExpandableText(notes)
                }
            }

            if let description = app.appDescription, !description.isEmpty {
                ReportSection("Description") {
                    ExpandableText(description)
                }
            }

            ReportSection("Details") {
                DetailGrid(app: app)
            }

            DownloadSignalsSection(model: model)
            EarningsSection(model: model)
            ReviewsSection(model: model.reviews)

            if let link = app.trackViewUrl, let url = URL(string: link) {
                Link(destination: url) {
                    Label("Open in the App Store", systemImage: "arrow.up.right.square")
                }
                .font(.subheadline)
            }
        }
    }
}

// MARK: - Ratings

private struct RatingsPanel: View {

    let app: AppStoreApp
    let model: LookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                RatingBlock(
                    title: model.storefront.name,
                    average: app.averageUserRating,
                    count: app.userRatingCount
                )
                Divider().frame(height: 62)
                RatingBlock(
                    title: "Version \(app.version ?? "current")",
                    average: app.averageUserRatingForCurrentVersion,
                    count: app.userRatingCountForCurrentVersion
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Screenshots

private struct Screenshots: View {

    let urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Screenshots")

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(urls, id: \.self) { url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                                .frame(width: 150, height: 320)
                        }
                        .frame(height: 320)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }
}


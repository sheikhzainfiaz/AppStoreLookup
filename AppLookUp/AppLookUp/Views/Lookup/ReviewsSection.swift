import SwiftUI

// MARK: - Reviews

struct ReviewsSection: View {

    let model: ReviewsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Reviews")
                Spacer()
                if !model.items.isEmpty {
                    Text("\(model.items.count) loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !model.hasStarted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review text comes from a separate feed, 50 at a time, capped at 500 per storefront.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await model.load() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isLoading {
                                ProgressView().controlSize(.small)
                                Text("Loading…")
                            } else {
                                Image(systemName: "text.bubble")
                                Text("Load reviews")
                            }
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                }
            } else {
                SortBar(model: model)

                if model.items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            Text(model.notice ?? "Nothing came back for this sort.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Try again") {
                                Task { await model.load(startingOver: true) }
                            }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    if model.isOrderedLocally {
                        Label("This storefront only serves the recent feed, so these are ordered on device.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ReviewSpread(digest: model.digest)

                    ForEach(model.items) { review in
                        ReviewCard(review: review)
                    }

                    if let notice = model.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if model.canLoadMore {
                        Button {
                            Task { await model.load() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isLoading {
                                    ProgressView().controlSize(.small)
                                }
                                Text(model.isLoading ? "Loading…" : "Load 50 more")
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoading)
                    }
                }
            }
        }
    }
}

private struct SortBar: View {

    let model: ReviewsViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReviewSort.allCases) { sort in
                    let isActive = model.sort == sort
                    Button {
                        Task { await model.changeSort(to: sort) }
                    } label: {
                        // Padding and background belong inside the label, or only the glyph is tappable.
                        Text(sort.label)
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
                }
            }
        }
        .scrollIndicators(.hidden)
        .disabled(model.isLoading)
    }
}

/// Apple's own star breakdown isn't in any public endpoint, so this is the spread of the
/// reviews we actually pulled — written reviews skew harder than tapped stars.
private struct ReviewSpread: View {

    let digest: ReviewDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 5, through: 1, by: -1)), id: \.self) { stars in
                HStack(spacing: 8) {
                    Text("\(stars)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(stars >= 4 ? Color.green : stars == 3 ? .orange : .red)
                            .opacity(0.65)
                            .frame(width: max(2, proxy.size.width * digest.share(of: stars)))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 7)

                    Text("\(digest.counts[stars] ?? 0)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            Text("Spread of loaded reviews, not Apple's full breakdown.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }
}

private struct ReviewCard: View {

    let review: AppReview
    @State private var expanded = false

    private var isLong: Bool { review.body.count > 280 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Stars(value: Double(review.rating))
                Text(review.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(review.body)
                .font(.subheadline)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if isLong {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            HStack(spacing: 6) {
                Text(review.author)
                if let version = review.version {
                    Text("·").foregroundStyle(.tertiary)
                    Text("v\(version)")
                }
                if let updated = review.updated {
                    Text("·").foregroundStyle(.tertiary)
                    Text(updated.formatted(.relative(presentation: .named)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }
}


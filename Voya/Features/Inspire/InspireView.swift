import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct InspireView: View {
    @EnvironmentObject private var store: VoyaStore
    @State private var didSearch = false
    @State private var comparisonRecommendation: TripRecommendation?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Voya", subtitle: "Tuesday, June 30")

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plan the trip that actually fits.")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .lineSpacing(1)
                                .foregroundStyle(Color.voyaInk)

                            Text("Budget, weather, flights, hotels, events, and calm trade-offs in one place.")
                                .font(.subheadline)
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "location.north.line.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [.voyaInk, .voyaTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.voyaMuted)
                            TextField("Warm 4-day trip under $700", text: $store.inspirationText, axis: .vertical)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(2...4)
                        }
                        .padding(14)
                        .background(.white.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(TripMood.allCases) { mood in
                                    MoodChip(mood: mood, isSelected: mood == store.selectedMood) {
                                        store.selectedMood = mood
                                    }
                                }
                            }
                        }

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                didSearch = true
                            }
                        } label: {
                            HStack {
                                Text("Find strong options")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(colors: [.white, .voyaMint], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .foregroundStyle(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 14)

                if didSearch {
                    InspirationBriefCard(intent: store.inspirationText, mood: store.selectedMood)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                SectionHeader(title: "Best matches", action: "See all")

                VStack(spacing: 14) {
                    ForEach(store.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation) {
                            comparisonRecommendation = recommendation
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .sheet(item: $comparisonRecommendation) { recommendation in
            RecommendationComparisonView(recommendation: recommendation)
        }
    }
}

struct RecommendationCard: View {
    @Environment(\.openURL) private var openURL
    let recommendation: TripRecommendation
    let onCompare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DestinationMark(destination: recommendation.destination, color: recommendation.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.destination)
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(recommendation.dates) · \(recommendation.fit)")
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()

                Text(recommendation.estimatedCost)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(recommendation.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(recommendation.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                ForEach(recommendation.details.prefix(3), id: \.self) { detail in
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            HStack(spacing: 12) {
                IconTextButton(title: "Compare", symbol: "slider.horizontal.3", style: .secondary, action: onCompare)
                IconTextButton(title: "Booking links", symbol: "safari", style: .primary) {
                    if let url = bookingSearchURL {
                        openURL(url)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var bookingSearchURL: URL? {
        let query = "\(recommendation.destination) flights hotels events \(recommendation.dates)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

struct InspirationBriefCard: View {
    let intent: String
    let mood: TripMood

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "checklist.checked")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Search brief")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Flexible trip") : intent)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                InspirationSignal(title: "Style", value: mood.displayName, symbol: "sparkles")
                InspirationSignal(title: "Compare", value: "Full trip", symbol: "slider.horizontal.3")
                InspirationSignal(title: "Booking", value: "External", symbol: "safari")
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct InspirationSignal: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct RecommendationComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let recommendation: TripRecommendation

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recommendation.destination)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("\(recommendation.dates) · \(recommendation.fit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Trip fit")
                            .font(.headline)
                            .foregroundStyle(Color.voyaInk)

                        ForEach(recommendation.details, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            MomentMetric(title: "Estimate", value: recommendation.estimatedCost, symbol: "creditcard", tint: recommendation.accent)
                            MomentMetric(title: "Booking", value: "External", symbol: "safari", tint: Color.voyaTeal)
                        }

                        Button {
                            if let url = bookingSearchURL {
                                openURL(url)
                            }
                        } label: {
                            Label("Open booking search", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundStyle(.white)
                                .background(Color.voyaInk)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var bookingSearchURL: URL? {
        let query = "\(recommendation.destination) flights hotels events \(recommendation.dates)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

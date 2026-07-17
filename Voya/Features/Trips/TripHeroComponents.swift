import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct TripHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let trip: Trip
    let onEdit: () -> Void

    private var summary: TripHeroSummary {
        TripHeroSummary(trip: trip)
    }

    private var displayTitle: String {
        trip.destination?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? trip.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

                    Text(trip.displayDates)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                }

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(trip.title)")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.statusText)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

                Text(summary.readinessText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            }

            HStack(spacing: 10) {
                MetricPill(title: "Duration", value: summary.durationText)
                MetricPill(title: "Items", value: summary.itemCountText)
                MetricPill(title: "Status", value: summary.phaseText)
            }

            if let credit = trip.destinationImageCredit?.nilIfEmpty {
                HStack {
                    Spacer(minLength: 0)
                    if let creditURL = trip.destinationImageCreditURL {
                        Link(credit, destination: creditURL)
                    } else {
                        Text(credit)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 258, alignment: .topLeading)
        .background {
            TripHeroBackground(imageURL: trip.destinationImageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(heroBorderGradient, lineWidth: 7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .inset(by: 10)
                .stroke(.white.opacity(colorScheme == .dark ? 0.26 : 0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 22, y: 14)
        .shadow(color: Color.voyaGold.opacity(colorScheme == .dark ? 0.30 : 0.18), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var heroBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.91, blue: 0.55).opacity(colorScheme == .dark ? 0.92 : 0.82),
                Color.voyaMint.opacity(colorScheme == .dark ? 0.82 : 0.64),
                Color.voyaGold.opacity(colorScheme == .dark ? 0.84 : 0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct TripHeroSummary {
    let statusText: String
    let durationText: String
    let itemCountText: String
    let phaseText: String
    let firstUpText: String
    let readinessText: String

    init(trip: Trip, now: Date = Date(), calendar: Calendar = .current) {
        let range = TripDateRange(trip: trip, calendar: calendar)
        let daysUntilStart = range.map { calendar.startOfDay(for: now).distanceInDays(to: calendar.startOfDay(for: $0.start), calendar: calendar) }

        if let range, calendar.isDate(now, inSameDayAs: range.start) {
            statusText = String(localized: "Starts today")
            phaseText = String(localized: "Today")
        } else if let range, now >= range.start && now <= range.end {
            statusText = String(localized: "In progress")
            phaseText = String(localized: "Live")
        } else if let daysUntilStart, daysUntilStart > 0 {
            statusText = String(localized: "Starts in \(daysUntilStart) \(daysUntilStart == 1 ? "day" : "days")")
            phaseText = String(localized: "Ready")
        } else if range != nil {
            statusText = String(localized: "Trip ended")
            phaseText = String(localized: "Done")
        } else {
            statusText = String(localized: "Dates needed")
            phaseText = String(localized: "Ready")
        }

        if let nights = range?.nights, nights > 0 {
            durationText = String(localized: "\(nights) \(nights == 1 ? "night" : "nights")")
        } else if let days = range?.days, days > 0 {
            durationText = String(localized: "\(days) \(days == 1 ? "day" : "days")")
        } else {
            durationText = trip.displayDates
        }

        itemCountText = String(localized: "\(trip.items.count) \(trip.items.count == 1 ? "item" : "items")")
        readinessText = String(localized: "Plan is ready")

        let firstItem = trip.items
            .filter { $0.startsAt != nil }
            .min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            ?? trip.items.first
        if let firstItem {
            firstUpText = String(localized: "First up: \(firstItem.title)")
        } else {
            firstUpText = trip.summary
        }
    }
}

struct TripDateRange {
    let start: Date
    let end: Date

    var days: Int {
        max(1, Calendar.current.dateComponents([.day], from: start, to: end).day.map { $0 + 1 } ?? 1)
    }

    var nights: Int {
        max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    init?(trip: Trip, calendar: Calendar) {
        let explicitDates = [trip.startsAt, trip.endsAt].compactMap { $0 }
        let itemDates = trip.items.flatMap { item in [item.startsAt, item.endsAt].compactMap { $0 } }
        let dates = explicitDates.isEmpty ? itemDates : explicitDates
        guard let first = dates.min(), let last = dates.max() else {
            return nil
        }

        start = calendar.startOfDay(for: first)
        end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: last) ?? last
    }
}

extension Date {
    func distanceInDays(to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: self, to: date).day ?? 0
    }
}

struct TripHeroBackground: View {
    let imageURL: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.voyaMint,
                    Color.voyaTeal.opacity(0.86),
                    Color.voyaInk
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.46),
                    .black.opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

                    Text(trip.dates)
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

                Text(summary.firstUpText)
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
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 238, alignment: .topLeading)
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
        .accessibilityElement(children: .combine)
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

    init(trip: Trip, now: Date = Date(), calendar: Calendar = .current) {
        let range = TripDateRange(dates: trip.dates, now: now, calendar: calendar)
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
            durationText = trip.dates
        }

        itemCountText = String(localized: "\(trip.items.count) \(trip.items.count == 1 ? "item" : "items")")

        if let firstItem = trip.items.first {
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

    init?(dates: String, now: Date, calendar: Calendar) {
        guard let parsed = Self.parse(dates) else {
            return nil
        }

        let currentYear = calendar.component(.year, from: now)
        var startComponents = DateComponents(year: currentYear, month: parsed.startMonth, day: parsed.startDay)
        var endComponents = DateComponents(year: currentYear, month: parsed.endMonth, day: parsed.endDay)

        guard var start = calendar.date(from: startComponents),
              var end = calendar.date(from: endComponents) else {
            return nil
        }

        if end < start {
            endComponents.year = currentYear + 1
            guard let adjustedEnd = calendar.date(from: endComponents) else {
                return nil
            }
            end = adjustedEnd
        }

        if end < calendar.startOfDay(for: now) {
            startComponents.year = currentYear + 1
            endComponents.year = endComponents.year.map { $0 + 1 }
            guard let adjustedStart = calendar.date(from: startComponents),
                  let adjustedEnd = calendar.date(from: endComponents) else {
                return nil
            }
            start = adjustedStart
            end = adjustedEnd
        }

        self.start = calendar.startOfDay(for: start)
        self.end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
    }

    private static func parse(_ value: String) -> (startMonth: Int, startDay: Int, endMonth: Int, endDay: Int)? {
        let dates = parsedDates(in: value)
        guard let first = dates.first else {
            return nil
        }

        let last = dates.dropFirst().last ?? first
        return (first.month, first.day, last.month, last.day)
    }

    private static func parsedDates(in value: String) -> [(month: Int, day: Int)] {
        let pattern = #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})|-\s*(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var latestMonth: Int?
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            if let monthRange = Range(match.range(at: 1), in: value),
               let dayRange = Range(match.range(at: 2), in: value),
               let month = monthNumber(String(value[monthRange])),
               let day = Int(value[dayRange]) {
                latestMonth = month
                return (month, day)
            }

            if let dayRange = Range(match.range(at: 3), in: value),
               let month = latestMonth,
               let day = Int(value[dayRange]) {
                return (month, day)
            }

            return nil
        }
    }

    private static func monthNumber(_ value: String) -> Int? {
        let months = [
            "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4,
            "May": 5, "Jun": 6, "Jul": 7, "Aug": 8,
            "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12
        ]
        return months[String(value.prefix(3).capitalized)]
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

import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct HeaderBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(Color.voyaInk)
                    .frame(width: 44, height: 44)
                    .background(.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
            }
        }
    }
}

struct VoyaTabBar: View {
    @Binding var selectedTab: VoyaTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VoyaTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .bold))
                        Text(tab.displayName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(selectedTab == tab ? Color.voyaInk : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

struct MoodChip: View {
    let mood: TripMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mood.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Color.voyaInk)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? Color.voyaInk : .white.opacity(0.88))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TripChip: View {
    let trip: Trip
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(trip.dates)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Color.voyaInk)
            .padding(.horizontal, 14)
            .frame(width: 148, height: 58, alignment: .leading)
            .background(isSelected ? Color.voyaInk : .white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.04), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyTripsCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
                .frame(width: 48, height: 48)
                .background(Color.voyaTeal.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(.headline.bold())
                .foregroundStyle(Color.voyaInk)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.voyaMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct TripOperationsCard: View {
    let trip: Trip
    let itinerary: [ItineraryItem]
    let onOpenAssistant: (ItineraryItem) -> Void

    private var sortedItems: [ItineraryItem] {
        itinerary.sorted { first, second in
            switch (first.startsAt, second.startsAt) {
            case let (firstDate?, secondDate?):
                return firstDate < secondDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return first.createdAt < second.createdAt
            }
        }
    }

    private var nextItem: ItineraryItem? {
        let now = Date()
        return sortedItems.first { item in
            guard let start = item.startsAt else {
                return false
            }
            return (item.endsAt ?? start) >= now
        } ?? sortedItems.first
    }

    private var firstTimedItem: ItineraryItem? {
        sortedItems.first { $0.startsAt != nil }
    }

    private var lastTimedItem: ItineraryItem? {
        sortedItems.last { $0.startsAt != nil || $0.endsAt != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "location.viewfinder")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Up next")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(nextItem.map(nextActionSummary) ?? commandSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let nextItem {
                Button {
                    onOpenAssistant(nextItem)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: nextItem.kind.symbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(nextItem.kind.timelineAccent)
                            .frame(width: 34, height: 34)
                            .background(nextItem.kind.timelineAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(nextItem.title.isEmpty ? String(localized: "Untitled item") : nextItem.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(1)
                            Text(nextItemDetail)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        VStack(spacing: 3) {
                            Image(systemName: "message.badge")
                                .font(.subheadline.weight(.bold))
                            Text("Assistant")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Color.voyaTeal)
                    }
                    .padding(12)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var commandSummary: String {
        if let destination = trip.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            return String(localized: "\(destination) · \(trip.displayDates)")
        }

        if let firstTimedItem, let lastTimedItem, firstTimedItem.id != lastTimedItem.id {
            return String(localized: "\(firstTimedItem.displayTime) to \(lastTimedItem.displayTime)")
        }

        return trip.summary.isEmpty ? String(localized: "Ready for itinerary review") : trip.summary
    }

    private func nextActionSummary(_ item: ItineraryItem) -> String {
        guard let startsAt = item.startsAt else {
            return String(localized: "Time needed")
        }

        return TripCommandDateFormatter.nextAction.string(from: startsAt)
    }

    private var nextItemDetail: String {
        guard let nextItem else { return "" }
        let place = nextItem.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? String(localized: "Location needed") : place
    }
}

enum TripCommandDateFormatter {
    static let nextAction: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEjm")
        return formatter
    }()
}

struct TripMetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct DestinationMark: View {
    let destination: String
    let color: Color

    var initials: String {
        String(destination.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.16))
            Text(initials)
                .font(.headline.bold())
                .foregroundStyle(color)
        }
        .frame(width: 54, height: 54)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    let action: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.voyaInk)
            Spacer()
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voyaTeal)
        }
    }
}

enum ButtonChrome {
    case primary
    case secondary
}

struct IconTextButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let style: ButtonChrome
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(style == .primary ? .white : Color.voyaInk)
                .background(style == .primary ? Color.voyaInk : Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MetricPill: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .opacity(0.72)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

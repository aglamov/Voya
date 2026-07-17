import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct FlightOperationalStatus {
    enum Tone: Equatable {
        case neutral
        case active
        case warning
        case critical
        case complete
    }

    let label: String
    let symbol: String
    let tone: Tone

    init(response: FlightLookupResponse?, fallbackStatus: String) {
        let snapshotStatus = response?.snapshot?.status.lowercased() ?? ""
        let providerStatus = response?.snapshot?.providerStatus
            ?? response?.candidate?.providerStatus
            ?? fallbackStatus
        let combined = "\(snapshotStatus) \(providerStatus)".lowercased()
        let delayMinutes = response?.delayStats?.delayMinutes ?? response?.snapshot?.delayMinutes
        let progress = response?.snapshot?.progressPercent ?? response?.plane?.progressPercent

        if response != nil, response?.validation.state != "validated", response?.snapshot == nil {
            label = String(localized: "Data not confirmed")
            symbol = "exclamationmark.triangle.fill"
            tone = .warning
        } else if combined.contains("cancel") || combined.contains("отмен") {
            label = String(localized: "Cancelled")
            symbol = "xmark.circle.fill"
            tone = .critical
        } else if combined.contains("divert") || combined.contains("redirect") || combined.contains("смен") {
            label = String(localized: "Route changed")
            symbol = "arrow.triangle.branch"
            tone = .critical
        } else if let delayMinutes, delayMinutes >= 15 {
            label = String(localized: "Delayed \(delayMinutes) min")
            symbol = "clock.badge.exclamationmark.fill"
            tone = .warning
        } else if combined.contains("delay") || combined.contains("задерж") {
            label = String(localized: "Delayed")
            symbol = "clock.badge.exclamationmark.fill"
            tone = .warning
        } else if snapshotStatus == "departed" || response?.plane?.state == "current_airborne" {
            label = progress.map { String(localized: "In flight · \(Int($0.rounded()))%") }
                ?? String(localized: "In flight")
            symbol = "airplane"
            tone = .active
        } else if snapshotStatus == "arrived" || combined.contains("landed") || combined.contains("прибыл") {
            label = String(localized: "Arrived")
            symbol = "checkmark.circle.fill"
            tone = .complete
        } else if combined.contains("board") || combined.contains("посадк") {
            label = String(localized: "Boarding")
            symbol = "person.line.dotted.person.fill"
            tone = .active
        } else if response?.gate?.changed == true {
            label = String(localized: "Gate changed")
            symbol = "arrow.triangle.2.circlepath"
            tone = .warning
        } else {
            label = String(localized: "On schedule")
            symbol = "calendar.badge.checkmark"
            tone = .neutral
        }
    }

    var tint: Color {
        switch tone {
        case .neutral, .active:
            Color.voyaTeal
        case .warning:
            Color.voyaGold
        case .critical:
            Color.voyaCoral
        case .complete:
            Color.voyaMuted
        }
    }
}

struct ItemCompanionCard: View {
    let item: ItineraryItem
    let phase: ItineraryPhase
    let enrichment: ItemEnrichment?
    let flightStatusResponse: FlightLookupResponse?
    let didCopyLocation: Bool
    let onOpenLocation: () -> Void
    let onCopyLocation: () -> Void
    @State private var displayLocation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 10) {
                    Label(kindLabel, systemImage: item.kind.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.kind.timelineAccent)

                    Spacer(minLength: 8)

                    Label(statusLabel, systemImage: statusSymbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusTint.opacity(0.10))
                        .clipShape(Capsule())
                }

                if let flightRoute {
                    flightHeader(flightRoute)
                } else {
                    standardHeader
                }

                Divider()

                HStack(spacing: 9) {
                    MomentMetric(title: "Time", value: timeMetric, symbol: "clock", tint: item.kind.timelineAccent)
                    MomentMetric(title: secondaryMetricTitle, value: secondaryMetricValue, symbol: secondaryMetricSymbol, tint: secondaryMetricTint)
                }

                if let summaryText {
                    Text(summaryText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let aircraftLocationCard {
                    AircraftLocationSummary(card: aircraftLocationCard, tint: item.kind.timelineAccent)
                }
            }
            .padding(18)

            if item.kind != .flight {
                MomentLocationRow(
                    item: item,
                    displayLocation: displayLocation,
                    route: flightRoute,
                    isCopied: didCopyLocation,
                    onOpenLocation: onOpenLocation,
                    onCopyLocation: onCopyLocation
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(item.kind.timelineAccent.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
        .task(id: item.location) {
            displayLocation = LocationDisplayResolver.immediateDisplayName(for: item.location)
            displayLocation = await LocationDisplayResolver.resolvedDisplayName(for: item.location)
        }
    }

    private func flightHeader(_ route: FlightRouteDisplay) -> some View {
        HStack(alignment: .center, spacing: 12) {
            airportBlock(code: route.origin, time: startTimeText, alignment: .leading, isTrailing: false)

            VStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted.opacity(0.64))
                Capsule()
                    .fill(Color.voyaLine)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)

            airportBlock(code: route.destination, time: endTimeText, alignment: .trailing, isTrailing: true)
        }
    }

    private func airportBlock(code: String, time: String, alignment: HorizontalAlignment, isTrailing: Bool) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(code)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(time)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(item.kind.timelineAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: 96, alignment: isTrailing ? .trailing : .leading)
    }

    private var standardHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(item.kind.timelineAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(displayLocation.isEmpty ? locationFallback : displayLocation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displayTitle: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Untitled item") : title
    }

    private var kindLabel: String {
        switch item.kind {
        case .flight: String(localized: "Flight")
        case .hotel: String(localized: "Stay")
        case .event: String(localized: "Event")
        case .transit: String(localized: "Transfer")
        }
    }

    private var statusLabel: String {
        if item.kind == .flight {
            return flightOperationalStatus.label
        }

        if let warning = enrichment?.warnings.first, !warning.isEmpty {
            return String(localized: "Needs attention")
        }

        let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty {
            return status
        }

        return phase.label
    }

    private var statusSymbol: String {
        if item.kind == .flight {
            return flightOperationalStatus.symbol
        }

        if enrichment?.warnings.first?.isEmpty == false {
            return "exclamationmark.triangle.fill"
        }

        switch phase {
        case .past:
            return "checkmark.circle.fill"
        case .current:
            return "dot.radiowaves.left.and.right"
        case .future:
            return "calendar.badge.clock"
        case .undated:
            return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        if item.kind == .flight {
            return flightOperationalStatus.tint
        }

        if enrichment?.warnings.first?.isEmpty == false {
            return Color.voyaCoral
        }

        switch phase {
        case .past:
            return Color.voyaMuted
        case .current:
            return Color.voyaTeal
        case .future:
            return item.kind.timelineAccent
        case .undated:
            return Color.voyaGold
        }
    }

    private var timeMetric: String {
        item.startsAt == nil ? String(localized: "Add time") : item.displayTime
    }

    private var secondaryMetricTitle: LocalizedStringKey {
        if itemDurationText != nil {
            return "Duration"
        }
        if bufferText != nil {
            return "Buffer"
        }
        return item.kind == .flight ? "Route" : "Place"
    }

    private var secondaryMetricValue: String {
        itemDurationText ?? bufferText ?? shortLocationText
    }

    private var secondaryMetricSymbol: String {
        if itemDurationText != nil {
            return "timer"
        }
        if bufferText != nil {
            return "figure.walk"
        }
        return item.kind == .flight ? "arrow.left.arrow.right" : "mappin.and.ellipse"
    }

    private var secondaryMetricTint: Color {
        if bufferText != nil {
            return Color.voyaTeal
        }
        return item.kind.timelineAccent
    }

    private var bufferText: String? {
        guard let bufferMinutes = enrichment?.routeLegs.first?.bufferMinutes else {
            return nil
        }
        return String(localized: "\(bufferMinutes) min")
    }

    private var summaryText: String? {
        if let warning = enrichment?.warnings.first, !warning.isEmpty {
            return trimmedBody(warning)
        }

        if let action = enrichment?.actions.first {
            return trimmedBody([action.title, action.detail].filter { !$0.isEmpty }.joined(separator: ". "))
        }

        if let summary = enrichment?.summary.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return trimmedBody(summary)
        }

        if item.kind == .flight {
            return nil
        }

        return defaultOperationalNote
    }

    private var flightOperationalStatus: FlightOperationalStatus {
        FlightOperationalStatus(response: flightStatusResponse, fallbackStatus: item.status)
    }

    private var aircraftLocationCard: ItemEnrichmentCard? {
        guard item.kind == .flight else {
            return nil
        }

        return enrichment?.cards.first { card in
            let title = card.title.lowercased()
            let value = card.value.lowercased()
            return card.kind == "flight"
                && (
                    title.contains("aircraft location")
                    || value.contains("assigned aircraft")
                    || value.contains("airborne")
                    || value.contains("inbound")
                )
        }
    }

    private var defaultOperationalNote: String {
        switch item.kind {
        case .flight:
            return String(localized: "Add flight status data to surface gate, delay, airport buffer, and arrival route.")
        case .hotel:
            return String(localized: "Add address and check-in time to prepare the arrival route and stay details.")
        case .event:
            return String(localized: "Add venue and start time to prepare route, entry buffer, ticket, and weather context.")
        case .transit:
            return String(localized: "Add departure and arrival details to prepare route timing and fallback options.")
        }
    }

    private var locationFallback: String {
        item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Location needed") : item.location
    }

    private var shortLocationText: String {
        let value = displayLocation.isEmpty ? locationFallback : displayLocation
        let shortened = value.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
        return shortened.isEmpty ? String(localized: "Add place") : shortened
    }

    private var startTimeText: String {
        item.startsAt.map {
            ItineraryDateFormatter.displayClock(
                date: $0,
                timeZoneOffsetSeconds: item.startsAtTimeZoneOffsetSeconds
            )
        } ?? String(localized: "--:--")
    }

    private var endTimeText: String {
        item.endsAt.map {
            ItineraryDateFormatter.displayClock(
                date: $0,
                timeZoneOffsetSeconds: item.endsAtTimeZoneOffsetSeconds ?? item.startsAtTimeZoneOffsetSeconds
            )
        } ?? String(localized: "--:--")
    }

    private var flightRoute: FlightRouteDisplay? {
        guard item.kind == .flight else {
            return nil
        }

        for candidate in [item.location, item.title] {
            let parts = candidate
                .replacingOccurrences(of: "→", with: " to ")
                .components(separatedBy: " to ")
                .map { cleanRouteToken($0) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return FlightRouteDisplay(origin: parts[0], destination: parts[1])
            }
        }

        return nil
    }

    private func cleanRouteToken(_ value: String) -> String {
        let token = value
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let airportCode = token.split(separator: " ").last.map(String.init) ?? token
        return airportCode.uppercased().count == 3 ? airportCode.uppercased() : token
    }

    private func trimmedBody(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 150 ? "\(trimmed.prefix(147))..." : trimmed
    }

    private var itemDurationText: String? {
        guard let startsAt = item.startsAt, let endsAt = item.endsAt else {
            return nil
        }

        if item.kind == .hotel {
            let nights = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: startsAt),
                to: Calendar.current.startOfDay(for: endsAt)
            ).day ?? 0

            guard nights > 0 else {
                return nil
            }

            return nights == 1 ? String(localized: "1 night") : String(localized: "\(nights) nights")
        }

        let minutes = max(0, Int(endsAt.timeIntervalSince(startsAt) / 60))
        guard minutes > 0 else {
            return nil
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }
}

struct FlightRouteDisplay {
    let origin: String
    let destination: String
}

enum MomentDateFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum SourceDocumentPreviewer {
    static func temporaryURL(for sourceFile: SourceDocumentFile) -> URL? {
        guard let data = sourceFile.data else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyaSourceDocuments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeFileName = sourceFile.fileName
                .components(separatedBy: CharacterSet(charactersIn: "/:"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Source document"
            let url = directory.appendingPathComponent(safeFileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

struct MomentMetric: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct AircraftLocationSummary: View {
    let card: ItemEnrichmentCard
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "airplane.departure")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(card.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = card.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MomentLocationRow: View {
    let item: ItineraryItem
    let displayLocation: String
    let route: FlightRouteDisplay?
    let isCopied: Bool
    let onOpenLocation: () -> Void
    let onCopyLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: route == nil ? "mappin.and.ellipse" : "arrow.triangle.swap")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.kind.timelineAccent)
                    .frame(width: 34, height: 34)
                    .background(item.kind.timelineAccent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(route == nil ? String(localized: "Location") : String(localized: "Route"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                    Text(previewTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onOpenLocation) {
                    Label(openTitle, systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(.white)
                        .background(hasLocation ? Color.voyaInk : Color.voyaMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!hasLocation)

                Button(action: onCopyLocation) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .frame(width: 46, height: 42)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!hasLocation)
                .accessibilityLabel(Text(isCopied ? String(localized: "Copied") : String(localized: "Copy location")))
            }
        }
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var previewTitle: String {
        if let route {
            return "\(route.origin) → \(route.destination)"
        }

        let resolved = displayLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty {
            return resolved
        }

        let raw = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? String(localized: "Add a place to unlock route context") : raw
    }

    private var openTitle: LocalizedStringKey {
        LocationLinkResolver.directURL(from: item.location) == nil ? "Open map" : "Open link"
    }

    private var hasLocation: Bool {
        !item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

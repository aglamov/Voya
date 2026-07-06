import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct AssistantCue: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct ItemInsightPanel: View {
    @Environment(\.openURL) private var openURL
    let item: ItineraryItem
    let phase: ItineraryPhase
    let enrichment: ItemEnrichment?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI brief")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("What matters now for this item.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.82)
                        .tint(Color.voyaTeal)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isLoading ? Color.voyaMuted : Color.voyaTeal)
                        .frame(width: 34, height: 34)
                        .background(Color.voyaSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel("Refresh trip intelligence")
            }

            Text(aiBriefText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !guidanceRows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(guidanceRows) { row in
                        if let actionURL = row.actionURL {
                            Button {
                                openURL(actionURL)
                            } label: {
                                AssistantGuidanceRow(row: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            AssistantGuidanceRow(row: row)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var guidanceRows: [AssistantGuidance] {
        var rows: [AssistantGuidance] = []

        if let firstWarning = enrichment?.warnings.first, !firstWarning.isEmpty {
            rows.append(
                AssistantGuidance(
                    title: String(localized: "Attention"),
                    value: firstWarning,
                    detail: nil,
                    symbol: "exclamationmark.triangle.fill",
                    tint: Color.voyaCoral,
                    actionURL: nil
                )
            )
        }

        if let enrichment, !enrichment.actions.isEmpty {
            rows.append(contentsOf: enrichment.actions.prefix(2).map { action in
                AssistantGuidance(
                    title: actionTitle(for: action),
                    value: action.title,
                    detail: action.detail,
                    symbol: symbol(forActionKind: action.kind),
                    tint: tint(forActionKind: action.kind, priority: action.priority),
                    actionURL: action.actionURL
                )
            })
        }

        if rows.count < 2,
           let leg = enrichment?.routeLegs.first {
            rows.append(
                AssistantGuidance(
                    title: String(localized: "Route"),
                    value: routeValue(for: leg),
                    detail: leg.guidance,
                    symbol: "map",
                    tint: Color.voyaTeal,
                    actionURL: leg.mapURL
                )
            )
        }

        if rows.isEmpty,
           let fallback = fallbackRows.first {
            rows.append(fallback)
        }

        return Array(rows.prefix(3))
    }

    private var aiBriefText: String {
        if let warning = enrichment?.warnings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
            return conciseText([primaryNextMove, warning].joined(separator: " "))
        }

        if let enrichment {
            let brief = enrichment.briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !brief.isEmpty {
                return conciseText(plainText(fromMarkdown: brief))
            }

            let sectionText = enrichment.sections
                .prefix(2)
                .map(\.body)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sectionText.isEmpty {
                return conciseText(sectionText)
            }

            let summary = enrichment.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                return conciseText(summary)
            }
        }

        return conciseText([primaryNextMove, primaryNextMoveDetail].joined(separator: " "))
    }

    private func routeValue(for leg: TravelRouteLeg) -> String {
        let endpoints = [leg.origin, leg.destination].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !endpoints.isEmpty {
            return endpoints.joined(separator: " -> ")
        }
        if let bufferMinutes = leg.bufferMinutes {
            return String(localized: "Keep about \(bufferMinutes) min buffer")
        }
        return String(localized: "Route guidance")
    }

    private func actionTitle(for action: TravelAction) -> String {
        switch action.priority {
        case "now": String(localized: "Do now")
        case "soon": String(localized: "Do soon")
        default: String(localized: "Keep in mind")
        }
    }

    private var primaryNextMove: String {
        if item.startsAt == nil {
            return String(localized: "Add the time so Voya can reason about routes, buffers, and weather.")
        }
        switch phase {
        case .current:
            return String(localized: "Focus on this moment now.")
        case .past:
            return String(localized: "This moment is complete.")
        case .future:
            return item.location.isEmpty ? String(localized: "Confirm the place before this gets close.") : String(localized: "Keep the route and timing ready.")
        case .undated:
            return String(localized: "Add timing to unlock better assistance.")
        }
    }

    private var primaryNextMoveDetail: String {
        switch item.kind {
        case .flight:
            return String(localized: "Status, airport timing, route to the airport, and arrival transfer should all collapse into one calm plan.")
        case .hotel:
            return String(localized: "Check-in timing, arrival route, and nearby essentials are the most useful signals here.")
        case .event:
            return String(localized: "Venue context, when to leave, weather, and nearby options matter more than raw booking fields.")
        case .transit:
            return String(localized: "This should behave like a travel leg with buffer, route choice, and fallback guidance.")
        }
    }

    private var fallbackRows: [AssistantGuidance] {
        [
            AssistantGuidance(
                title: String(localized: "Weather"),
                value: String(localized: "Connect forecast"),
                detail: String(localized: "Weather should become advice like what to bring, when to leave, and whether delays are likely."),
                symbol: "cloud.sun",
                tint: Color.voyaSky,
                actionURL: nil
            ),
            AssistantGuidance(
                title: item.kind == .flight ? String(localized: "Live status") : String(localized: "Place context"),
                value: kindFallbackText,
                detail: String(localized: "Provider data will appear here as guidance instead of small dashboard tiles."),
                symbol: item.kind.symbol,
                tint: item.kind.timelineAccent,
                actionURL: nil
            )
        ]
    }

    private var kindFallbackText: String {
        switch item.kind {
        case .flight:
            return String(localized: "FlightAware can power gate, delay, baggage, and airport timing guidance.")
        case .hotel:
            return String(localized: "Hotel context can power arrival, check-in, and nearby essentials.")
        case .event:
            return String(localized: "Event data can power performer, venue, seating, and what-to-expect notes.")
        case .transit:
            return String(localized: "Maps data can power route, buffer, and fallback decisions.")
        }
    }

    private func guidanceTitle(for card: ItemEnrichmentCard) -> String {
        switch card.kind {
        case "weather":
            return String(localized: "Weather decision")
        case "flight":
            return String(localized: "Flight status")
        case "events":
            return String(localized: "Nearby opportunity")
        case "maps":
            return String(localized: "Getting there")
        case "warning":
            return String(localized: "Watch this")
        default:
            return card.title
        }
    }

    private func symbol(for kind: String) -> String {
        switch kind {
        case "weather": "cloud.sun"
        case "flight": "airplane"
        case "events": "ticket"
        case "maps": "map"
        case "warning": "exclamationmark.triangle"
        default: "sparkles"
        }
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "weather": Color.voyaSky
        case "flight": Color.voyaSky
        case "events": Color.voyaCoral
        case "maps": Color.voyaTeal
        case "warning": Color.voyaCoral
        default: Color.voyaGold
        }
    }

    private func symbol(forActionKind kind: String) -> String {
        switch kind {
        case "route": "map"
        case "weather": "cloud.sun"
        case "booking": "doc.text"
        case "flight": "airplane"
        case "event": "ticket"
        case "safety": "exclamationmark.triangle"
        default: "sparkles"
        }
    }

    private func tint(forActionKind kind: String, priority: String) -> Color {
        if priority == "now" {
            return Color.voyaCoral
        }
        switch kind {
        case "route":
            return Color.voyaTeal
        case "weather":
            return Color.voyaSky
        case "flight":
            return Color.voyaSky
        case "event":
            return Color.voyaCoral
        case "safety":
            return Color.voyaCoral
        default:
            return Color.voyaGold
        }
    }

    private func plainText(fromMarkdown value: String) -> String {
        value
            .replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
    }

    private func conciseText(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 420 ? "\(trimmed.prefix(417))..." : trimmed
    }
}

struct AssistantGuidance: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String?
    let symbol: String
    let tint: Color
    let actionURL: URL?
}

struct AssistantGuidanceRow: View {
    let row: AssistantGuidance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(row.tint)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                    if row.actionURL != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(row.tint)
                    }
                }

                Text(row.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = row.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var symbol: String {
        row.actionURL == nil ? row.symbol : "location.north.line.fill"
    }
}

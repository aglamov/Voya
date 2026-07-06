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
                    Text(panelTitle)
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(panelSubtitle)
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

            if let enrichment, hasDetailedBrief(enrichment) {
                DetailedInsightBrief(
                    enrichment: enrichment,
                    fallbackText: aiBriefText,
                    isRussian: isRussian
                )
            } else {
                Text(aiBriefText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !hasRichBrief, !guidanceRows.isEmpty {
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

    private var hasRichBrief: Bool {
        enrichment.map(hasDetailedBrief) ?? false
    }

    private func hasDetailedBrief(_ enrichment: ItemEnrichment) -> Bool {
        !enrichment.sections.isEmpty || !enrichment.briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var aiBriefText: String {
        if let warning = enrichment?.warnings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
            return conciseText([primaryNextMove, warning].joined(separator: " "))
        }

        if let enrichment {
            if let composedBrief = composedBrief(for: enrichment) {
                return composedBrief
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

            let brief = enrichment.briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !brief.isEmpty {
                return conciseText(plainText(fromMarkdown: brief))
            }
        }

        return conciseText([primaryNextMove, primaryNextMoveDetail].joined(separator: " "))
    }

    private var panelTitle: String {
        isRussian ? "Описание" : "Description"
    }

    private var panelSubtitle: String {
        isRussian ? "Коротко, что важно сейчас." : "A short read on what matters now."
    }

    private var isRussian: Bool {
        VoyaAppLocale.currentLanguageCode == "ru"
    }

    private func composedBrief(for enrichment: ItemEnrichment) -> String? {
        let text: String?
        switch item.kind {
        case .flight:
            text = composedFlightBrief(for: enrichment)
        case .hotel:
            text = composedStayBrief(for: enrichment)
        case .event:
            text = composedEventBrief(for: enrichment)
        case .transit:
            text = composedTransitBrief(for: enrichment)
        }

        return text.flatMap { conciseText($0) }
    }

    private func composedFlightBrief(for enrichment: ItemEnrichment) -> String? {
        let flight = firstCard(in: enrichment, kind: "flight", preferredTitles: ["Рейс", "Flight"])
        let gate = firstCard(in: enrichment, kind: "flight", preferredTitles: ["Выход", "Gate"])
        let delay = firstCard(in: enrichment, kind: "flight", preferredTitles: ["Задержка", "Delay"])
        let weather = firstCard(in: enrichment, kind: "weather", preferredTitles: ["Погода", "Weather", "Airport weather", "Погода в аэропорту"])

        var sentences: [String] = []

        if let flight {
            sentences.append(isRussian
                ? "\(cleanCardValue(flight.value))\(cleanCardDetail(flight.detail).map { ": \($0)" } ?? "")."
                : "\(cleanCardValue(flight.value))\(cleanCardDetail(flight.detail).map { ": \($0)" } ?? "").")
        } else {
            sentences.append(isRussian
                ? "\(displayTitle) запланирован на \(item.displayTime)."
                : "\(displayTitle) is scheduled for \(item.displayTime).")
        }

        if let gate {
            let value = cleanCardValue(gate.value)
            let detail = cleanCardDetail(gate.detail)
            if value.localizedCaseInsensitiveContains("не опубликовано") || value.localizedCaseInsensitiveContains("not posted") {
                sentences.append(isRussian
                    ? "Выход пока не опубликован; проверьте его ближе к вылету."
                    : "The gate is not posted yet; check again closer to departure.")
            } else {
                sentences.append(isRussian ? "Выход: \(value)." : "Gate: \(value).")
            }
            if let detail, !detail.localizedCaseInsensitiveContains("final source") {
                sentences.append("\(detail).")
            }
        }

        if let delay {
            sentences.append(isRussian
                ? "По задержкам: \(cleanCardValue(delay.value))."
                : "Delay signal: \(cleanCardValue(delay.value)).")
        }

        if let weather {
            sentences.append(isRussian
                ? "Погода: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "")."
                : "Weather: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "").")
        }

        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private func composedStayBrief(for enrichment: ItemEnrichment) -> String? {
        let route = enrichment.routeLegs.first
        let weather = firstCard(in: enrichment, kind: "weather", preferredTitles: ["Погода", "Weather"])
        let status = firstCard(in: enrichment, kind: "status", preferredTitles: ["Статус", "Status"])

        var sentences = [isRussian
            ? "\(displayTitle): держите адрес, время заезда и маршрут прибытия под рукой."
            : "\(displayTitle): keep the address, check-in window, and arrival route handy."]

        if let route {
            sentences.append(route.guidance)
        }
        if let weather {
            sentences.append(isRussian
                ? "Погода рядом: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "")."
                : "Nearby weather: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "").")
        }
        if let status {
            sentences.append(isRussian ? "Статус: \(cleanCardValue(status.value))." : "Status: \(cleanCardValue(status.value)).")
        }

        return sentences.joined(separator: " ")
    }

    private func composedEventBrief(for enrichment: ItemEnrichment) -> String? {
        let route = enrichment.routeLegs.first
        let weather = firstCard(in: enrichment, kind: "weather", preferredTitles: ["Погода", "Weather"])
        let event = firstCard(in: enrichment, kind: "events", preferredTitles: ["События", "Events"])

        var sentences = [isRussian
            ? "\(displayTitle): проверьте время, место и маршрут до выхода."
            : "\(displayTitle): check the time, venue, and route before leaving."]

        if let route {
            sentences.append(route.guidance)
        }
        if let weather {
            sentences.append(isRussian
                ? "Погода: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "")."
                : "Weather: \(cleanCardValue(weather.value))\(cleanCardDetail(weather.detail).map { ", \($0)" } ?? "").")
        }
        if let event {
            sentences.append(cleanCardLine(event))
        }

        return sentences.joined(separator: " ")
    }

    private func composedTransitBrief(for enrichment: ItemEnrichment) -> String? {
        if let route = enrichment.routeLegs.first {
            return isRussian
                ? "\(route.guidance) \(route.bufferMinutes.map { "Держите запас около \($0) мин." } ?? "")"
                : "\(route.guidance) \(route.bufferMinutes.map { "Keep about \($0) min buffer." } ?? "")"
        }

        return nil
    }

    private var displayTitle: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Untitled item") : title
    }

    private func firstCard(in enrichment: ItemEnrichment, kind: String, preferredTitles: [String]) -> ItemEnrichmentCard? {
        enrichment.cards.first { card in
            preferredTitles.contains { title in
                card.title.localizedCaseInsensitiveContains(title)
            }
        } ?? enrichment.cards.first { $0.kind == kind }
    }

    private func cleanCardLine(_ card: ItemEnrichmentCard) -> String {
        let value = cleanCardValue(card.value)
        if let detail = cleanCardDetail(card.detail) {
            return "\(value): \(detail)."
        }
        return "\(value)."
    }

    private func cleanCardValue(_ value: String) -> String {
        cleanInlineText(value)
    }

    private func cleanCardDetail(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = cleanInlineText(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func cleanInlineText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(status|статус|рейс|flight|weather decision|flight status)\s*[-:]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
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
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
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

struct DetailedInsightBrief: View {
    @Environment(\.openURL) private var openURL
    let enrichment: ItemEnrichment
    let fallbackText: String
    let isRussian: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displaySections) { section in
                DetailedInsightSection(section: section)
            }

            if !displayActions.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label(isRussian ? "Что сделать дальше" : "Next actions", systemImage: "checklist")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayActions) { action in
                            Button {
                                if let actionURL = action.actionURL {
                                    openURL(actionURL)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: actionSymbol(for: action.kind))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(action.priority == "now" ? Color.voyaCoral : Color.voyaTeal)
                                        .frame(width: 22, height: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(action.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Color.voyaInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if !action.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(cleanInlineText(action.detail))
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(Color.voyaMuted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    if action.actionURL != nil {
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Color.voyaTeal)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(action.actionURL == nil)
                        }
                    }
                }
                .padding(14)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var displaySections: [DetailedBriefSection] {
        let sourceSections = enrichment.sections.isEmpty
            ? sectionsFromMarkdown(enrichment.briefMarkdown)
            : enrichment.sections.map {
                DetailedBriefSection(title: $0.title, body: $0.body, kind: $0.kind)
            }

        let filtered = sourceSections.filter { section in
            let title = section.title.lowercased()
            guard !title.contains("assistant stance"),
                  !title.contains("позиция ассистента"),
                  !title.contains("следующие действия"),
                  !title.contains("next actions") else {
                return false
            }
            return !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let unique = deduplicated(filtered)
        if unique.isEmpty {
            return [DetailedBriefSection(title: isRussian ? "Главное" : "Overview", body: fallbackText, kind: "overview")]
        }
        return unique
    }

    private var displayActions: [TravelAction] {
        var seen: Set<String> = []
        return enrichment.actions.filter { action in
            let key = normalizedKey("\(action.title) \(action.detail)")
            return seen.insert(key).inserted
        }
    }

    private func sectionsFromMarkdown(_ markdown: String) -> [DetailedBriefSection] {
        let lines = markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var sections: [DetailedBriefSection] = []
        var currentTitle = isRussian ? "Главное" : "Overview"
        var currentBody: [String] = []

        func flush() {
            let body = currentBody
                .map(cleanMarkdownLine)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(DetailedBriefSection(title: cleanMarkdownLine(currentTitle), body: body, kind: kind(for: currentTitle)))
            }
            currentBody = []
        }

        for line in lines {
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("#") {
                flush()
                currentTitle = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            } else {
                currentBody.append(line)
            }
        }

        flush()
        return sections
    }

    private func deduplicated(_ sections: [DetailedBriefSection]) -> [DetailedBriefSection] {
        var seenTitles: Set<String> = []
        var seenBodies: Set<String> = []

        return sections.compactMap { section in
            let titleKey = normalizedKey(section.title)
            let bodyLines = section.body
                .components(separatedBy: .newlines)
                .map(cleanMarkdownLine)
                .filter { !$0.isEmpty }

            var uniqueLines: [String] = []
            for line in bodyLines {
                let lineKey = normalizedKey(line)
                if seenBodies.insert(lineKey).inserted {
                    uniqueLines.append(line)
                }
            }

            let body = uniqueLines.joined(separator: "\n")
            guard !body.isEmpty else {
                return nil
            }

            if seenTitles.contains(titleKey), seenBodies.contains(normalizedKey(body)) {
                return nil
            }
            seenTitles.insert(titleKey)
            return DetailedBriefSection(title: section.title, body: body, kind: section.kind)
        }
    }

    private func cleanMarkdownLine(_ value: String) -> String {
        cleanInlineText(
            value
                .replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        )
    }

    private func cleanInlineText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalizedKey(_ value: String) -> String {
        cleanInlineText(value)
            .lowercased()
            .replacingOccurrences(of: #"\d{1,2}:\d{2}\s*(am|pm)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func kind(for title: String) -> String {
        let lowercased = title.lowercased()
        if lowercased.contains("route") || lowercased.contains("маршрут") || lowercased.contains("добраться") {
            return "route"
        }
        if lowercased.contains("weather") || lowercased.contains("погода") {
            return "weather"
        }
        if lowercased.contains("flight") || lowercased.contains("рейс") || lowercased.contains("вылет") {
            return "flight"
        }
        if lowercased.contains("risk") || lowercased.contains("риск") {
            return "risk"
        }
        if lowercased.contains("event") || lowercased.contains("событ") {
            return "event"
        }
        return "overview"
    }

    private func actionSymbol(for kind: String) -> String {
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
}

struct DetailedBriefSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let kind: String
}

struct DetailedInsightSection: View {
    let section: DetailedBriefSection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(section.title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(displayLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var displayLines: [String] {
        let lines = section.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines
        }

        let body = section.body
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? [] : [body]
    }

    private var symbol: String {
        switch section.kind {
        case "route": "map"
        case "weather": "cloud.sun"
        case "event": "ticket"
        case "flight": "airplane"
        case "risk": "exclamationmark.triangle"
        case "action": "checklist"
        default: "sparkles"
        }
    }

    private var tint: Color {
        switch section.kind {
        case "risk": Color.voyaCoral
        case "route": Color.voyaTeal
        case "weather": Color.voyaSky
        case "event": Color.voyaCoral
        case "flight": Color.voyaSky
        default: Color.voyaGold
        }
    }
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

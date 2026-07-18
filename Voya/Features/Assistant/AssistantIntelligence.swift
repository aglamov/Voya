import Foundation
import SwiftData
import SwiftUI

struct AssistantIntelligence {
    var journey: AssistantJourneyStage
    var assessment: AssistantTripAssessment
    var alerts: [TravelAlert]
    var weather: AssistantWeatherPreparation
    var environment: [AssistantEnvironmentSignal]
    var recommendations: [AssistantRecommendation]
    var sources: [AssistantSourceSummary]
    var aiAdvice: AssistantAIAdvice?
    var generatedAt: Date
    var isPlaceholder: Bool

    static let empty = AssistantIntelligence(
        journey: .empty,
        assessment: AssistantTripAssessment(
            score: 0,
            title: String(localized: "No active trip"),
            detail: String(localized: "Import a confirmation to activate live trip support."),
            riskLabel: String(localized: "Set"),
            readyCount: 0,
            watchCount: 0,
            actionCount: 0
        ),
        alerts: [],
        weather: .empty,
        environment: [],
        recommendations: [],
        sources: [],
        aiAdvice: nil,
        generatedAt: Date(),
        isPlaceholder: true
    )

    static func loading(trip: Trip?, itinerary: [ItineraryItem]) -> AssistantIntelligence {
        guard let trip else {
            return .empty
        }

        let missingRequiredFields = itinerary.filter {
            $0.startsAt == nil
                || $0.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.location.localizedCaseInsensitiveContains("needed")
        }.count
        let score = itinerary.isEmpty ? 35 : max(55, 82 - missingRequiredFields * 9)

        return AssistantIntelligence(
            journey: AssistantJourneyStage.make(trip: trip, itinerary: itinerary),
            assessment: AssistantTripAssessment(
                score: score,
                title: String(localized: "\(trip.title) support is updating"),
                detail: String(localized: "Refreshing routes, flight status, weather, and readiness signals."),
                riskLabel: String(localized: "Sync"),
                readyCount: 0,
                watchCount: 0,
                actionCount: 0
            ),
            alerts: [],
            weather: AssistantWeatherPreparation(
                title: String(localized: "Weather prep"),
                summary: String(localized: "Checking forecast across upcoming itinerary locations."),
                recommendation: String(localized: "Voya is refreshing trip-wide clothing guidance."),
                items: [],
                severity: .watch,
                sourceDetail: nil
            ),
            environment: [],
            recommendations: [],
            sources: [],
            aiAdvice: nil,
            generatedAt: Date(),
            isPlaceholder: true
        )
    }

    static func cacheKey(
        trip: Trip?,
        itinerary: [ItineraryItem],
        homeLocationName: String,
        homeLocationAddress: String
    ) -> String {
        [
            "assistant-progressive-flight-data-v7",
            trip?.id.uuidString ?? "no-trip",
            trip?.updatedAt.timeIntervalSince1970.description ?? "0",
            itinerary.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: "|"),
            homeLocationName,
            homeLocationAddress
        ].joined(separator: "::")
    }

    func isFresh(for trip: Trip?, now: Date = Date()) -> Bool {
        guard !isPlaceholder else {
            return false
        }

        return now.timeIntervalSince(generatedAt) < Self.freshDuration(for: trip, now: now)
    }

    private static func freshDuration(for trip: Trip?, now: Date) -> TimeInterval {
        guard let startsAt = trip?.startsAt ?? trip?.items.compactMap(\.startsAt).min() else {
            return 15 * 60
        }

        let secondsUntilTrip = startsAt.timeIntervalSince(now)
        if secondsUntilTrip < 24 * 60 * 60 {
            return 10 * 60
        }
        if secondsUntilTrip < 7 * 24 * 60 * 60 {
            return 60 * 60
        }
        return 6 * 60 * 60
    }
}

enum AssistantJourneyPhase: String {
    case planning
    case preparing
    case active
    case between
    case completed

    var symbol: String {
        switch self {
        case .planning: "list.bullet.clipboard"
        case .preparing: "clock.badge.checkmark"
        case .active: "location.fill.viewfinder"
        case .between: "arrow.trianglehead.swap"
        case .completed: "checkmark.seal.fill"
        }
    }
}

struct AssistantJourneyStage {
    var phase: AssistantJourneyPhase
    var phaseLabel: String
    var title: String
    var detail: String
    var currentItemID: UUID?
    var nextItemID: UUID?
    var focusItemID: UUID?
    var itemKind: ItineraryKind?
    var progress: Double
    var completedItems: Int
    var totalItems: Int
    var location: String?
    var status: String?
    var timeSummary: String?
    var timingContext: String?

    static let empty = AssistantJourneyStage(
        phase: .planning,
        phaseLabel: String(localized: "Planning"),
        title: String(localized: "Add a trip to begin"),
        detail: String(localized: "Voya will track each stage once itinerary items are available."),
        currentItemID: nil,
        nextItemID: nil,
        focusItemID: nil,
        itemKind: nil,
        progress: 0,
        completedItems: 0,
        totalItems: 0,
        location: nil,
        status: nil,
        timeSummary: nil,
        timingContext: nil
    )

    static func make(trip: Trip, itinerary: [ItineraryItem], now: Date = Date()) -> AssistantJourneyStage {
        let sorted = itinerary.sorted { lhs, rhs in
            switch (lhs.startsAt, rhs.startsAt) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.createdAt < rhs.createdAt
            }
        }
        let timed = sorted.filter { $0.startsAt != nil }
        let undated = sorted.filter { $0.startsAt == nil }

        guard !timed.isEmpty else {
            let focus = undated.first
            return AssistantJourneyStage(
                phase: .planning,
                phaseLabel: String(localized: "Planning"),
                title: focus?.title ?? String(localized: "Build the itinerary"),
                detail: undated.isEmpty
                    ? String(localized: "Import bookings so Voya can identify the current stage and prepare recommendations.")
                    : String(localized: "Add dates and places to turn saved bookings into a live journey."),
                currentItemID: nil,
                nextItemID: focus?.id,
                focusItemID: focus?.id,
                itemKind: focus?.kind,
                progress: 0,
                completedItems: 0,
                totalItems: sorted.count,
                location: clean(focus?.location),
                status: clean(focus?.status),
                timeSummary: focus?.displayTime,
                timingContext: String(localized: "Timing is still needed")
            )
        }

        let current = timed.last { item in
            guard let start = item.startsAt else { return false }
            return start <= now && effectiveEnd(for: item, start: start) >= now
        }
        let previous = timed.last { item in
            guard let start = item.startsAt else { return false }
            return effectiveEnd(for: item, start: start) < now
        }
        let next = timed.first { ($0.startsAt ?? .distantPast) > now }
        let completed = timed.filter { item in
            guard let start = item.startsAt else { return false }
            return effectiveEnd(for: item, start: start) < now
        }.count

        if let current {
            let nextAfterCurrent = timed.first { ($0.startsAt ?? .distantPast) > (current.startsAt ?? now) && $0.id != current.id }
            return AssistantJourneyStage(
                phase: .active,
                phaseLabel: activeLabel(for: current.kind),
                title: current.title,
                detail: activeGuidance(for: current.kind),
                currentItemID: current.id,
                nextItemID: nextAfterCurrent?.id,
                focusItemID: current.id,
                itemKind: current.kind,
                progress: min(1, (Double(completed) + 0.5) / Double(max(1, timed.count))),
                completedItems: completed,
                totalItems: sorted.count,
                location: clean(current.location),
                status: clean(current.status),
                timeSummary: current.displayTime,
                timingContext: current.endsAt.map { relativeText(for: $0, now: now, prefix: String(localized: "Ends")) }
            )
        }

        if let next {
            let isBeforeTrip = previous == nil
            return AssistantJourneyStage(
                phase: isBeforeTrip ? .preparing : .between,
                phaseLabel: isBeforeTrip ? String(localized: "Before the trip") : String(localized: "Between stages"),
                title: next.title,
                detail: isBeforeTrip
                    ? String(localized: "Prepare documents, route, and timing before this first stage begins.")
                    : String(localized: "Use this window to reset, check the route, and prepare for the next stage."),
                currentItemID: nil,
                nextItemID: next.id,
                focusItemID: next.id,
                itemKind: next.kind,
                progress: Double(completed) / Double(max(1, timed.count)),
                completedItems: completed,
                totalItems: sorted.count,
                location: clean(next.location),
                status: clean(next.status),
                timeSummary: next.displayTime,
                timingContext: next.startsAt.map { relativeText(for: $0, now: now, prefix: String(localized: "Starts")) }
            )
        }

        let last = timed.last
        return AssistantJourneyStage(
            phase: .completed,
            phaseLabel: String(localized: "Trip complete"),
            title: trip.destination?.nilIfEmpty ?? trip.title,
            detail: String(localized: "The saved itinerary is complete. Keep documents available until every booking is settled."),
            currentItemID: nil,
            nextItemID: undated.first?.id,
            focusItemID: undated.first?.id ?? last?.id,
            itemKind: undated.first?.kind ?? last?.kind,
            progress: 1,
            completedItems: completed,
            totalItems: sorted.count,
            location: clean(undated.first?.location ?? last?.location),
            status: clean(undated.first?.status ?? last?.status),
            timeSummary: undated.first?.displayTime ?? last?.displayTime,
            timingContext: undated.isEmpty ? String(localized: "All timed stages finished") : String(localized: "Untimed items still need review")
        )
    }

    private static func effectiveEnd(for item: ItineraryItem, start: Date) -> Date {
        if let endsAt = item.endsAt { return endsAt }
        let duration: TimeInterval
        switch item.kind {
        case .flight: duration = 6 * 60 * 60
        case .hotel: duration = 12 * 60 * 60
        case .event: duration = 3 * 60 * 60
        case .transit: duration = 4 * 60 * 60
        }
        return start.addingTimeInterval(duration)
    }

    private static func activeLabel(for kind: ItineraryKind) -> String {
        switch kind {
        case .flight: String(localized: "Flight in progress")
        case .hotel: String(localized: "Stay in progress")
        case .event: String(localized: "Event in progress")
        case .transit: String(localized: "On the move")
        }
    }

    private static func activeGuidance(for kind: ItineraryKind) -> String {
        switch kind {
        case .flight: String(localized: "Keep live status, arrival details, baggage, and the onward route close at hand.")
        case .hotel: String(localized: "Keep the address, check-out time, local weather, and the next route visible.")
        case .event: String(localized: "Keep entry details, venue guidance, and the route to the next stage ready.")
        case .transit: String(localized: "Watch the line, stops, arrival time, and any connection after this transfer.")
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              !value.localizedCaseInsensitiveContains("needed"),
              !value.localizedCaseInsensitiveContains("unknown") else {
            return nil
        }
        return value
    }

    private static func relativeText(for date: Date, now: Date, prefix: String) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(prefix) \(formatter.localizedString(for: date, relativeTo: now))"
    }
}

enum AssistantEnvironmentKind: Equatable {
    case place
    case weather
    case route
    case event
    case flight
    case warning

    var symbol: String {
        switch self {
        case .place: "mappin.and.ellipse"
        case .weather: "cloud.sun.fill"
        case .route: "arrow.triangle.turn.up.right.diamond.fill"
        case .event: "ticket.fill"
        case .flight: "airplane.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

struct AssistantEnvironmentSignal: Identifiable {
    var id: String
    var kind: AssistantEnvironmentKind
    var title: String
    var value: String
    var detail: String?
    var severity: AlertSeverity
    var actionURL: URL?
    var itemID: UUID?
}

enum AssistantRecommendationUrgency: String {
    case now
    case soon
    case later

    var label: String {
        switch self {
        case .now: String(localized: "Now")
        case .soon: String(localized: "Soon")
        case .later: String(localized: "Later")
        }
    }
}

struct AssistantRecommendation: Identifiable {
    var id: String
    var urgency: AssistantRecommendationUrgency
    var title: String
    var detail: String
    var symbol: String
    var itemID: UUID?
}

func assistantSemanticTokens(_ value: String) -> Set<String> {
    let ignored: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "your", "you", "into", "before", "after",
        "для", "или", "это", "этот", "ваш", "перед", "после", "нужно", "надо", "будет"
    ]
    return Set(value.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 2 && !ignored.contains($0) }
        .map { token in
            if token.hasPrefix("tim") || token.hasPrefix("врем") { return "time" }
            if token.hasPrefix("place") || token.hasPrefix("address") || token.hasPrefix("location") || token.hasPrefix("мест") || token.hasPrefix("адрес") { return "place" }
            if token.hasPrefix("route") || token.hasPrefix("transfer") || token.hasPrefix("leave") || token.hasPrefix("маршрут") || token.hasPrefix("трансфер") || token.hasPrefix("вые") { return "route" }
            if token.hasPrefix("weather") || token.hasPrefix("forecast") || token.hasPrefix("погод") || token.hasPrefix("прогноз") { return "weather" }
            if token.hasPrefix("checkin") || token == "check" || token.hasPrefix("регистрац") { return "checkin" }
            if token.hasPrefix("board") || token.hasPrefix("посадоч") { return "boarding" }
            if token.hasPrefix("book") || token.hasPrefix("reserv") || token.hasPrefix("брон") { return "booking" }
            if token.hasPrefix("accommod") || token.hasPrefix("hotel") || token.hasPrefix("sleep") || token.hasPrefix("отел") || token.hasPrefix("ноч") { return "stay" }
            if token.hasPrefix("flight") || token.hasPrefix("aircraft") || token.hasPrefix("рейс") || token.hasPrefix("самолет") || token.hasPrefix("самолёт") { return "flight" }
            if token.hasPrefix("pollen") || token.hasPrefix("пыльц") { return "pollen" }
            return token
        })
}

func assistantMeaningfullyMatches(_ lhs: String, _ rhs: String) -> Bool {
    let left = assistantSemanticTokens(lhs)
    let right = assistantSemanticTokens(rhs)
    guard !left.isEmpty, !right.isEmpty else {
        return lhs.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
            rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
    }
    let overlap = left.intersection(right).count
    let ratio = Double(overlap) / Double(max(1, min(left.count, right.count)))
    let concepts: Set<String> = ["time", "place", "route", "weather", "checkin", "boarding", "booking", "stay", "flight", "pollen"]
    let sharedConcept = !left.intersection(right).intersection(concepts).isEmpty
    return ratio >= 0.58 || (sharedConcept && overlap >= 2)
}

struct AssistantTripAssessment {
    var score: Int
    var title: String
    var detail: String
    var riskLabel: String
    var readyCount: Int
    var watchCount: Int
    var actionCount: Int

    var scoreText: String {
        score > 0 ? "\(score)" : "--"
    }

    var tone: AlertSeverity {
        if actionCount > 0 || score < 55 {
            return .action
        }
        if watchCount > 0 || score < 78 {
            return .watch
        }
        return .calm
    }
}

struct AssistantWeatherPreparation {
    var title: String
    var summary: String
    var recommendation: String
    var items: [String]
    var severity: AlertSeverity
    var sourceDetail: String?

    static let empty = AssistantWeatherPreparation(
        title: String(localized: "Weather prep"),
        summary: String(localized: "Forecast will appear when itinerary locations are available."),
        recommendation: String(localized: "Add hotel, venue, or airport locations for trip-wide clothing guidance."),
        items: [],
        severity: .watch,
        sourceDetail: nil
    )
}

struct AssistantSourceSummary: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var count: Int
    var severity: AlertSeverity
}

enum AssistantProcessingStage: Int, CaseIterable {
    case local
    case flights
    case routes
    case weather
    case aiReview
    case complete
}

@MainActor
struct AssistantIntelligenceBuilder {
    let store: VoyaStore

    func build(
        trip: Trip?,
        itinerary: [ItineraryItem],
        homeLocationName: String,
        homeLocationAddress: String,
        modelContext: ModelContext?,
        onProgress: ((AssistantProcessingStage) -> Void)? = nil,
        onFlightInsights: (([TravelAlert]) -> Void)? = nil
    ) async -> AssistantIntelligence {
        guard let trip else {
            return .empty
        }

        onProgress?(.local)
        let journey = AssistantJourneyStage.make(trip: trip, itinerary: itinerary)
        var alerts: [TravelAlert] = []
        var sourceCounts: [String: Int] = [:]
        var sourceSeverities: [String: AlertSeverity] = [:]
        var weatherCards: [ItemEnrichmentCard] = []
        var readySignals = 0
        var watchSignals = 0
        var actionSignals = 0

        func append(_ alert: TravelAlert) {
            alerts.append(alert)
            if let source = alert.sourceTitle {
                sourceCounts[source, default: 0] += 1
                sourceSeverities[source] = maxSeverity(sourceSeverities[source], alert.severity)
            }
            switch alert.severity {
            case .calm:
                readySignals += 1
            case .watch:
                watchSignals += 1
            case .action:
                actionSignals += 1
            }
        }

        if itinerary.isEmpty {
            append(
                TravelAlert(
                    id: "itinerary-empty",
                    title: String(localized: "Itinerary needs items"),
                    message: String(localized: "Import or add bookings so Voya can reason about timing, routes, weather, and documents."),
                    severity: .action,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Trip has no saved itinerary items.")
                )
            )
        }

        for alert in localReadinessAlerts(trip: trip, itinerary: itinerary) {
            append(alert)
        }

        onProgress?(.flights)
        let flightAlerts = await flightStatusAlerts(for: itinerary, modelContext: modelContext)
        for alert in flightAlerts {
            append(alert)
        }
        onFlightInsights?(
            flightAlerts.filter {
                $0.id.hasPrefix("flight-reliability-")
                    || $0.id.hasPrefix("flight-plane-")
                    || $0.id.hasPrefix("flight-status-pending-")
            }
        )

        onProgress?(.routes)
        let transferAlerts = await mobilityAlerts(
            trip: trip,
            itinerary: itinerary,
            homeLocationName: homeLocationName,
            homeLocationAddress: homeLocationAddress
        )
        for alert in transferAlerts {
            append(alert)
        }

        onProgress?(.weather)
        weatherCards = await loadWeatherCards(
            itinerary: itinerary,
            modelContext: modelContext
        )
        let weather = weatherPreparation(from: weatherCards)
        if !weatherCards.isEmpty {
            append(
                TravelAlert(
                    id: "weather-trip-prep",
                    title: weather.title,
                    message: weather.summary,
                    severity: weather.severity,
                    sourceTitle: String(localized: "Weather enrichment"),
                    sourceDetail: weather.sourceDetail
                )
            )
        }

        let sortedAlerts = alerts
            .sorted { lhs, rhs in
                if lhs.severity.priority != rhs.severity.priority {
                    return lhs.severity.priority > rhs.severity.priority
                }
                return lhs.title < rhs.title
            }

        var assessment = tripAssessment(
            trip: trip,
            itinerary: itinerary,
            alerts: sortedAlerts,
            readySignals: readySignals,
            watchSignals: watchSignals,
            actionSignals: actionSignals
        )

        let sources = sourceCounts
            .map { source, count in
                AssistantSourceSummary(
                    title: source,
                    detail: sourceDetail(for: source),
                    count: count,
                    severity: sourceSeverities[source] ?? .calm
                )
            }
            .sorted { lhs, rhs in
                if lhs.severity.priority != rhs.severity.priority {
                    return lhs.severity.priority > rhs.severity.priority
                }
                return lhs.title < rhs.title
            }

        var finalWeather = weather
        let environment = environmentSignals(
            journey: journey,
            itinerary: itinerary,
            weatherCards: weatherCards,
            alerts: sortedAlerts
        )
        onProgress?(.aiReview)
        let aiAdvice = await assistantAIAdvice(
            trip: trip,
            itinerary: itinerary,
            assessment: assessment,
            journey: journey,
            alerts: sortedAlerts,
            weather: finalWeather,
            environment: environment,
            sources: sources,
            question: nil,
            conversation: []
        )

        if let aiAdvice, aiAdvice.isReliableEnoughToOverrideFacts {
            assessment.title = aiAdvice.assessmentTitle
            assessment.detail = aiAdvice.assessmentDetail
            finalWeather.recommendation = aiAdvice.packingAdvice
        }

        onProgress?(.complete)
        return AssistantIntelligence(
            journey: journey,
            assessment: assessment,
            alerts: sortedAlerts,
            weather: finalWeather,
            environment: environment,
            recommendations: recommendations(
                journey: journey,
                itinerary: itinerary,
                alerts: sortedAlerts,
                aiAdvice: aiAdvice
            ),
            sources: sources,
            aiAdvice: aiAdvice,
            generatedAt: Date(),
            isPlaceholder: false
        )
    }

    func localSnapshot(trip: Trip?, itinerary: [ItineraryItem]) -> AssistantIntelligence {
        guard let trip else { return .empty }
        let alerts = localReadinessAlerts(trip: trip, itinerary: itinerary)
        let ready = alerts.filter { $0.severity == .calm }.count
        let watch = alerts.filter { $0.severity == .watch }.count
        let action = alerts.filter { $0.severity == .action }.count
        let assessment = tripAssessment(
            trip: trip,
            itinerary: itinerary,
            alerts: alerts,
            readySignals: ready,
            watchSignals: watch,
            actionSignals: action
        )
        let journey = AssistantJourneyStage.make(trip: trip, itinerary: itinerary)

        return AssistantIntelligence(
            journey: journey,
            assessment: assessment,
            alerts: alerts,
            weather: .empty,
            environment: environmentSignals(
                journey: journey,
                itinerary: itinerary,
                weatherCards: [],
                alerts: alerts
            ),
            recommendations: recommendations(
                journey: journey,
                itinerary: itinerary,
                alerts: alerts,
                aiAdvice: nil
            ),
            sources: [],
            aiAdvice: nil,
            generatedAt: Date(),
            isPlaceholder: true
        )
    }

    private func localReadinessAlerts(trip: Trip, itinerary: [ItineraryItem]) -> [TravelAlert] {
        var alerts: [TravelAlert] = []
        let now = Date()

        let missingTimeCount = itinerary.filter { $0.startsAt == nil }.count
        if missingTimeCount > 0 {
            alerts.append(
                TravelAlert(
                    id: "local-missing-time",
                    title: String(localized: "\(missingTimeCount) items need time"),
                    message: String(localized: "Add start times so Voya can calculate route buffers, weather windows, and reminders."),
                    severity: .action,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Calculated from saved itinerary fields.")
                )
            )
        }

        let missingPlaceCount = itinerary.filter {
            $0.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.location.localizedCaseInsensitiveContains("needed")
        }.count
        if missingPlaceCount > 0 {
            alerts.append(
                TravelAlert(
                    id: "local-missing-place",
                    title: String(localized: "\(missingPlaceCount) places need confirmation"),
                    message: String(localized: "Add exact addresses, airports, hotels, or venues before travel day."),
                    severity: .action,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Calculated from saved itinerary fields.")
                )
            )
        }

        let uncoveredNights = uncoveredNightCount(trip: trip, itinerary: itinerary)
        if uncoveredNights > 0 {
            alerts.append(
                TravelAlert(
                    id: "local-accommodation-missing",
                    title: String(localized: "No place to stay"),
                    message: uncoveredNights == 1
                        ? String(localized: "There is one overnight stay in this trip without accommodation. Decide where you will sleep and add the booking to the itinerary.")
                        : String(localized: "There are \(uncoveredNights) nights in this trip without accommodation. Decide where you will sleep and add the bookings to the itinerary."),
                    severity: .action,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Compared overnight trip dates with saved hotel stays.")
                )
            )
        }

        let checkInActions = itinerary.compactMap { item -> FlightCheckInAction? in
            guard store.boardingPassDocument(for: item) == nil else {
                return nil
            }
            return FlightCheckInAction(item: item, now: now)
        }
        for action in checkInActions.prefix(2) {
            alerts.append(
                TravelAlert(
                    id: "check-in-\(action.id.uuidString)",
                    title: String(localized: "Check in for \(action.flightNumber)"),
                    message: action.confirmationCode == nil
                        ? String(localized: "Online check-in should be open. Have PNR and passenger last name ready.")
                        : String(localized: "Online check-in should be open. The booking reference is saved locally; have the passenger last name ready."),
                    severity: .watch,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Calculated from flight time and booking fields.")
                )
            )
        }

        for item in itinerary where item.kind == .flight {
            guard let startsAt = item.startsAt,
                  startsAt > now,
                  now >= startsAt.addingTimeInterval(-24 * 60 * 60),
                  store.boardingPassDocument(for: item) == nil,
                  !FlightCheckInAction.isAlreadyCheckedIn(item) else {
                continue
            }

            alerts.append(
                TravelAlert(
                    id: "boarding-pass-\(item.id.uuidString)",
                    title: String(localized: "Boarding pass missing"),
                    message: String(localized: "Attach the boarding pass for \(flightDisplayTitle(item)) so the QR or barcode is one tap away."),
                    severity: .watch,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Calculated from flight time and attached documents.")
                )
            )
        }

        if itinerary.contains(where: { $0.kind == .flight }) {
            alerts.append(
                TravelAlert(
                    id: "local-flight-source",
                    title: String(localized: "Booking source saved"),
                    message: String(localized: "Voya can keep flight, check-in, and source documents together for support moments."),
                    severity: .calm,
                    sourceTitle: String(localized: "Local itinerary"),
                    sourceDetail: String(localized: "Calculated from saved trip documents and flight items.")
                )
            )
        }

        return alerts
    }

    private func uncoveredNightCount(trip: Trip, itinerary: [ItineraryItem]) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let startsAt = itinerary.compactMap(\.startsAt).min() ?? trip.startsAt
        let endsAt = itinerary.compactMap { $0.endsAt ?? $0.startsAt }.max() ?? trip.endsAt
        guard let startsAt, let endsAt, endsAt > startsAt else {
            return 0
        }

        let hotels = itinerary.filter { $0.kind == .hotel && $0.startsAt != nil }
        var day = calendar.startOfDay(for: startsAt)
        var uncovered = 0

        while let checkpoint = calendar.date(byAdding: .hour, value: 3, to: day), checkpoint < endsAt {
            if checkpoint > startsAt {
                let isCovered = hotels.contains { hotel in
                    guard let checkIn = hotel.startsAt else { return false }
                    let checkOut = hotel.endsAt
                        ?? calendar.date(byAdding: .day, value: 1, to: checkIn)
                        ?? checkIn
                    return checkIn <= checkpoint && checkOut >= checkpoint
                }
                if !isCovered {
                    uncovered += 1
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return uncovered
    }

    private func flightStatusAlerts(for itinerary: [ItineraryItem], modelContext: ModelContext?) async -> [TravelAlert] {
        var alerts: [TravelAlert] = []
        let service = VercelFlightLookupService()
        let upcomingFlights = itinerary
            .filter { $0.kind == .flight && ItineraryPhase(item: $0) != .past }
            .prefix(4)

        for item in upcomingFlights {
            guard let flightNumber = item.resolvedFlightNumber else {
                alerts.append(
                    TravelAlert(
                        id: "flight-number-needed-\(item.id.uuidString)",
                        title: String(localized: "Flight number needed"),
                        message: String(localized: "Add the airline flight number to refresh live status, terminal, gate, and baggage details."),
                        severity: .action,
                        sourceTitle: String(localized: "Flight lookup"),
                        sourceDetail: String(localized: "No parseable flight number in saved itinerary.")
                    )
                )
                continue
            }

            let route = store.airportRouteCodes(in: item.location)
            do {
                let response: FlightLookupResponse
                if let cached = FlightLookupCache.freshCachedResponse(for: item) {
                    response = cached
                } else {
                    do {
                        response = try await service.lookup(
                            flightNumber: flightNumber,
                            date: item.startsAt,
                            dateTimeZoneOffsetSeconds: item.startsAtTimeZoneOffsetSeconds,
                            originAirport: route?.origin,
                            destinationAirport: route?.destination
                        )
                        FlightLookupCache.store(response, for: item)
                        try? modelContext?.save()
                    } catch {
                        guard let stale = FlightLookupCache.cachedResponse(for: item) else {
                            throw error
                        }
                        response = stale
                    }
                }

                if let reliability = response.reliability ?? response.intelligence?.history {
                    alerts.append(flightReliabilityAlert(for: item, flightNumber: flightNumber, reliability: reliability))
                } else {
                    alerts.append(flightReliabilityUnavailableAlert(for: item, flightNumber: flightNumber))
                }

                if let plane = response.plane {
                    alerts.append(flightPlaneAlert(for: item, flightNumber: flightNumber, plane: plane))
                }

                guard let candidate = response.candidate else {
                    alerts.append(flightStatusUnavailableAlert(for: item, flightNumber: flightNumber))
                    continue
                }

                alerts.append(flightAlert(for: item, candidate: candidate))
            } catch {
                alerts.append(flightStatusUnavailableAlert(for: item, flightNumber: flightNumber))
            }
        }

        return alerts
    }

    private func flightStatusUnavailableAlert(for item: ItineraryItem, flightNumber: String) -> TravelAlert {
        let secondsUntilDeparture = item.startsAt?.timeIntervalSinceNow ?? 0
        let isNearDeparture = secondsUntilDeparture <= 48 * 60 * 60

        return TravelAlert(
            id: "flight-status-pending-\(item.id.uuidString)",
            title: isNearDeparture
                ? String(localized: "Check \(flightNumber) closer to departure")
                : String(localized: "Live status for \(flightNumber) will appear later"),
            message: isNearDeparture
                ? String(localized: "The live provider has not confirmed this flight yet. Check the airline before leaving for the airport; aircraft assignment and position will appear here when available.")
                : String(localized: "The flight is saved. Live terminal, gate, delay, aircraft assignment, and position normally become available closer to departure."),
            severity: isNearDeparture ? .watch : .calm,
            sourceTitle: String(localized: "Flight lookup"),
            sourceDetail: String(localized: "Live provider data is not available for this flight window yet.")
        )
    }

    private func flightAlert(for item: ItineraryItem, candidate: FlightLookupCandidate) -> TravelAlert {
        let gate = candidate.departureGate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let terminal = candidate.departureTerminal?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let baggage = candidate.baggageClaim?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let status = candidate.statusText
        let statusLower = status.lowercased()
        let severity: AlertSeverity

        if statusLower.contains("cancel") || statusLower.contains("divert") {
            severity = .action
        } else if statusLower.contains("delay") || gate == nil {
            severity = .watch
        } else {
            severity = .calm
        }

        let title: String
        if let gate {
            title = String(localized: "Gate \(gate) for \(candidate.flightNumber)")
        } else {
            title = String(localized: "Gate not posted for \(candidate.flightNumber)")
        }

        let details = [
            status,
            terminal.map { String(localized: "Terminal \($0)") },
            baggage.map { String(localized: "Bags \($0)") },
            candidate.dataMode.map { String(localized: "Mode \($0)") }
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }

        return TravelAlert(
            id: "flight-status-\(item.id.uuidString)",
            title: title,
            message: details.isEmpty ? String(localized: "Flight provider verified this itinerary item.") : details.joined(separator: " · "),
            severity: severity,
            sourceTitle: String(localized: "Flight lookup"),
            sourceDetail: candidate.confidence.map {
                String(localized: "\(Int($0 * 100))% provider match confidence.")
            } ?? String(localized: "Live flight candidate returned by provider.")
        )
    }

    private func flightPlaneAlert(for item: ItineraryItem, flightNumber: String, plane: FlightPlaneContext) -> TravelAlert {
        let severity: AlertSeverity
        switch plane.state {
        case "current_airborne", "inbound_airborne", "inbound_scheduled":
            severity = .watch
        case "unknown":
            severity = .watch
        default:
            severity = .calm
        }

        let aircraft = [
            plane.aircraftRegistration?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            plane.aircraftType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ].compactMap { $0 }.joined(separator: " · ")

        let message = [planeLocationDescription(plane), aircraft.nilIfEmpty]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " · ")

        let mapURL = plane.position.flatMap { position in
            URL(string: "https://maps.apple.com/?ll=\(position.lat),\(position.lon)")
        }

        return TravelAlert(
            id: "flight-plane-\(item.id.uuidString)",
            title: String(localized: "\(flightNumber): \(planeHeadline(plane))"),
            message: message.isEmpty ? String(localized: "Aircraft assignment and live position will appear closer to departure.") : message,
            severity: severity,
            sourceTitle: String(localized: "Flight lookup"),
            sourceDetail: String(localized: "\(Int(plane.confidence * 100))% aircraft context confidence."),
            actionURL: mapURL
        )
    }

    private func flightReliabilityAlert(
        for item: ItineraryItem,
        flightNumber: String,
        reliability: FlightReliabilityStats
    ) -> TravelAlert {
        let delayedPercent = reliability.delayed15Rate.map { Int(($0 * 100).rounded()) }
        var details: [String] = [String(localized: "Based on \(reliability.sampleSize) recent flights")]
        if let delayedPercent {
            details.append(String(localized: "\(delayedPercent)% were delayed by 15 minutes or more"))
        }
        if let average = reliability.averageArrivalDelayMinutes {
            details.append(String(localized: "Average arrival delay \(Int(average.rounded())) min"))
        } else if let average = reliability.averageDepartureDelayMinutes {
            details.append(String(localized: "Average departure delay \(Int(average.rounded())) min"))
        }
        if reliability.cancelledCount > 0 {
            details.append(String(localized: "\(reliability.cancelledCount) cancelled"))
        }

        let severity: AlertSeverity = (reliability.delayed15Rate ?? 0) >= 0.35 || reliability.cancelledCount > 0
            ? .watch
            : .calm

        return TravelAlert(
            id: "flight-reliability-\(item.id.uuidString)",
            title: String(localized: "\(flightNumber): delay history"),
            message: details.joined(separator: " · "),
            severity: severity,
            sourceTitle: String(localized: "Flight history"),
            sourceDetail: String(localized: "Calculated from recent flights with the same flight number and available route match.")
        )
    }

    private func flightReliabilityUnavailableAlert(for item: ItineraryItem, flightNumber: String) -> TravelAlert {
        TravelAlert(
            id: "flight-reliability-\(item.id.uuidString)",
            title: String(localized: "\(flightNumber): not enough history yet"),
            message: String(localized: "FlightAware did not return enough recent flights with this number and route to calculate a meaningful delay rate."),
            severity: .calm,
            sourceTitle: String(localized: "Flight history"),
            sourceDetail: String(localized: "Historical data is requested independently of the future live flight status.")
        )
    }

    private func planeHeadline(_ plane: FlightPlaneContext) -> String {
        switch plane.state {
        case "current_airborne": return String(localized: "Your flight is airborne")
        case "current_arrived": return String(localized: "Your flight has arrived")
        case "inbound_airborne": return String(localized: "The aircraft is flying to your departure airport")
        case "inbound_arrived": return String(localized: "The aircraft has arrived for your flight")
        case "inbound_scheduled": return String(localized: "The aircraft has a flight before yours")
        case "assigned": return String(localized: "Aircraft assigned")
        case "not_assigned": return String(localized: "Aircraft not assigned yet")
        default: return String(localized: "Aircraft position is not available yet")
        }
    }

    private func planeLocationDescription(_ plane: FlightPlaneContext) -> String {
        var details: [String] = []
        if let inbound = plane.inboundFlight {
            let route = [inbound.originAirport, inbound.destinationAirport]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: " → ")
            if !route.isEmpty {
                details.append(String(localized: "Previous segment: \(route)"))
            }
        }
        if let progress = plane.progressPercent {
            details.append(String(localized: "\(Int(progress.rounded()))% of the flight completed"))
        }
        if let position = plane.position {
            if let altitude = position.altitudeFeet {
                details.append(String(localized: "Altitude \(Int(altitude.rounded())) ft"))
            }
            details.append(String(localized: "Live position is available on the map"))
        } else {
            details.append(String(localized: "Live coordinates are not available yet"))
        }
        return details.joined(separator: " · ")
    }

    private func mobilityAlerts(
        trip: Trip,
        itinerary: [ItineraryItem],
        homeLocationName: String,
        homeLocationAddress: String
    ) async -> [TravelAlert] {
        let contexts = transferContexts(
            trip: trip,
            itinerary: itinerary,
            homeLocationName: homeLocationName,
            homeLocationAddress: homeLocationAddress
        )
        let service = VercelMobilityService()
        var alerts: [TravelAlert] = []

        for context in contexts.prefix(5) {
            do {
                let plan: MobilityPlan
                if let cached = MobilityPlanCache.freshPlan(for: context) {
                    plan = cached
                } else {
                    plan = try await service.planTransfer(context: context)
                    MobilityPlanCache.store(plan, for: context)
                }
                guard let option = plan.defaultOption else {
                    alerts.append(
                        TravelAlert(
                            id: "route-empty-\(context.id)",
                            title: String(localized: "Route needs review"),
                            message: String(localized: "Routing provider returned no route options for \(shortPlace(context.destination))."),
                            severity: .watch,
                            sourceTitle: String(localized: "Mobility plan"),
                            sourceDetail: String(localized: "Provider \(plan.provider) returned an empty option set.")
                        )
                    )
                    continue
                }

                alerts.append(transferAlert(context: context, plan: plan, option: option))
            } catch {
                alerts.append(
                    TravelAlert(
                        id: "route-unavailable-\(context.id)",
                        title: String(localized: "Route timing unavailable"),
                        message: String(localized: "Could not refresh the route from \(shortPlace(context.origin)) to \(shortPlace(context.destination))."),
                        severity: .watch,
                        sourceTitle: String(localized: "Mobility plan"),
                        sourceDetail: String(localized: "Request to /api/mobility failed.")
                    )
                )
            }
        }

        return alerts
    }

    private func transferContexts(
        trip: Trip,
        itinerary: [ItineraryItem],
        homeLocationName: String,
        homeLocationAddress: String
    ) -> [MobilityTransferContext] {
        var contexts: [MobilityTransferContext] = []
        guard !itinerary.isEmpty else { return contexts }

        if let first = itinerary.first,
           let context = VercelMobilityService.startTransferContext(
                for: trip,
                firstItem: first,
                defaultHomeAddress: homeLocationAddress,
                defaultHomeName: homeLocationName
           ) {
            contexts.append(context)
        }

        for index in itinerary.indices where index + 1 < itinerary.count {
            if let context = VercelMobilityService.transferContext(from: itinerary[index], to: itinerary[index + 1]) {
                contexts.append(context)
            }
        }

        if let last = itinerary.last,
           let context = VercelMobilityService.endTransferContext(
                for: trip,
                lastItem: last,
                defaultHomeAddress: homeLocationAddress,
                defaultHomeName: homeLocationName
           ) {
            contexts.append(context)
        }

        return contexts.map { context in
            guard let routeOverride = trip.transferRouteOverride(for: context.id) else {
                return context
            }

            var adjustedContext = context
            adjustedContext.origin = routeOverride.origin
            adjustedContext.destination = routeOverride.destination
            return adjustedContext
        }
    }

    private func transferAlert(context: MobilityTransferContext, plan: MobilityPlan, option: MobilityRouteOption) -> TravelAlert {
        let leaveDate = routeDepartureDate(for: option)
        let leaveText = leaveDate.map { MobilityDateFormatter.time.string(from: $0) }
            ?? option.leaveBy
            ?? option.departureTime
        let durationText = option.durationMinutes.map { String(localized: "\($0) min") } ?? String(localized: "Timing ready")
        let bufferText = option.bufferMinutes > 0 ? String(localized: " + \(option.bufferMinutes) min buffer") : ""
        let title = leaveText.map { String(localized: "Leave by \($0)") }
            ?? String(localized: "Route to \(shortPlace(context.destination)) ready")
        let message = [
            option.mode.displayName,
            durationText + bufferText,
            option.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ].compactMap { $0 }.joined(separator: " · ")
        let severity: AlertSeverity = option.reliability.localizedCaseInsensitiveContains("low") ? .watch : .calm

        return TravelAlert(
            id: "route-\(context.id)",
            title: title,
            message: message,
            severity: severity,
            sourceTitle: String(localized: "Mobility plan"),
            sourceDetail: String(localized: "\(plan.provider) route from \(shortPlace(context.origin)) to \(shortPlace(context.destination)).")
        )
    }

    private func loadWeatherCards(
        itinerary: [ItineraryItem],
        modelContext: ModelContext?
    ) async -> [ItemEnrichmentCard] {
        let enrichable = itinerary
            .filter {
                !$0.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.startsAt != nil
                    && ItineraryPhase(item: $0) != .past
            }
            .prefix(5)

        var cards: [ItemEnrichmentCard] = []
        let enricher = VercelItemEnricher()

        for item in enrichable {
            do {
                let enrichment = try await enricher.enrich(item: item, modelContext: modelContext)
                cards.append(
                    contentsOf: enrichment.cards.filter {
                        $0.kind == "weather"
                            || $0.kind == "warning"
                            || $0.title.localizedCaseInsensitiveContains("weather")
                    }
                )
            } catch {
                cards.append(
                    ItemEnrichmentCard(
                        title: String(localized: "Weather"),
                        value: String(localized: "Unavailable"),
                        detail: String(localized: "Forecast provider could not be reached for \(item.title)."),
                        actionURL: nil,
                        kind: "warning"
                    )
                )
            }
        }

        return cards
    }

    private func weatherPreparation(from cards: [ItemEnrichmentCard]) -> AssistantWeatherPreparation {
        guard !cards.isEmpty else {
            return .empty
        }

        let unavailable = cards.filter {
            $0.value.localizedCaseInsensitiveContains("unavailable")
                || $0.value.localizedCaseInsensitiveContains("not connected")
                || $0.value.localizedCaseInsensitiveContains("location needed")
        }
        let warningCount = cards.filter { $0.kind == "warning" }.count
        let temperatures = cards.compactMap { temperatureCelsius(from: "\($0.value) \($0.detail ?? "")") }
        let coldest = temperatures.min()
        let warmest = temperatures.max()
        let combinedText = cards.map { "\($0.value) \($0.detail ?? "")" }.joined(separator: " ").lowercased()

        var items: [String] = []
        if combinedText.contains("rain") || combinedText.contains("shower") || combinedText.contains("storm") {
            items.append(String(localized: "Pack a compact umbrella or rain shell."))
        }
        if combinedText.contains("snow") || combinedText.contains("ice") {
            items.append(String(localized: "Use warm layers and shoes with grip."))
        }
        if combinedText.contains("wind") {
            items.append(String(localized: "Bring a wind layer for transfers and exposed stops."))
        }
        if let coldest, coldest <= 8 {
            items.append(String(localized: "Pack a warm outer layer; lowest checked temperature is about \(coldest) C."))
        }
        if let warmest, warmest >= 26 {
            items.append(String(localized: "Pack breathable clothes, sunglasses, and hydration room; highest checked temperature is about \(warmest) C."))
        }
        if items.isEmpty {
            items.append(String(localized: "Pack comfortable layers that can handle airport, transit, and evening temperature shifts."))
        }

        let range: String
        if let coldest, let warmest, coldest != warmest {
            range = String(localized: "\(coldest)-\(warmest) C")
        } else if let value = temperatures.first {
            range = String(localized: "\(value) C")
        } else {
            range = String(localized: "Forecast checked")
        }

        let severity: AlertSeverity
        if warningCount > 0 {
            severity = .watch
        } else if unavailable.count == cards.count {
            severity = .watch
        } else {
            severity = .calm
        }

        let sourceDetail = String(localized: "\(cards.count) weather cards checked across upcoming itinerary locations.")
        return AssistantWeatherPreparation(
            title: String(localized: "Weather prep"),
            summary: [range, weatherSummaryText(cards)].compactMap { $0.nilIfEmpty }.joined(separator: " · "),
            recommendation: items.first ?? String(localized: "Check the forecast before leaving."),
            items: items,
            severity: severity,
            sourceDetail: sourceDetail
        )
    }

    private func environmentSignals(
        journey: AssistantJourneyStage,
        itinerary: [ItineraryItem],
        weatherCards: [ItemEnrichmentCard],
        alerts: [TravelAlert]
    ) -> [AssistantEnvironmentSignal] {
        let focusItem = journey.focusItemID.flatMap { focusID in
            itinerary.first { $0.id == focusID }
        }
        var signals: [AssistantEnvironmentSignal] = []

        func append(_ signal: AssistantEnvironmentSignal) {
            let meaning = "\(signal.title) \(signal.value) \(signal.detail ?? "")"
            guard !signals.contains(where: { existing in
                assistantMeaningfullyMatches(
                    "\(existing.title) \(existing.value) \(existing.detail ?? "")",
                    meaning
                )
            }) else {
                return
            }
            signals.append(signal)
        }

        if let location = journey.location {
            append(
                AssistantEnvironmentSignal(
                    id: "stage-place-\(journey.focusItemID?.uuidString ?? "trip")",
                    kind: .place,
                    title: String(localized: "Stage location"),
                    value: location,
                    detail: journey.phase == .active
                        ? String(localized: "This is the place Voya is using for live context right now.")
                        : String(localized: "Weather, nearby events, and route guidance are matched to this place."),
                    severity: .calm,
                    actionURL: mapURL(for: location),
                    itemID: journey.focusItemID
                )
            )
        }

        if let focusItem,
           let enrichment = ItemEnrichmentCache.cachedEnrichment(for: focusItem) {
            if let weather = enrichment.cards.first(where: {
                $0.kind == "weather" || $0.title.localizedCaseInsensitiveContains("weather")
            }) {
                append(environmentSignal(from: weather, kind: .weather, itemID: focusItem.id))
            }

            for warning in enrichment.cards.filter({ $0.kind == "warning" }).prefix(1) {
                append(environmentSignal(from: warning, kind: .warning, itemID: focusItem.id))
            }

            for event in (enrichment.nearbyEvents ?? []).prefix(2) {
                let timing = [event.localDate, event.localTime]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                    .joined(separator: " · ")
                let place = [event.venue, event.city]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                    .joined(separator: " · ")
                append(
                    AssistantEnvironmentSignal(
                        id: "nearby-event-\(event.id)",
                        kind: .event,
                        title: String(localized: "Nearby event"),
                        value: event.name,
                        detail: [timing.nilIfEmpty, place.nilIfEmpty].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                        severity: .calm,
                        actionURL: event.url,
                        itemID: focusItem.id
                    )
                )
            }
        }

        if !signals.contains(where: { $0.kind == .weather }), let weather = weatherCards.first {
            append(environmentSignal(from: weather, kind: .weather, itemID: journey.focusItemID))
        }

        if let focusID = journey.focusItemID {
            let identifier = focusID.uuidString
            if let flight = alerts.first(where: {
                ($0.id.hasPrefix("flight-status-") || $0.id.hasPrefix("flight-plane-") || $0.id.hasPrefix("flight-status-pending-"))
                    && $0.id.hasSuffix(identifier)
            }) {
                append(
                    AssistantEnvironmentSignal(
                        id: "environment-\(flight.id)",
                        kind: .flight,
                        title: String(localized: "Live flight context"),
                        value: flight.title,
                        detail: flight.message,
                        severity: flight.severity,
                        actionURL: flight.actionURL,
                        itemID: focusID
                    )
                )
            }
        }

        let route = alerts.first(where: { alert in
            alert.sourceTitle == String(localized: "Mobility plan")
                && journey.focusItemID.map { alert.id.contains($0.uuidString) } == true
        }) ?? alerts.first(where: { $0.sourceTitle == String(localized: "Mobility plan") })
        if let route {
            append(
                AssistantEnvironmentSignal(
                    id: "environment-\(route.id)",
                    kind: .route,
                    title: String(localized: "Route context"),
                    value: route.title,
                    detail: route.message,
                    severity: route.severity,
                    actionURL: route.actionURL,
                    itemID: journey.focusItemID
                )
            )
        }

        return Array(signals.prefix(6))
    }

    private func environmentSignal(
        from card: ItemEnrichmentCard,
        kind: AssistantEnvironmentKind,
        itemID: UUID?
    ) -> AssistantEnvironmentSignal {
        AssistantEnvironmentSignal(
            id: "environment-card-\(card.id)-\(itemID?.uuidString ?? "trip")",
            kind: kind,
            title: card.title,
            value: card.value,
            detail: card.detail,
            severity: card.kind == "warning" ? .watch : .calm,
            actionURL: card.actionURL,
            itemID: itemID
        )
    }

    private func recommendations(
        journey: AssistantJourneyStage,
        itinerary: [ItineraryItem],
        alerts: [TravelAlert],
        aiAdvice: AssistantAIAdvice?
    ) -> [AssistantRecommendation] {
        var result: [AssistantRecommendation] = []

        func append(_ recommendation: AssistantRecommendation) {
            let meaning = "\(recommendation.title) \(recommendation.detail)"
            guard !recommendation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.contains(where: {
                      assistantMeaningfullyMatches("\($0.title) \($0.detail)", meaning)
                  }) else {
                return
            }
            result.append(recommendation)
        }

        for alert in alerts where alert.severity != .calm {
            append(
                AssistantRecommendation(
                    id: "recommendation-\(alert.id)",
                    urgency: alert.severity == .action ? .now : .soon,
                    title: alert.title,
                    detail: alert.message,
                    symbol: alert.severity == .action ? "exclamationmark.circle.fill" : "clock.fill",
                    itemID: relatedItemID(for: alert, itinerary: itinerary, journey: journey)
                )
            )
            if result.count >= 4 { break }
        }

        if let aiAdvice, aiAdvice.isReliableEnoughToOverrideFacts {
            for (index, action) in aiAdvice.nextActions.prefix(3).enumerated() {
                let parts = action.split(separator: ":", maxSplits: 1).map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                append(
                    AssistantRecommendation(
                        id: "ai-recommendation-\(index)",
                        urgency: result.isEmpty ? .soon : .later,
                        title: parts.first?.nilIfEmpty ?? String(localized: "Travel recommendation"),
                        detail: parts.count > 1
                            ? parts[1]
                            : String(localized: "Keep this in view as the trip progresses."),
                        symbol: "sparkles",
                        itemID: nil
                    )
                )
            }
        }

        if result.isEmpty {
            append(stageRecommendation(for: journey))
        }

        return Array(result.prefix(5))
    }

    private func relatedItemID(
        for alert: TravelAlert,
        itinerary: [ItineraryItem],
        journey: AssistantJourneyStage
    ) -> UUID? {
        if let focusID = journey.focusItemID, alert.id.contains(focusID.uuidString) {
            return focusID
        }
        return itinerary.first(where: { alert.id.contains($0.id.uuidString) })?.id
    }

    private func stageRecommendation(for journey: AssistantJourneyStage) -> AssistantRecommendation {
        let urgency: AssistantRecommendationUrgency
        let title: String
        let detail: String
        let symbol: String

        switch journey.phase {
        case .planning:
            urgency = .now
            title = String(localized: "Complete the itinerary")
            detail = String(localized: "Add dates and exact places so Voya can calculate the current stage, route buffers, and local conditions.")
            symbol = "calendar.badge.plus"
        case .preparing:
            urgency = .soon
            title = String(localized: "Prepare the first stage")
            detail = String(localized: "Confirm documents, departure route, and a realistic leave time before the trip begins.")
            symbol = "checklist"
        case .active:
            urgency = .now
            title = String(localized: "Stay with the current stage")
            detail = String(localized: "Keep its live status and the next connection visible; Voya will surface changes as sources refresh.")
            symbol = "location.fill.viewfinder"
        case .between:
            urgency = .now
            title = String(localized: "Prepare the next move")
            detail = String(localized: "Check the route, leave time, and anything that could delay the next stage.")
            symbol = "arrow.trianglehead.swap"
        case .completed:
            urgency = .later
            title = String(localized: "Keep records until the trip is settled")
            detail = String(localized: "Retain booking documents until deposits, points, refunds, and claims are complete.")
            symbol = "archivebox.fill"
        }

        return AssistantRecommendation(
            id: "stage-recommendation-\(journey.phase.rawValue)",
            urgency: urgency,
            title: title,
            detail: detail,
            symbol: symbol,
            itemID: journey.focusItemID
        )
    }

    private func mapURL(for place: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: place)]
        return components?.url
    }

    private func tripAssessment(
        trip: Trip,
        itinerary: [ItineraryItem],
        alerts: [TravelAlert],
        readySignals: Int,
        watchSignals: Int,
        actionSignals: Int
    ) -> AssistantTripAssessment {
        let maxScore = 100
        let score = max(0, min(maxScore, maxScore - actionSignals * 18 - watchSignals * 7 + min(readySignals * 2, 12)))
        let title: String
        let detail: String
        let riskLabel: String

        if actionSignals > 0 {
            title = String(localized: "\(trip.title) needs action")
            detail = String(localized: "Resolve blocking items before relying on live guidance.")
            riskLabel = String(localized: "Action")
        } else if watchSignals > 0 {
            title = String(localized: "\(trip.title) is mostly ready")
            detail = String(localized: "Some live signals need watching; core itinerary data is usable.")
            riskLabel = String(localized: "Watch")
        } else if itinerary.isEmpty {
            title = String(localized: "\(trip.title) needs itinerary data")
            detail = String(localized: "Add timed items, places, and documents to activate the assistant.")
            riskLabel = String(localized: "Set")
        } else {
            title = String(localized: "\(trip.title) looks ready")
            detail = String(localized: "Routes, flight checks, weather prep, and local itinerary signals are aligned.")
            riskLabel = String(localized: "Low")
        }

        return AssistantTripAssessment(
            score: score,
            title: title,
            detail: alerts.isEmpty ? String(localized: "No live signals were generated yet.") : detail,
            riskLabel: riskLabel,
            readyCount: readySignals,
            watchCount: watchSignals,
            actionCount: actionSignals
        )
    }

    private func sourceDetail(for source: String) -> String {
        if source == String(localized: "Flight lookup") {
            return String(localized: "Status, gate, terminal, baggage, and provider confidence.")
        }
        if source == String(localized: "Mobility plan") {
            return String(localized: "Leave time, duration, route mode, buffer, and reliability.")
        }
        if source == String(localized: "Weather enrichment") {
            return String(localized: "Forecast cards converted into packing and clothing advice.")
        }
        return String(localized: "Saved itinerary fields, documents, and timing rules.")
    }

    func answerQuestion(
        _ question: String,
        trip: Trip?,
        itinerary: [ItineraryItem],
        intelligence: AssistantIntelligence,
        conversation: [AssistantConversationTurn] = []
    ) async -> AssistantAIAdvice? {
        guard let trip else {
            return nil
        }

        return await assistantAIAdvice(
            trip: trip,
            itinerary: itinerary,
            assessment: intelligence.assessment,
            journey: intelligence.journey,
            alerts: intelligence.alerts,
            weather: intelligence.weather,
            environment: intelligence.environment,
            sources: intelligence.sources,
            question: question,
            conversation: conversation
        )
    }

    private func assistantAIAdvice(
        trip: Trip,
        itinerary: [ItineraryItem],
        assessment: AssistantTripAssessment,
        journey: AssistantJourneyStage,
        alerts: [TravelAlert],
        weather: AssistantWeatherPreparation,
        environment: [AssistantEnvironmentSignal],
        sources: [AssistantSourceSummary],
        question: String?,
        conversation: [AssistantConversationTurn]
    ) async -> AssistantAIAdvice? {
        do {
            return try await VercelAssistantAIService().advise(
                request: aiRequest(
                    trip: trip,
                    itinerary: itinerary,
                    assessment: assessment,
                    journey: journey,
                    alerts: alerts,
                    weather: weather,
                    environment: environment,
                    sources: sources,
                    question: question,
                    conversation: conversation
                )
            )
        } catch {
            return nil
        }
    }

    private func aiRequest(
        trip: Trip,
        itinerary: [ItineraryItem],
        assessment: AssistantTripAssessment,
        journey: AssistantJourneyStage,
        alerts: [TravelAlert],
        weather: AssistantWeatherPreparation,
        environment: [AssistantEnvironmentSignal],
        sources: [AssistantSourceSummary],
        question: String?,
        conversation: [AssistantConversationTurn]
    ) -> AssistantAIRequest {
        AssistantAIRequest(
            locale: VoyaAppLocale.currentIdentifier,
            languageCode: VoyaAppLocale.currentLanguageCode,
            languageName: VoyaAppLocale.currentLanguageName,
            question: privacySafeText(question, itinerary: itinerary, maximumLength: 2_000),
            trip: AssistantAIRequest.TripContext(
                title: privacySafeText(trip.title, itinerary: itinerary, maximumLength: 300) ?? trip.title,
                dates: trip.displayDates,
                summary: privacySafeText(trip.summary, itinerary: itinerary, maximumLength: 1_500) ?? "",
                destination: privacySafeText(trip.destination, itinerary: itinerary, maximumLength: 500),
                startsAt: trip.startsAt,
                endsAt: trip.endsAt,
                notes: privacySafeText(trip.notes, itinerary: itinerary, maximumLength: 1_500),
                sourceName: trip.sourceName,
                startLocationName: privacySafeText(trip.startLocationName, itinerary: itinerary, maximumLength: 500),
                endLocationName: privacySafeText(trip.endLocationName, itinerary: itinerary, maximumLength: 500)
            ),
            assessment: AssistantAIRequest.AssessmentContext(
                score: assessment.score,
                riskLabel: assessment.riskLabel,
                readyCount: assessment.readyCount,
                watchCount: assessment.watchCount,
                actionCount: assessment.actionCount
            ),
            journey: AssistantAIRequest.JourneyContext(
                phase: journey.phase.rawValue,
                phaseLabel: journey.phaseLabel,
                title: privacySafeText(journey.title, itinerary: itinerary, maximumLength: 300) ?? journey.title,
                detail: privacySafeText(journey.detail, itinerary: itinerary, maximumLength: 1_500) ?? journey.detail,
                progress: journey.progress,
                completedItems: journey.completedItems,
                totalItems: journey.totalItems,
                location: privacySafeText(journey.location, itinerary: itinerary, maximumLength: 500),
                status: privacySafeText(journey.status, itinerary: itinerary, maximumLength: 500),
                timeSummary: journey.timeSummary,
                timingContext: journey.timingContext
            ),
            nextItem: nextItem(in: itinerary).map { itemContext($0, itinerary: itinerary) },
            itinerary: itinerary.map { itemContext($0, itinerary: itinerary) },
            alerts: alerts.map {
                AssistantAIRequest.AlertContext(
                    title: privacySafeText($0.title, itinerary: itinerary, maximumLength: 300) ?? $0.title,
                    message: privacySafeText($0.message, itinerary: itinerary, maximumLength: 1_500) ?? $0.message,
                    severity: $0.severity.apiValue,
                    sourceTitle: privacySafeText($0.sourceTitle, itinerary: itinerary, maximumLength: 160),
                    sourceDetail: privacySafeText($0.sourceDetail, itinerary: itinerary, maximumLength: 1_000)
                )
            },
            weather: AssistantAIRequest.WeatherContext(
                title: privacySafeText(weather.title, itinerary: itinerary, maximumLength: 200) ?? weather.title,
                summary: privacySafeText(weather.summary, itinerary: itinerary, maximumLength: 1_500) ?? weather.summary,
                recommendation: privacySafeText(weather.recommendation, itinerary: itinerary, maximumLength: 1_500) ?? weather.recommendation,
                items: weather.items.compactMap {
                    privacySafeText($0, itinerary: itinerary, maximumLength: 500)
                },
                severity: weather.severity.apiValue
            ),
            environment: environment.map {
                AssistantAIRequest.EnvironmentContext(
                    kind: $0.kind.apiValue,
                    title: privacySafeText($0.title, itinerary: itinerary, maximumLength: 200) ?? $0.title,
                    value: privacySafeText($0.value, itinerary: itinerary, maximumLength: 500) ?? $0.value,
                    detail: privacySafeText($0.detail, itinerary: itinerary, maximumLength: 1_000),
                    severity: $0.severity.apiValue
                )
            },
            sources: sources.map {
                AssistantAIRequest.SourceContext(
                    title: privacySafeText($0.title, itinerary: itinerary, maximumLength: 160) ?? $0.title,
                    detail: privacySafeText($0.detail, itinerary: itinerary, maximumLength: 1_000) ?? $0.detail,
                    count: $0.count,
                    severity: $0.severity.apiValue
                )
            },
            conversation: conversation.suffix(12).compactMap { turn in
                guard let content = privacySafeText(turn.content, itinerary: itinerary, maximumLength: 2_000) else {
                    return nil
                }
                return AssistantConversationTurn(role: turn.role, content: content)
            }
        )
    }

    private func itemContext(
        _ item: ItineraryItem,
        itinerary: [ItineraryItem]
    ) -> AssistantAIRequest.ItineraryItemContext {
        AssistantAIRequest.ItineraryItemContext(
            kind: item.kind.rawValue,
            title: privacySafeText(item.title, itinerary: itinerary, maximumLength: 300) ?? item.title,
            location: privacySafeText(item.location, itinerary: itinerary, maximumLength: 500) ?? "",
            status: privacySafeText(item.status, itinerary: itinerary, maximumLength: 500) ?? "",
            startsAt: item.startsAt,
            endsAt: item.endsAt,
            providerName: privacySafeText(item.providerName, itinerary: itinerary, maximumLength: 160),
            sourceName: privacySafeText(item.sourceName, itinerary: itinerary, maximumLength: 160),
            hasConfirmationCode: item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil,
            hasBoardingPass: store.boardingPassDocument(for: item) != nil,
            hasSourceDocument: store.sourceDocument(for: item) != nil
        )
    }

    private func privacySafeText(
        _ value: String?,
        itinerary: [ItineraryItem],
        maximumLength: Int
    ) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        for confirmationCode in itinerary.compactMap(\.confirmationCode) {
            let code = confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            value = value.replacingOccurrences(
                of: code,
                with: String(localized: "[booking reference saved locally]"),
                options: [.caseInsensitive]
            )
        }
        return String(value.prefix(maximumLength))
    }

    private func nextItem(in itinerary: [ItineraryItem]) -> ItineraryItem? {
        let now = Date()
        return itinerary.first { item in
            guard let start = item.startsAt else { return false }
            return (item.endsAt ?? start) >= now
        } ?? itinerary.first
    }

    private func routeDepartureDate(for option: MobilityRouteOption) -> Date? {
        (option.steps?.compactMap { $0.departureTime.flatMap(MobilityDateFormatter.date(from:)) } ?? []).min()
            ?? option.departureTime.flatMap(MobilityDateFormatter.date(from:))
            ?? option.leaveBy.flatMap(MobilityDateFormatter.date(from:))
    }

    private func weatherSummaryText(_ cards: [ItemEnrichmentCard]) -> String {
        cards.compactMap { card in
            card.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? card.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        .prefix(2)
        .joined(separator: " · ")
    }

    private func temperatureCelsius(from value: String) -> Int? {
        let pattern = #"(-?\d{1,2})\s?(?:°?\s?C|C\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Int(value[range])
    }

    private func shortPlace(_ value: String) -> String {
        let parts = value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2,
           ["arrivals", "departures"].contains(parts[0].lowercased()) {
            return "\(parts[0]) \(parts[1])"
        }
        return parts.first ?? value
    }

    private func flightDisplayTitle(_ item: ItineraryItem) -> String {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Flight")
    }

    private func maxSeverity(_ lhs: AlertSeverity?, _ rhs: AlertSeverity) -> AlertSeverity {
        guard let lhs else { return rhs }
        return lhs.priority >= rhs.priority ? lhs : rhs
    }
}

private extension AssistantEnvironmentKind {
    var apiValue: String {
        switch self {
        case .place: "place"
        case .weather: "weather"
        case .route: "route"
        case .event: "event"
        case .flight: "flight"
        case .warning: "warning"
        }
    }
}

private extension AlertSeverity {
    var priority: Int {
        switch self {
        case .calm: 0
        case .watch: 1
        case .action: 2
        }
    }

    var apiValue: String {
        switch self {
        case .calm: "calm"
        case .watch: "watch"
        case .action: "action"
        }
    }
}

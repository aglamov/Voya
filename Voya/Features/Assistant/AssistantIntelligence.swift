import Foundation
import SwiftData
import SwiftUI

struct AssistantIntelligence {
    var assessment: AssistantTripAssessment
    var alerts: [TravelAlert]
    var weather: AssistantWeatherPreparation
    var sources: [AssistantSourceSummary]
    var aiAdvice: AssistantAIAdvice?
    var generatedAt: Date
    var isPlaceholder: Bool

    static let empty = AssistantIntelligence(
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
        onProgress?(.aiReview)
        let aiAdvice = await assistantAIAdvice(
            trip: trip,
            itinerary: itinerary,
            assessment: assessment,
            alerts: sortedAlerts,
            weather: finalWeather,
            sources: sources,
            question: nil
        )

        if let aiAdvice, aiAdvice.isReliableEnoughToOverrideFacts {
            assessment.title = aiAdvice.assessmentTitle
            assessment.detail = aiAdvice.assessmentDetail
            finalWeather.recommendation = aiAdvice.packingAdvice
        }

        onProgress?(.complete)
        return AssistantIntelligence(
            assessment: assessment,
            alerts: sortedAlerts,
            weather: finalWeather,
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

        return AssistantIntelligence(
            assessment: assessment,
            alerts: alerts,
            weather: .empty,
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
                    message: action.confirmationCode.map {
                        String(localized: "Online check-in should be open. Booking reference \($0) is saved.")
                    } ?? String(localized: "Online check-in should be open. Have PNR and passenger last name ready."),
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
            guard let flightNumber = store.firstFlightNumber(in: "\(item.title) \(item.location)") else {
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

        return contexts
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
            detail = String(localized: "Resolve \(actionSignals) blocking items before relying on live guidance.")
            riskLabel = String(localized: "Action")
        } else if watchSignals > 0 {
            title = String(localized: "\(trip.title) is mostly ready")
            detail = String(localized: "\(watchSignals) live signals need watching; core itinerary data is usable.")
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
        intelligence: AssistantIntelligence
    ) async -> AssistantAIAdvice? {
        guard let trip else {
            return nil
        }

        return await assistantAIAdvice(
            trip: trip,
            itinerary: itinerary,
            assessment: intelligence.assessment,
            alerts: intelligence.alerts,
            weather: intelligence.weather,
            sources: intelligence.sources,
            question: question
        )
    }

    private func assistantAIAdvice(
        trip: Trip,
        itinerary: [ItineraryItem],
        assessment: AssistantTripAssessment,
        alerts: [TravelAlert],
        weather: AssistantWeatherPreparation,
        sources: [AssistantSourceSummary],
        question: String?
    ) async -> AssistantAIAdvice? {
        do {
            return try await VercelAssistantAIService().advise(
                request: aiRequest(
                    trip: trip,
                    itinerary: itinerary,
                    assessment: assessment,
                    alerts: alerts,
                    weather: weather,
                    sources: sources,
                    question: question
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
        alerts: [TravelAlert],
        weather: AssistantWeatherPreparation,
        sources: [AssistantSourceSummary],
        question: String?
    ) -> AssistantAIRequest {
        AssistantAIRequest(
            locale: VoyaAppLocale.currentIdentifier,
            languageCode: VoyaAppLocale.currentLanguageCode,
            languageName: VoyaAppLocale.currentLanguageName,
            question: question?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            trip: AssistantAIRequest.TripContext(
                title: trip.title,
                dates: trip.displayDates,
                summary: trip.summary,
                destination: trip.destination,
                startsAt: trip.startsAt,
                endsAt: trip.endsAt,
                notes: trip.notes,
                sourceName: trip.sourceName,
                startLocationName: trip.startLocationName,
                startLocationAddress: trip.startLocationAddress,
                endLocationName: trip.endLocationName,
                endLocationAddress: trip.endLocationAddress
            ),
            assessment: AssistantAIRequest.AssessmentContext(
                score: assessment.score,
                riskLabel: assessment.riskLabel,
                readyCount: assessment.readyCount,
                watchCount: assessment.watchCount,
                actionCount: assessment.actionCount
            ),
            nextItem: nextItem(in: itinerary).map { itemContext($0) },
            itinerary: itinerary.map { itemContext($0) },
            alerts: alerts.map {
                AssistantAIRequest.AlertContext(
                    title: $0.title,
                    message: $0.message,
                    severity: $0.severity.apiValue,
                    sourceTitle: $0.sourceTitle,
                    sourceDetail: $0.sourceDetail
                )
            },
            weather: AssistantAIRequest.WeatherContext(
                title: weather.title,
                summary: weather.summary,
                recommendation: weather.recommendation,
                items: weather.items,
                severity: weather.severity.apiValue
            ),
            sources: sources.map {
                AssistantAIRequest.SourceContext(
                    title: $0.title,
                    detail: $0.detail,
                    count: $0.count,
                    severity: $0.severity.apiValue
                )
            }
        )
    }

    private func itemContext(_ item: ItineraryItem) -> AssistantAIRequest.ItineraryItemContext {
        AssistantAIRequest.ItineraryItemContext(
            kind: item.kind.rawValue,
            title: item.title,
            location: item.location,
            status: item.status,
            startsAt: item.startsAt,
            endsAt: item.endsAt,
            confirmationCode: item.confirmationCode,
            providerName: item.providerName,
            sourceName: item.sourceName,
            extractedBookingData: compactAIContext(item.normalizedData ?? item.rawData),
            hasBoardingPass: store.boardingPassDocument(for: item) != nil,
            hasSourceDocument: store.sourceDocument(for: item) != nil
        )
    }

    private func compactAIContext(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return String(value.prefix(4_000))
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

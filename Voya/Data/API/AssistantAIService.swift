import Foundation
import SwiftData
import SwiftUI

struct AssistantAIAdvice: Codable {
    var summary: String
    var assessmentTitle: String
    var assessmentDetail: String
    var answer: String
    var packingAdvice: String
    var nextActions: [String]
    var nextItemDescription: String?
    var riskOverview: String?
    var additionalRisks: [AssistantAIRisk]?
    var suggestedQuestions: [String]?
    var answerSources: [String]?
    var confidence: Double
    var usedAI: Bool
}

extension AssistantAIAdvice {
    var isReliableEnoughToOverrideFacts: Bool {
        !usedAI || confidence >= 0.55
    }

    var confidencePercent: Int {
        Int((max(0, min(1, confidence)) * 100).rounded())
    }
}

struct AssistantAIRisk: Codable {
    var title: String
    var description: String
    var severity: String
}

struct AssistantConversationTurn: Codable, Hashable {
    var role: String
    var content: String
}

struct AssistantAIRequest: Encodable {
    var locale: String
    var languageCode: String
    var languageName: String
    var question: String?
    var trip: TripContext
    var assessment: AssessmentContext
    var journey: JourneyContext
    var nextItem: ItineraryItemContext?
    var itinerary: [ItineraryItemContext]
    var alerts: [AlertContext]
    var weather: WeatherContext
    var environment: [EnvironmentContext]
    var sources: [SourceContext]
    var conversation: [AssistantConversationTurn]

    struct TripContext: Encodable {
        var title: String
        var dates: String
        var summary: String
        var destination: String?
        var startsAt: Date?
        var endsAt: Date?
        var notes: String?
        var sourceName: String
        var startLocationName: String?
        var endLocationName: String?
    }

    struct AssessmentContext: Encodable {
        var score: Int
        var riskLabel: String
        var readyCount: Int
        var watchCount: Int
        var actionCount: Int
    }

    struct JourneyContext: Encodable {
        var phase: String
        var phaseLabel: String
        var title: String
        var detail: String
        var progress: Double
        var completedItems: Int
        var totalItems: Int
        var location: String?
        var status: String?
        var timeSummary: String?
        var timingContext: String?
    }

    struct ItineraryItemContext: Encodable {
        var kind: String
        var title: String
        var location: String
        var status: String
        var startsAt: Date?
        var endsAt: Date?
        var providerName: String?
        var sourceName: String?
        var hasConfirmationCode: Bool
        var hasBoardingPass: Bool
        var hasSourceDocument: Bool
    }

    struct AlertContext: Encodable {
        var title: String
        var message: String
        var severity: String
        var sourceTitle: String?
        var sourceDetail: String?
    }

    struct WeatherContext: Encodable {
        var title: String
        var summary: String
        var recommendation: String
        var items: [String]
        var severity: String
    }

    struct EnvironmentContext: Encodable {
        var kind: String
        var title: String
        var value: String
        var detail: String?
        var severity: String
    }

    struct SourceContext: Encodable {
        var title: String
        var detail: String
        var count: Int
        var severity: String
    }
}

struct VercelAssistantAIService {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func advise(request body: AssistantAIRequest) async throws -> AssistantAIAdvice {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/assistant"))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        return try JSONDecoder().decode(AssistantAIAdvice.self, from: data)
    }
}

enum InspirationTheme: String, Codable, CaseIterable {
    case music
    case nature
    case culture
    case phenomenon
    case seasonal
}

struct InspirationStory: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var hook: String
    var destination: String
    var country: String
    var theme: InspirationTheme
    var moods: [String]
    var timing: String
    var idealDays: Int
    var whyNow: String
    var experience: [String]
    var practicalNotes: [String]
    var mainRisk: String
    var symbol: String
    var gradient: [String]
    var sourceTitle: String
    var sourceURL: URL
    var confidence: Double
    var selectionReason: String? = nil
    var verificationSummary: String? = nil
    var agentChecks: [String]? = nil
    var place: InspirationPlace? = nil

    static let fallback: [InspirationStory] = [
        InspirationStory(
            id: "lofoten-aurora",
            title: String(localized: "Northern lights above the Lofoten Islands"),
            hook: String(localized: "Long blue hours, fishing villages and four nights with a chance to see the sky turn green."),
            destination: "Lofoten Islands",
            country: String(localized: "Norway"),
            theme: .phenomenon,
            moods: ["wonder", "nature", "remote", "winter"],
            timing: String(localized: "September–March"),
            idealDays: 6,
            whyNow: String(localized: "The dark season creates long viewing windows, while the islands remain a remarkable journey even if the aurora stays hidden."),
            experience: [String(localized: "Aurora nights"), String(localized: "Scenic island roads"), String(localized: "Arctic fishing villages")],
            practicalNotes: [String(localized: "A car makes the islands much easier"), String(localized: "Keep at least four viewing nights")],
            mainRisk: String(localized: "Cloud cover is unpredictable, so no single night can be promised."),
            symbol: "sparkles",
            gradient: ["122B45", "49A99A"],
            sourceTitle: "Visit Norway — Northern Lights",
            sourceURL: URL(string: "https://www.visitnorway.com/things-to-do/nature-attractions/northern-lights/")!,
            confidence: 0.92
        ),
        InspirationStory(
            id: "japan-sakura",
            title: String(localized: "Follow spring through Japan"),
            hook: String(localized: "A slow journey from temple gardens to mountain onsen as the cherry blossom season moves north."),
            destination: String(localized: "Kyoto and the Japanese Alps"),
            country: String(localized: "Japan"),
            theme: .seasonal,
            moods: ["beauty", "culture", "slow", "spring"],
            timing: String(localized: "Late March–April"),
            idealDays: 9,
            whyNow: String(localized: "The blossom forecast turns an ordinary route into a time-sensitive journey through several stages of spring."),
            experience: [String(localized: "Temple gardens"), String(localized: "Mountain onsen"), String(localized: "Seasonal food")],
            practicalNotes: [String(localized: "Exact bloom dates vary every year"), String(localized: "Book popular cities well ahead")],
            mainRisk: String(localized: "Peak bloom is brief and weather can move it earlier or later."),
            symbol: "camera.macro",
            gradient: ["BB6F86", "F1B6A8"],
            sourceTitle: "Japan National Tourism Organization",
            sourceURL: URL(string: "https://www.japan.travel/en/uk/inspiration/cherry-blossom-forecast/")!,
            confidence: 0.9
        ),
        InspirationStory(
            id: "azores-whales",
            title: String(localized: "Meet the whales of the Azores"),
            hook: String(localized: "Volcanic lakes, Atlantic cliffs and days shaped around what appears on the horizon."),
            destination: "São Miguel",
            country: String(localized: "Portugal"),
            theme: .nature,
            moods: ["ocean", "wildlife", "quiet", "nature"],
            timing: String(localized: "April–October"),
            idealDays: 7,
            whyNow: String(localized: "Different species pass through the archipelago across the season, making wildlife part of a broader volcanic-island trip."),
            experience: [String(localized: "Whale watching"), String(localized: "Volcanic hot springs"), String(localized: "Crater-lake walks")],
            practicalNotes: [String(localized: "Leave a weather buffer for the boat"), String(localized: "Choose a responsible operator")],
            mainRisk: String(localized: "Sea conditions can cancel departures and sightings are never guaranteed."),
            symbol: "water.waves",
            gradient: ["145B63", "6CB6A6"],
            sourceTitle: "Visit Azores — Whale Watching",
            sourceURL: URL(string: "https://www.visitazores.com/en/experience-the-azores/whale-watching")!,
            confidence: 0.91
        )
    ]
}

struct InspirationPlace: Codable, Equatable {
    var id: String
    var name: String
    var address: String?
    var rating: Double?
    var userRatingCount: Int?
    var mapsURL: URL?
}

enum AgentMissionKind: String, Codable, CaseIterable {
    case guardian
    case inspiration
    case planning
    case recovery
    case concierge

    var symbol: String {
        switch self {
        case .guardian: "shield.checkered"
        case .inspiration: "sparkles"
        case .planning: "map"
        case .recovery: "lifepreserver"
        case .concierge: "bell.and.waves.left.and.right"
        }
    }
}

enum AgentMissionStatus: String, Codable {
    case queued
    case active
    case running
    case waiting
    case completed
    case failed
    case cancelled
}

struct AgentMission: Identifiable, Codable, Equatable {
    var id: UUID
    var tripId: UUID?
    var inspirationId: String?
    var kind: AgentMissionKind
    var title: String
    var detail: String
    var status: AgentMissionStatus
    var createdAt: Date
    var updatedAt: Date
    var nextCheckAt: Date?
    var assignedAgents: [String]?
    var resultTitle: String?
    var resultSummary: String?
    var resultActions: [String]?
    var requiresApproval: Bool?
    var lastRunAt: Date?
    var runCount: Int?
    var lastError: String?
}

struct InspirationReleaseAgent: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var state: String
    var detail: String
}

struct InspirationRelease: Identifiable, Codable, Equatable {
    var id: UUID
    var status: String
    var mood: String
    var stage: String
    var progress: Double
    var requestedAt: Date
    var updatedAt: Date
    var readyAt: Date?
    var curatorNote: String?
    var stories: [InspirationStory]?
    var usedAI: Bool?
    var error: String?
    var agents: [InspirationReleaseAgent]
}

enum AgentMissionLocalStore {
    private static let key = "voya-agent-missions-v1"

    static func load() -> [AgentMission] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let missions = try? decoder.decode([AgentMission].self, from: data) else {
            return []
        }
        return missions
    }

    static func save(_ missions: [AgentMission]) {
        guard let data = try? encoder.encode(missions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct GuardianReport: Codable, Equatable {
    var generatedAt: Date
    var status: String
    var headline: String
    var summary: String
    var watchCount: Int
    var findings: [GuardianFinding]
    var agents: [GuardianAgent]
}

struct GuardianFinding: Identifiable, Codable, Equatable {
    var id: String
    var agent: String
    var severity: String
    var title: String
    var detail: String
    var itemId: UUID?
}

struct GuardianAgent: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var responsibility: String
    var state: String
}

private struct InspirationReleaseResponse: Decodable {
    var release: InspirationRelease?
}

private struct MissionResponse: Decodable {
    var mission: AgentMission
}

private struct MissionsResponse: Decodable {
    var missions: [AgentMission]
}

@MainActor
struct VoyaAgentService {
    private let session: URLSession
    private let baseURL: URL?

    init(session: URLSession = .shared, baseURL: URL? = VoyaAPIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func prepareInspiration(mood: String) async throws -> InspirationRelease? {
        struct Body: Encodable {
            var mood: String
            var deviceToken: String?
            var locale: String
        }
        let data = try await request(
            path: "api/inspiration",
            method: "POST",
            body: Body(
                mood: mood,
                deviceToken: VoyaPushRegistrationService.shared.currentDeviceToken,
                locale: VoyaAppLocale.currentIdentifier
            )
        )
        return try decoder.decode(InspirationReleaseResponse.self, from: data).release
    }

    func inspirationRelease() async throws -> InspirationRelease? {
        let data = try await get(path: "api/inspiration")
        return try decoder.decode(InspirationReleaseResponse.self, from: data).release
    }

    func createMission(_ mission: AgentMission, context: [String: String]) async throws -> AgentMission {
        struct Body: Encodable {
            var kind: AgentMissionKind
            var title: String
            var detail: String
            var tripId: UUID?
            var inspirationId: String?
            var nextCheckAt: Date?
            var deviceToken: String?
            var context: [String: String]
        }
        let body = Body(
            kind: mission.kind,
            title: mission.title,
            detail: mission.detail,
            tripId: mission.tripId,
            inspirationId: mission.inspirationId,
            nextCheckAt: mission.nextCheckAt,
            deviceToken: VoyaPushRegistrationService.shared.currentDeviceToken,
            context: context
        )
        let data = try await request(path: "api/missions", method: "POST", body: body)
        return try decoder.decode(MissionResponse.self, from: data).mission
    }

    func missions() async throws -> [AgentMission] {
        let data = try await get(path: "api/missions")
        return try decoder.decode(MissionsResponse.self, from: data).missions
    }

    func updateMission(id: UUID, status: AgentMissionStatus) async throws -> AgentMission {
        struct Body: Encodable {
            var id: UUID
            var status: AgentMissionStatus
        }
        let data = try await request(path: "api/missions", method: "PATCH", body: Body(id: id, status: status))
        return try decoder.decode(MissionResponse.self, from: data).mission
    }

    func guardian(trip: Trip, itinerary: [ItineraryItem]) async throws -> GuardianReport {
        struct Item: Encodable {
            var id: UUID
            var kind: String
            var title: String
            var location: String
            var status: String
            var startsAt: Date?
            var endsAt: Date?
            var hasConfirmationCode: Bool
        }
        struct TripBody: Encodable {
            var id: UUID
            var title: String
            var destination: String?
            var startsAt: Date?
            var endsAt: Date?
        }
        struct Body: Encodable {
            var trip: TripBody
            var itinerary: [Item]
            var locale: String
        }
        let body = Body(
            trip: TripBody(id: trip.id, title: trip.title, destination: trip.destination, startsAt: trip.startsAt, endsAt: trip.endsAt),
            itinerary: itinerary.map {
                Item(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    title: $0.title,
                    location: $0.location,
                    status: $0.status,
                    startsAt: $0.startsAt,
                    endsAt: $0.endsAt,
                    hasConfirmationCode: $0.confirmationCode?.isEmpty == false
                )
            },
            locale: Locale.current.identifier
        )
        let data = try await request(path: "api/guardian", method: "POST", body: body)
        return try decoder.decode(GuardianReport.self, from: data)
    }

    private func request<Body: Encodable>(path: String, method: String, body: Body) async throws -> Data {
        guard let baseURL else { throw VercelExtractionError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VercelExtractionError.badResponse
        }
        return data
    }

    private func get(path: String) async throws -> Data {
        guard let baseURL else { throw VercelExtractionError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VercelExtractionError.badResponse
        }
        return data
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }
}

@MainActor
extension VoyaStore {
    func refreshInspiration() async {
        guard !isLoadingInspiration else { return }
        isLoadingInspiration = true
        defer { isLoadingInspiration = false }
        do {
            applyInspirationRelease(try await VoyaAgentService().inspirationRelease())
        } catch {
            // Keep the announcement or last ready release visible offline.
        }
    }

    func prepareInspiration(mood: String) async {
        guard !isLoadingInspiration else { return }
        isLoadingInspiration = true
        inspirationStories = []
        inspirationCuratorNote = ""
        defer { isLoadingInspiration = false }
        do {
            applyInspirationRelease(try await VoyaAgentService().prepareInspiration(mood: mood))
        } catch {
            if case VercelExtractionError.notConfigured = error {
                try? await Task.sleep(for: .seconds(1.2))
                let now = Date()
                let local = InspirationRelease(
                    id: UUID(),
                    status: "ready",
                    mood: mood,
                    stage: "ready",
                    progress: 1,
                    requestedAt: now,
                    updatedAt: now,
                    readyAt: now,
                    curatorNote: String(localized: "A small offline preview of journeys worth wanting."),
                    stories: InspirationStory.fallback,
                    usedAI: false,
                    error: nil,
                    agents: [
                        InspirationReleaseAgent(id: "scout", name: "Scout", state: "complete", detail: String(localized: "Found promising reasons to travel")),
                        InspirationReleaseAgent(id: "verifier", name: "Verifier", state: "complete", detail: String(localized: "Checked the source evidence")),
                        InspirationReleaseAgent(id: "editor", name: "Story Editor", state: "complete", detail: String(localized: "Prepared the travel stories")),
                        InspirationReleaseAgent(id: "curator", name: "Curator", state: "complete", detail: String(localized: "Shaped the collection"))
                    ]
                )
                applyInspirationRelease(local)
                return
            }
            inspirationRelease = InspirationRelease(
                id: UUID(),
                status: "failed",
                mood: mood,
                stage: "failed",
                progress: 0,
                requestedAt: Date(),
                updatedAt: Date(),
                readyAt: nil,
                curatorNote: nil,
                stories: nil,
                usedAI: false,
                error: String(localized: "Voya could not start the collection yet. Try again when the backend is available."),
                agents: []
            )
        }
    }

    private func applyInspirationRelease(_ release: InspirationRelease?) {
        inspirationRelease = release
        guard release?.status == "ready" else {
            inspirationStories = []
            inspirationCuratorNote = ""
            return
        }
        inspirationStories = release?.stories ?? []
        inspirationCuratorNote = release?.curatorNote ?? ""
    }

    @discardableResult
    func startMission(
        kind: AgentMissionKind,
        title: String,
        detail: String,
        tripID: UUID? = nil,
        inspirationID: String? = nil
    ) -> AgentMission {
        let now = Date()
        let mission = AgentMission(
            id: UUID(),
            tripId: tripID,
            inspirationId: inspirationID,
            kind: kind,
            title: title,
            detail: detail,
            status: .queued,
            createdAt: now,
            updatedAt: now,
            nextCheckAt: Calendar.current.date(byAdding: .hour, value: 6, to: now),
            assignedAgents: nil,
            resultTitle: nil,
            resultSummary: nil,
            resultActions: nil,
            requiresApproval: nil,
            lastRunAt: nil,
            runCount: nil,
            lastError: nil
        )
        agentMissions.insert(mission, at: 0)
        AgentMissionLocalStore.save(agentMissions)
        Task {
            let context = missionContext(tripID: tripID)
            if let synced = try? await VoyaAgentService().createMission(mission, context: context),
               let index = agentMissions.firstIndex(where: { $0.id == mission.id }) {
                agentMissions[index] = synced
                AgentMissionLocalStore.save(agentMissions)
            }
        }
        return mission
    }

    private func missionContext(tripID: UUID?) -> [String: String] {
        guard let tripID, let trip = trips.first(where: { $0.id == tripID }) else {
            return ["locale": VoyaAppLocale.currentIdentifier]
        }
        let stages = itinerary(for: trip).prefix(24).map { item in
            [item.kind.rawValue, item.title, item.location, item.status, item.startsAt?.ISO8601Format() ?? "time unknown"]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }.joined(separator: "\n")
        return [
            "locale": VoyaAppLocale.currentIdentifier,
            "trip": trip.title,
            "destination": trip.destination ?? "",
            "dates": trip.displayDates,
            "itinerary": stages
        ]
    }

    func completeMission(_ mission: AgentMission) {
        guard let index = agentMissions.firstIndex(where: { $0.id == mission.id }) else { return }
        agentMissions[index].status = .completed
        agentMissions[index].updatedAt = Date()
        AgentMissionLocalStore.save(agentMissions)
        Task {
            if let synced = try? await VoyaAgentService().updateMission(id: mission.id, status: .completed),
               let syncedIndex = agentMissions.firstIndex(where: { $0.id == synced.id }) {
                agentMissions[syncedIndex] = synced
                AgentMissionLocalStore.save(agentMissions)
            }
        }
    }

    func refreshAgentMissions() async {
        guard let remote = try? await VoyaAgentService().missions(), !remote.isEmpty else { return }
        let localOnly = agentMissions.filter { local in !remote.contains(where: { $0.id == local.id }) }
        agentMissions = (remote + localOnly).sorted { $0.updatedAt > $1.updatedAt }
        AgentMissionLocalStore.save(agentMissions)
    }

    func refreshGuardian(for trip: Trip) async {
        guard !refreshingGuardianTripIDs.contains(trip.id) else { return }
        if !agentMissions.contains(where: {
            $0.kind == .guardian
                && $0.tripId == trip.id
                && $0.status != .cancelled
                && $0.status != .failed
        }) {
            startMission(
                kind: .guardian,
                title: String(localized: "Keep \(trip.title) on track"),
                detail: String(localized: "Watch the journey as a whole and surface only changes that affect the next useful decision."),
                tripID: trip.id
            )
        }
        refreshingGuardianTripIDs.insert(trip.id)
        defer { refreshingGuardianTripIDs.remove(trip.id) }
        do {
            guardianReports[trip.id] = try await VoyaAgentService().guardian(trip: trip, itinerary: itinerary(for: trip))
        } catch {
            guardianReports[trip.id] = localGuardianReport(for: trip)
        }
    }

    private func localGuardianReport(for trip: Trip) -> GuardianReport {
        let missingTimes = trip.items.filter { $0.startsAt == nil }
        let findings = missingTimes.prefix(4).map {
            GuardianFinding(
                id: "missing-time-\($0.id.uuidString)",
                agent: "clerk",
                severity: "watch",
                title: String(localized: "Add timing for \($0.title)"),
                detail: String(localized: "Guardian needs a time to protect this connection."),
                itemId: $0.id
            )
        }
        return GuardianReport(
            generatedAt: Date(),
            status: findings.isEmpty ? "calm" : "watch",
            headline: findings.isEmpty ? String(localized: "Guardian is watching your journey") : String(localized: "Guardian is watching a few weak points"),
            summary: findings.isEmpty ? String(localized: "Everything currently looks coherent.") : String(localized: "Some itinerary details still need attention."),
            watchCount: trip.items.count,
            findings: findings,
            agents: [
                GuardianAgent(id: "sentinel", name: "Sentinel", responsibility: String(localized: "Live changes"), state: "watching"),
                GuardianAgent(id: "navigator", name: "Navigator", responsibility: String(localized: "Transfers"), state: "watching"),
                GuardianAgent(id: "clerk", name: "Clerk", responsibility: String(localized: "Booking details"), state: "watching"),
                GuardianAgent(id: "coordinator", name: "Coordinator", responsibility: String(localized: "Trip-wide impact"), state: "watching")
            ]
        )
    }
}

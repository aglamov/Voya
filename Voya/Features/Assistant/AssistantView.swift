import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

enum AssistantChatRole: String, Codable {
    case user
    case assistant
}

struct AssistantChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: AssistantChatRole
    var text: String
    var createdAt: Date
    var confidence: Double?
    var sources: [String]
    var isLocalOnly: Bool?

    init(
        id: UUID = UUID(),
        role: AssistantChatRole,
        text: String,
        createdAt: Date = Date(),
        confidence: Double? = nil,
        sources: [String] = [],
        isLocalOnly: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.confidence = confidence
        self.sources = sources
        self.isLocalOnly = isLocalOnly
    }
}

enum AssistantConversationStore {
    private static let schemaVersion = "assistant-conversation-v2"
    private static let maximumMessages = 24

    static func load(tripID: UUID?) -> [AssistantChatMessage] {
        guard let tripID,
              let data = UserDefaults.standard.data(forKey: key(for: tripID)),
              let messages = try? JSONDecoder().decode([AssistantChatMessage].self, from: data) else {
            return []
        }
        return Array(messages.suffix(maximumMessages))
    }

    static func save(_ messages: [AssistantChatMessage], tripID: UUID?) {
        guard let tripID,
              let data = try? JSONEncoder().encode(Array(messages.suffix(maximumMessages))) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key(for: tripID))
    }

    private static func key(for tripID: UUID) -> String {
        "\(schemaVersion)-\(tripID.uuidString)"
    }
}

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: VoyaStore
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""
    @State private var itemBeingViewed: ItineraryItem?
    @State private var assistantQuestion = ""
    @State private var conversation: [AssistantChatMessage] = []
    @State private var suggestedQuestions: [String] = []
    @State private var isBoardingPassImporterPresented = false
    @State private var boardingPassTarget: ItineraryItem?
    @State private var boardingPassPreviewURL: URL?
    @State private var boardingPassImportMessage: String?
    @State private var intelligence = AssistantIntelligence.empty
    @State private var isAnsweringQuestion = false
    @State private var focusedItemID: UUID?
    @State private var processingStage: AssistantProcessingStage = .local
    @State private var progressiveFlightInsights: [TravelAlert] = []

    private var trip: Trip? {
        store.currentOrUpcomingTrip ?? store.selectedTrip
    }

    private var itinerary: [ItineraryItem] {
        trip.map { store.itinerary(for: $0) } ?? []
    }

    private var nextItem: ItineraryItem? {
        let now = Date()
        return itinerary.first { item in
            guard let start = item.startsAt else { return false }
            return (item.endsAt ?? start) >= now
        } ?? itinerary.first
    }

    private var focusedItem: ItineraryItem? {
        guard let focusedItemID else { return nil }
        return itinerary.first { $0.id == focusedItemID }
    }

    private var assistantItem: ItineraryItem? {
        if let focusID = intelligence.journey.focusItemID,
           let item = itinerary.first(where: { $0.id == focusID }) {
            return item
        }
        return focusedItem ?? nextItem
    }

    private var stageNextItem: ItineraryItem? {
        guard let itemID = intelligence.journey.nextItemID else { return nil }
        return itinerary.first { $0.id == itemID }
    }

    private var checkInActions: [FlightCheckInAction] {
        let now = Date()
        return itinerary.compactMap { item -> FlightCheckInAction? in
            guard store.boardingPassDocument(for: item) == nil else {
                return nil
            }
            return FlightCheckInAction(item: item, now: now)
        }
    }

    private var boardingPassEntries: [AssistantBoardingPassEntry] {
        let now = Date()
        let soon = now.addingTimeInterval(48 * 60 * 60)
        return Array(itinerary.compactMap { item in
            guard item.kind == .flight,
                  let departsAt = item.startsAt,
                  departsAt > now,
                  now >= departsAt.addingTimeInterval(-24 * 60 * 60),
                  !FlightCheckInAction.isAlreadyCheckedIn(item) else {
                return nil
            }

            let document = store.boardingPassDocument(for: item)
            guard document != nil || departsAt <= soon else {
                return nil
            }

            return AssistantBoardingPassEntry(item: item, document: document)
        }.prefix(3))
    }

    private var intelligenceRefreshID: String {
        AssistantIntelligence.cacheKey(
            trip: trip,
            itinerary: itinerary,
            homeLocationName: homeLocationName,
            homeLocationAddress: homeLocationAddress
        )
    }

    private var isRefreshingIntelligence: Bool {
        store.refreshingAssistantIntelligenceKeys.contains(intelligenceRefreshID)
    }

    private var missionPollingID: String {
        store.agentMissions
            .map { "\($0.id.uuidString):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private var flightInsights: [TravelAlert] {
        let source = isRefreshingIntelligence
            ? progressiveFlightInsights
            : intelligence.alerts.filter {
            $0.id.hasPrefix("flight-reliability-")
                || $0.id.hasPrefix("flight-plane-")
                || $0.id.hasPrefix("flight-status-pending-")
        }

        let pendingItemIDs = Set(source.compactMap { insight -> String? in
            guard insight.id.hasPrefix("flight-status-pending-") else { return nil }
            return String(insight.id.dropFirst("flight-status-pending-".count))
        })

        return source.filter { insight in
            guard insight.id.hasPrefix("flight-plane-") else { return true }
            let itemID = String(insight.id.dropFirst("flight-plane-".count))
            return !pendingItemIDs.contains(itemID)
        }
    }

    private var conversationCard: some View {
        AssistantConversationCard(
            question: $assistantQuestion,
            messages: conversation,
            isAnswering: isAnsweringQuestion,
            prompts: quickPrompts,
            onPrompt: { prompt in
                Task {
                    await submitAssistantQuestion(prompt)
                }
            },
            onSend: {
                Task {
                    await submitAssistantQuestion(assistantQuestion)
                }
            },
            onClear: {
                conversation = []
                AssistantConversationStore.save([], tripID: trip?.id)
            }
        )
    }

    private var headerSubtitle: String {
        guard trip != nil else {
            return String(localized: "Your trip at a glance")
        }

        let phase = intelligence.journey.phaseLabel
        guard intelligence.journey.focusItemID != nil,
              let stageTitle = intelligence.journey.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else {
            return phase
        }
        return "\(phase) · \(stageTitle)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HeaderBar(title: "Assistant", subtitle: headerSubtitle)

                if let trip {
                    AssistantJourneyHeroCard(
                        trip: trip,
                        journey: intelligence.journey,
                        assessment: intelligence.assessment,
                        isRefreshing: isRefreshingIntelligence
                    )

                    TripGuardianCard(
                        report: store.guardianReports[trip.id],
                        isRefreshing: store.refreshingGuardianTripIDs.contains(trip.id)
                    ) {
                        Task { await store.refreshGuardian(for: trip) }
                    }

                    AgentMissionBoardCard(
                        trip: trip,
                        missions: store.agentMissions.filter { $0.tripId == nil || $0.tripId == trip.id },
                        onStart: { kind, title, detail in
                            store.startMission(kind: kind, title: title, detail: detail, tripID: trip.id)
                        },
                        onComplete: store.completeMission
                    )

                    AssistantSyncStatusCard(
                        stage: processingStage,
                        isRefreshing: isRefreshingIntelligence || intelligence.isPlaceholder,
                        generatedAt: intelligence.generatedAt,
                        sourceCount: intelligence.sources.count,
                        usedAI: intelligence.aiAdvice?.usedAI == true,
                        onRefresh: {
                            Task {
                                await refreshAssistantIntelligenceIfNeeded(forceRefresh: true)
                            }
                        }
                    )

                    if let assistantItem {
                        Button {
                            itemBeingViewed = assistantItem
                        } label: {
                            AssistantCurrentStageCard(
                                journey: intelligence.journey,
                                item: assistantItem,
                                nextItem: stageNextItem,
                                isRefreshing: isRefreshingIntelligence
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    conversationCard

                    if !intelligence.environment.isEmpty {
                        AssistantEnvironmentCard(signals: intelligence.environment) { signal in
                            if let actionURL = signal.actionURL {
                                openURL(actionURL)
                            } else if let itemID = signal.itemID,
                                      let item = itinerary.first(where: { $0.id == itemID }) {
                                itemBeingViewed = item
                            }
                        }
                    }

                    AssistantActionPlanCard(recommendations: intelligence.recommendations) { recommendation in
                        guard let itemID = recommendation.itemID,
                              let item = itinerary.first(where: { $0.id == itemID }) else {
                            return
                        }
                        itemBeingViewed = item
                    }
                } else {
                    EmptyTripsCard(
                        title: "No trip to watch",
                        message: "Import a confirmation and Voya will turn the itinerary into stages, local context, risks, and a practical plan.",
                        symbol: "message.badge"
                    )
                    conversationCard
                }

                if trip != nil {
                    AssistantTripRisksCard(
                        alerts: intelligence.alerts,
                        aiAdvice: isRefreshingIntelligence ? nil : intelligence.aiAdvice,
                        isRefreshing: isRefreshingIntelligence
                    )
                }

                if !flightInsights.isEmpty {
                    AssistantFlightInsightsCard(insights: flightInsights)
                }

                if !checkInActions.isEmpty {
                    AssistantCheckInCard(actions: checkInActions) { action in
                        openURL(action.checkInURL)
                    }
                }

                if !boardingPassEntries.isEmpty {
                    AssistantBoardingPassCard(
                        entries: boardingPassEntries,
                        message: boardingPassImportMessage,
                        onAdd: { item in
                            boardingPassImportMessage = nil
                            boardingPassTarget = item
                            isBoardingPassImporterPresented = true
                        },
                        onOpen: { document in
                            boardingPassPreviewURL = SourceDocumentPreviewer.temporaryURL(for: document.sourceFile)
                        },
                        onOpenFlight: { item in
                            itemBeingViewed = item
                        }
                    )
                }

            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .sheet(item: $itemBeingViewed) { item in
            ItineraryItemDetailView(
                tripID: store.trips.first(where: { trip in
                    trip.items.contains(where: { $0.id == item.id })
                })?.id,
                item: item,
                sourceDocument: store.sourceDocument(for: item)
            ) { draft in
                store.updateItineraryItem(
                    item,
                    kind: draft.kind,
                    title: draft.title,
                    flightNumber: draft.flightNumber,
                    startsAt: draft.effectiveStartsAt,
                    endsAt: draft.effectiveEndsAt,
                    startsAtTimeZoneOffsetSeconds: draft.startsAtTimeZoneOffsetSeconds,
                    endsAtTimeZoneOffsetSeconds: draft.endsAtTimeZoneOffsetSeconds,
                    location: draft.location,
                    status: draft.status,
                    confirmationCode: draft.confirmationCode,
                    providerName: draft.providerName
                )
            } onDelete: {
                store.deleteItineraryItem(item)
            }
        }
        .fileImporter(
            isPresented: $isBoardingPassImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleBoardingPassImport(result)
        }
        .quickLookPreview($boardingPassPreviewURL)
        .onAppear {
            consumeAssistantFocus()
            loadAssistantConversation()
        }
        .onChange(of: store.assistantFocusItemID) { _, _ in
            consumeAssistantFocus()
        }
        .onChange(of: trip?.id) { _, _ in
            loadAssistantConversation()
        }
        .task(id: intelligenceRefreshID) {
            async let intelligenceTask: Void = refreshAssistantIntelligenceIfNeeded()
            async let missionTask: Void = store.refreshAgentMissions()
            if let trip {
                await store.refreshGuardian(for: trip)
            }
            await intelligenceTask
            await missionTask
        }
        .task(id: missionPollingID) {
            let hasRunningMission = store.agentMissions.contains { $0.status == .queued || $0.status == .running }
            guard hasRunningMission else { return }
            try? await Task.sleep(for: .seconds(3))
            await store.refreshAgentMissions()
        }
    }

    private var quickPrompts: [String] {
        let stagePrompts: [String]
        switch intelligence.journey.phase {
        case .active:
            stagePrompts = [
                String(localized: "What matters right now?"),
                String(localized: "What comes next?"),
                String(localized: "Are there risks nearby?"),
                String(localized: "How do I reach the next stage?")
            ]
        case .between:
            stagePrompts = [
                String(localized: "When should I leave?"),
                String(localized: "What comes next?"),
                String(localized: "Could I be late?"),
                String(localized: "What is nearby?")
            ]
        case .completed:
            stagePrompts = [
                String(localized: "What should I check after the trip?"),
                String(localized: "Which records should I keep?"),
                String(localized: "Are any risks unresolved?")
            ]
        case .planning, .preparing:
            stagePrompts = [
                String(localized: "What should I do next?"),
                String(localized: "When should I leave?"),
                String(localized: "What are the risks?"),
                String(localized: "What should I pack?")
            ]
        }

        var seen = Set<String>()
        return (suggestedQuestions + (intelligence.aiAdvice?.suggestedQuestions ?? []) + stagePrompts)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(4)
            .map { $0 }
    }

    private func loadAssistantConversation() {
        conversation = AssistantConversationStore.load(tripID: trip?.id)
        suggestedQuestions = intelligence.aiAdvice?.suggestedQuestions ?? []
    }

    private func consumeAssistantFocus() {
        guard let itemID = store.assistantFocusItemID,
              let item = itinerary.first(where: { $0.id == itemID }) else {
            return
        }

        focusedItemID = itemID
        assistantQuestion = "\(String(localized: "What should I do next?")) \(item.title)"
        store.assistantFocusItemID = nil
    }

    private func answer(for question: String) -> String {
        let normalized = question.lowercased()
        guard let trip else {
            return String(localized: "Import a confirmation first. After that I can watch timing, route choices, flight status, and missing booking fields.")
        }

        if shouldKeepQuestionLocal(question) {
            if let item = itinerary.first(where: {
                $0.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            }), let code = item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return String(localized: "The booking reference for \(item.title) is \(code). Voya keeps booking references on this device and does not send them to the AI service.")
            }
            return String(localized: "No booking reference is saved for this trip yet. Open the relevant itinerary item to add it; Voya will keep it on this device.")
        }

        if containsAny(normalized, ["delay", "задерж"]) {
            guard let flight = itinerary.first(where: {
                $0.kind == .flight && ItineraryPhase(item: $0) != .past
            }) else {
                return String(localized: "There is no upcoming flight in \(trip.title), so no flight connection is currently at risk.")
            }

            let liveStatus = intelligence.alerts.first(where: {
                $0.id.hasSuffix(flight.id.uuidString) && $0.id.hasPrefix("flight-status-")
            })
            let followingItem = itinerary
                .drop(while: { $0.id != flight.id })
                .dropFirst()
                .first
            let connection = followingItem.map {
                String(localized: "The next saved stage is \($0.title) at \($0.displayTime); recheck its transfer if the arrival changes.")
            } ?? String(localized: "There is no saved onward stage to protect after this flight.")
            let status = liveStatus.map { "\($0.title). \($0.message)" }
                ?? String(localized: "No live delay is confirmed in the available provider data.")
            return String(localized: "\(status) \(connection) Keep the airline booking source available for rebooking or support.")
        }

        if containsAny(normalized, ["flight", "рейс", "перелет", "перелёт"]) {
            if let flight = itinerary.first(where: { $0.kind == .flight && ItineraryPhase(item: $0) != .past }) {
                if let checkInAction = FlightCheckInAction(item: flight) {
                    let booking = checkInAction.confirmationCode == nil
                        ? String(localized: "Have the booking reference / PNR and passenger last name ready.")
                        : String(localized: "The booking reference is saved locally; have the passenger last name ready.")
                    return String(localized: "Online check-in should be open for \(checkInAction.flightNumber). \(booking) Use the check-in card in Assistant for the airline link.")
                }
                return String(localized: "Keep \(flight.title) open in the trip. If the provider reports a delay, Voya compares the new arrival with the next item and keeps the booking source handy for airline support.")
            }
            return String(localized: "There is no upcoming flight in \(trip.title). I will focus on route timing and check-in reminders instead.")
        }

        if containsAny(normalized, ["leave", "route", "выез", "выех", "маршрут", "добрат"]) {
            if let routeAlert = intelligence.alerts.first(where: { $0.sourceTitle == String(localized: "Mobility plan") }) {
                return String(localized: "\(routeAlert.title). \(routeAlert.message)")
            }
            if let assistantItem {
                return String(localized: "For \(assistantItem.title), use the transfer card in Trips for live timing. Taxi and car stay concise; public transit shows the line, departure time, and stop to get off.")
            }
            return String(localized: "Add a timed itinerary item and route guidance will appear around it.")
        }

        if containsAny(normalized, ["pack", "wear", "weather", "clothes", "погод", "взять", "одеть", "упаков"]) {
            let items = intelligence.weather.items.joined(separator: " ")
            return String(localized: "\(intelligence.weather.recommendation) \(items)")
        }

        if containsAny(normalized, ["alert", "risk", "ready", "риск", "опас", "готов", "проблем"]) {
            return String(localized: "\(intelligence.assessment.title). \(intelligence.assessment.detail)")
        }

        if let assistantItem {
            return String(localized: "Next: \(assistantItem.title) at \(assistantItem.displayTime). Check the place, route, and status fields; if anything is uncertain, open the item and correct it before travel day.")
        }

        return String(localized: "\(trip.title) is saved, but it needs timed itinerary items before I can produce useful live guidance.")
    }

    private func containsAny(_ value: String, _ fragments: [String]) -> Bool {
        fragments.contains { value.contains($0) }
    }

    private func shouldKeepQuestionLocal(_ question: String) -> Bool {
        let normalized = question.lowercased()
        let containsPrivateLabel = containsAny(
            normalized,
            ["pnr", "booking reference", "confirmation code", "код бро", "номер бро", "код подтвержд"]
        )
        let containsSavedReference = itinerary
            .compactMap(\.confirmationCode)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .contains { normalized.contains($0) }
        return containsPrivateLabel || containsSavedReference
    }

    private func handleBoardingPassImport(_ result: Result<[URL], Error>) {
        guard let boardingPassTarget,
              case .success(let urls) = result,
              let url = urls.first else {
            return
        }

        do {
            let sourceFile = try SourceDocumentFile.imported(from: url)
            store.attachBoardingPass(sourceFile, to: boardingPassTarget)
            boardingPassImportMessage = nil
        } catch {
            boardingPassImportMessage = String(localized: "Could not attach this boarding pass.")
        }
    }

    @MainActor
    private func refreshAssistantIntelligenceIfNeeded(forceRefresh: Bool = false) async {
        let cacheKey = intelligenceRefreshID

        if let cached = store.assistantIntelligenceCache[cacheKey] {
            intelligence = cached
            if !forceRefresh, cached.isFresh(for: trip) {
                processingStage = .complete
                return
            }
        }

        let builder = AssistantIntelligenceBuilder(store: store)
        intelligence = builder.localSnapshot(trip: trip, itinerary: itinerary)
        processingStage = .local
        progressiveFlightInsights = []

        guard !store.refreshingAssistantIntelligenceKeys.contains(cacheKey) else {
            return
        }

        store.refreshingAssistantIntelligenceKeys.insert(cacheKey)
        defer {
            store.refreshingAssistantIntelligenceKeys.remove(cacheKey)
        }

        let refreshed = await builder.build(
            trip: trip,
            itinerary: itinerary,
            homeLocationName: homeLocationName,
            homeLocationAddress: homeLocationAddress,
            modelContext: modelContext,
            onProgress: { stage in
                processingStage = stage
            },
            onFlightInsights: { insights in
                progressiveFlightInsights = insights
            }
        )
        store.assistantIntelligenceCache[cacheKey] = refreshed
        intelligence = refreshed
        if let prompts = refreshed.aiAdvice?.suggestedQuestions, !prompts.isEmpty {
            suggestedQuestions = prompts
        }
        processingStage = .complete
    }

    @MainActor
    private func submitAssistantQuestion(_ question: String) async {
        let trimmedQuestion = String(
            question
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(2_000)
        )
        guard !trimmedQuestion.isEmpty, !isAnsweringQuestion else {
            return
        }

        let localOnly = shouldKeepQuestionLocal(trimmedQuestion) || trip == nil
        let priorConversation = conversation
            .filter { $0.isLocalOnly != true }
            .suffix(12)
            .map {
                AssistantConversationTurn(role: $0.role.rawValue, content: $0.text)
            }

        appendConversationMessage(
            AssistantChatMessage(
                role: .user,
                text: trimmedQuestion,
                isLocalOnly: localOnly
            )
        )
        assistantQuestion = ""

        let localAnswer = answer(for: trimmedQuestion)
        guard trip != nil, !localOnly else {
            appendConversationMessage(
                AssistantChatMessage(
                    role: .assistant,
                    text: localAnswer,
                    sources: trip == nil ? [] : [String(localized: "Local itinerary")],
                    isLocalOnly: true
                )
            )
            return
        }

        isAnsweringQuestion = true
        defer {
            isAnsweringQuestion = false
        }

        if intelligence.isPlaceholder {
            await refreshAssistantIntelligenceIfNeeded()
        }

        let builder = AssistantIntelligenceBuilder(store: store)
        if let advice = await builder.answerQuestion(
            trimmedQuestion,
            trip: trip,
            itinerary: itinerary,
            intelligence: intelligence,
            conversation: priorConversation
        ) {
            if let prompts = advice.suggestedQuestions, !prompts.isEmpty {
                suggestedQuestions = prompts
            }
            appendConversationMessage(
                AssistantChatMessage(
                    role: .assistant,
                    text: advice.answer,
                    confidence: advice.usedAI ? advice.confidence : nil,
                    sources: advice.answerSources ?? [],
                    isLocalOnly: false
                )
            )
        } else {
            appendConversationMessage(
                AssistantChatMessage(
                    role: .assistant,
                    text: localAnswer,
                    sources: Array(intelligence.sources.map(\.title).prefix(3)),
                    isLocalOnly: false
                )
            )
        }
    }

    private func appendConversationMessage(_ message: AssistantChatMessage) {
        conversation = Array((conversation + [message]).suffix(24))
        AssistantConversationStore.save(conversation, tripID: trip?.id)
    }
}

private struct TripGuardianCard: View {
    let report: GuardianReport?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var accent: Color {
        switch report?.status {
        case "action": .voyaCoral
        case "watch": .voyaGold
        default: .voyaTeal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip Guardian")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(report?.headline ?? String(localized: "Preparing the journey watch"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
                Spacer()
                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView().tint(accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            Text(report?.summary ?? String(localized: "Sentinel, Navigator, Clerk, and Coordinator are checking the trip."))
                .font(.subheadline)
                .foregroundStyle(Color.voyaMuted)

            if let report {
                HStack(spacing: 8) {
                    Label("\(report.watchCount) watched", systemImage: "eye")
                    Label("\(report.agents.count) agents", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)

                ForEach(report.findings.prefix(3)) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(finding.severity == "action" ? Color.voyaCoral : finding.severity == "watch" ? Color.voyaGold : Color.voyaTeal)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(Color.voyaMuted)
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
}

private struct AgentMissionBoardCard: View {
    let trip: Trip
    let missions: [AgentMission]
    let onStart: (AgentMissionKind, String, String) -> Void
    let onComplete: (AgentMission) -> Void
    @State private var draft = ""

    private var activeMissions: [AgentMission] {
        missions.filter {
            $0.status == .queued || $0.status == .active || $0.status == .running || $0.status == .waiting
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Missions")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Give Voya an outcome to keep working on.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
                Spacer()
                Text("\(activeMissions.count) active")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.voyaMint)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                TextField("Watch, find, prepare…", text: $draft)
                    .font(.subheadline.weight(.medium))
                    .submitLabel(.done)
                    .onSubmit(startDraft)
                Button(action: startDraft) {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.voyaMuted : Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .padding(.leading, 6)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    missionPreset("Watch my connection", kind: .guardian, symbol: "arrow.triangle.branch")
                    missionPreset("Prepare a plan B", kind: .recovery, symbol: "lifepreserver")
                    missionPreset("Plan a free evening", kind: .concierge, symbol: "moon.stars")
                }
            }

            ForEach(activeMissions.prefix(4)) { mission in
                HStack(spacing: 11) {
                    Image(systemName: mission.kind.symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                        .frame(width: 36, height: 36)
                        .background(Color.voyaMint)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                            .lineLimit(1)
                        Text(mission.detail)
                            .font(.caption)
                            .foregroundStyle(Color.voyaMuted)
                            .lineLimit(mission.resultSummary == nil ? 2 : 1)
                        if let result = mission.resultSummary {
                            Text(result)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(mission.requiresApproval == true ? Color.voyaGold : Color.voyaTeal)
                                .lineLimit(3)
                        } else {
                            Text(missionStatus(mission))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                        }
                    }
                    Spacer(minLength: 4)
                    Button { onComplete(mission) } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.headline)
                            .foregroundStyle(Color.voyaMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private func missionPreset(_ title: String, kind: AgentMissionKind, symbol: String) -> some View {
        Button {
            onStart(kind, title, String(localized: "Voya will keep this mission active for \(trip.title) and surface the next useful decision."))
        } label: {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(Color.voyaSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func startDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onStart(.planning, title, String(localized: "Coordinator will route this mission to the right Voya specialists."))
        draft = ""
    }

    private func missionStatus(_ mission: AgentMission) -> String {
        switch mission.status {
        case .queued: String(localized: "Queued for Voya's team")
        case .running: String(localized: "Agents are working")
        case .active: String(localized: "Watching in the background")
        case .waiting: String(localized: "Waiting for your decision")
        case .completed: String(localized: "Completed")
        case .failed: mission.lastError ?? String(localized: "Needs another attempt")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}

struct AssistantBoardingPassEntry: Identifiable {
    var id: UUID { item.id }
    let item: ItineraryItem
    let document: SourceDocument?
}

struct AssistantJourneyHeroCard: View {
    let trip: Trip
    let journey: AssistantJourneyStage
    let assessment: AssistantTripAssessment
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(journey.phaseLabel, systemImage: journey.phase.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMint)

                    Text(displayTripTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(overviewText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, journey.progress)))
                        .stroke(Color.voyaMint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    if isRefreshing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("\(Int((journey.progress * 100).rounded()))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 58, height: 58)
            }

            VStack(spacing: 8) {
                ProgressView(value: journey.progress)
                    .tint(Color.voyaMint)
                    .background(.white.opacity(0.14))
                    .clipShape(Capsule())

                HStack {
                    Text(progressText)
                    Spacer()
                    Text(trip.displayDates)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 9) {
                AssistantHeroMetricPill(title: "Stage", value: journey.phaseLabel)
                AssistantHeroMetricPill(title: "Risk", value: assessment.riskLabel)
                AssistantHeroMetricPill(title: "Focus", value: focusMetric)
            }
            .foregroundStyle(.white)
        }
        .padding(19)
        .background(
            LinearGradient(
                colors: [Color.voyaInk, Color.voyaInk.opacity(0.90), Color.voyaTeal.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 14)
    }

    private var overviewText: String {
        if isRefreshing {
            return String(localized: "Refreshing the journey, local context, and risks.")
        }
        if let destination = trip.destination?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           destination.caseInsensitiveCompare(trip.title.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
            return String(localized: "\(destination) · \(assessment.detail)")
        }
        return assessment.detail
    }

    private var displayTripTitle: String {
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = title.lowercased()
        if title.isEmpty || normalized == "unknown destination" || normalized == "unknown trip" {
            return String(localized: "Trip needs details")
        }
        return title
    }

    private var progressText: String {
        guard journey.totalItems > 0 else {
            return String(localized: "Itinerary is being prepared")
        }
        return String(localized: "\(journey.completedItems) of \(journey.totalItems) stages complete")
    }

    private var focusMetric: String {
        if journey.phase == .planning, journey.totalItems > 0 {
            return String(localized: "Add time")
        }
        return journey.timeSummary?.nilIfEmpty
            ?? String(localized: "Set")
    }
}

private struct AssistantHeroMetricPill: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .opacity(0.72)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AssistantSyncStatusCard: View {
    let stage: AssistantProcessingStage
    let isRefreshing: Bool
    let generatedAt: Date
    let sourceCount: Int
    let usedAI: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill((isRefreshing ? Color.voyaSky : Color.voyaTeal).opacity(0.12))
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.voyaSky)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(isRefreshing ? stageTitle : String(localized: "Trip context is current"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                Text(detailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isRefreshing ? Color.voyaMuted : Color.voyaInk)
                    .frame(width: 40, height: 40)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .accessibilityLabel(Text("Refresh trip context"))
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
    }

    private var stageTitle: String {
        switch stage {
        case .local: String(localized: "Reading saved trip data")
        case .flights: String(localized: "Checking flights")
        case .routes: String(localized: "Checking routes")
        case .weather: String(localized: "Checking local conditions")
        case .aiReview: String(localized: "Reviewing the whole journey")
        case .complete: String(localized: "Trip context is current")
        }
    }

    private var detailText: String {
        if isRefreshing {
            return String(localized: "You can keep using the assistant while sources refresh.")
        }
        let sourceText = sourceCount == 1
            ? String(localized: "1 source")
            : String(localized: "\(sourceCount) sources")
        let aiText = usedAI ? String(localized: " · AI review") : ""
        return String(localized: "\(sourceText)\(aiText) · Updated \(MomentDateFormatter.time.string(from: generatedAt))")
    }
}

struct AssistantCurrentStageCard: View {
    let journey: AssistantJourneyStage
    let item: ItineraryItem
    let nextItem: ItineraryItem?
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: item.kind.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(item.kind.timelineAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(stageEyebrow)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.kind.timelineAccent)
                    Text(journey.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let timing = journey.timingContext ?? journey.timeSummary {
                        Text(timing)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.voyaMuted)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                    .padding(.top, 4)
            }

            Text(journey.detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                if let location = journey.location {
                    AssistantBriefRow(symbol: "mappin.and.ellipse", text: location)
                }
                if let status = journey.status {
                    AssistantBriefRow(symbol: "info.circle.fill", text: status)
                }
                if let nextItem, nextItem.id != item.id {
                    AssistantBriefRow(
                        symbol: "arrow.right.circle.fill",
                        text: String(localized: "After this: \(nextItem.title) · \(nextItem.displayTime)")
                    )
                }
            }
            .padding(13)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if isRefreshing {
                Label("Live details are refreshing", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: .black.opacity(0.055), radius: 17, y: 9)
    }

    private var stageEyebrow: String {
        switch journey.phase {
        case .active: String(localized: "Current stage")
        case .between: String(localized: "Next stage")
        case .preparing: String(localized: "Trip starts here")
        case .planning: String(localized: "Needs planning")
        case .completed: String(localized: "Last stage")
        }
    }
}

struct AssistantEnvironmentCard: View {
    let signals: [AssistantEnvironmentSignal]
    let onSelect: (AssistantEnvironmentSignal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "location.magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaSky)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Around this stage")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Place, conditions, movement, and nearby activity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                    Button {
                        onSelect(signal)
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: signal.kind.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(signal.severity.color)
                                .frame(width: 32, height: 32)
                                .background(signal.severity.color.opacity(0.10))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(signal.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.voyaMuted)
                                Text(signal.value)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.voyaInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let detail = signal.detail?.nilIfEmpty {
                                    Text(detail)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.voyaMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 6)

                            if signal.actionURL != nil {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.voyaMuted)
                            } else if signal.itemID != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.voyaMuted)
                            }
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < signals.count - 1 {
                        Divider().padding(.leading, 43)
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct AssistantActionPlanCard: View {
    let recommendations: [AssistantRecommendation]
    let onSelect: (AssistantRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaPlum)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("The most useful actions, in travel order")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
            }

            if recommendations.isEmpty {
                Label("Preparing recommendations…", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 9) {
                    ForEach(recommendations) { recommendation in
                        if recommendation.itemID != nil {
                            Button {
                                onSelect(recommendation)
                            } label: {
                                recommendationRow(recommendation, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            recommendationRow(recommendation, showsDisclosure: false)
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

    private func recommendationRow(
        _ recommendation: AssistantRecommendation,
        showsDisclosure: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: recommendation.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(urgencyColor(recommendation.urgency))
                .frame(width: 32, height: 32)
                .background(urgencyColor(recommendation.urgency).opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.urgency.label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(urgencyColor(recommendation.urgency))
                Text(recommendation.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recommendation.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func urgencyColor(_ urgency: AssistantRecommendationUrgency) -> Color {
        switch urgency {
        case .now: Color.voyaCoral
        case .soon: Color.voyaGold
        case .later: Color.voyaTeal
        }
    }
}

struct AssistantNextBriefCard: View {
    let item: ItineraryItem
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.kind.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(item.kind.timelineAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Up next")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.kind.timelineAccent)
                    Text(item.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.displayTime)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                    .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What to know")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)

                if let location {
                    AssistantBriefRow(symbol: "mappin.and.ellipse", text: location)
                }
                AssistantBriefRow(symbol: "info.circle.fill", text: guidance)
                if let status {
                    AssistantBriefRow(symbol: "doc.text.fill", text: status)
                }
            }
            .padding(14)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            if isRefreshing {
                Label("Checking the latest details…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
    }

    private var location: String? {
        let value = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.localizedCaseInsensitiveContains("needed") else { return nil }
        return value
    }

    private var status: String? {
        item.status.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var guidance: String {
        switch item.kind {
        case .flight:
            return String(localized: "Allow time for the airport, and check the terminal and gate before you leave.")
        case .hotel:
            return String(localized: "Keep the address and check-in instructions handy for your arrival.")
        case .event:
            return String(localized: "Check the entrance, ticket, and how long it takes to reach the venue.")
        case .transit:
            return String(localized: "Check the departure stop and route shortly before you set off.")
        }
    }
}

private struct AssistantBriefRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.voyaMuted)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.voyaInk)
    }
}

struct AssistantSourcesProcessingCard: View {
    let stage: AssistantProcessingStage
    let isProcessing: Bool
    let advice: AssistantAIAdvice?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: isProcessing ? "sparkles" : "checkmark.seal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(isProcessing ? Color.voyaSky : Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isProcessing ? "Processing all sources" : "All-source analysis")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(isProcessing ? "Building a complete picture of the trip" : completionSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
            }

            if isProcessing {
                VStack(spacing: 10) {
                    processingRow("Flight status and documents", stage: .flights)
                    processingRow("Routes and critical connections", stage: .routes)
                    processingRow("Weather along the itinerary", stage: .weather)
                    processingRow("Final AI risk review", stage: .aiReview)
                }
                .padding(13)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(resultText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    @ViewBuilder
    private func processingRow(_ title: LocalizedStringKey, stage rowStage: AssistantProcessingStage) -> some View {
        HStack(spacing: 10) {
            if stage == rowStage {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.voyaSky)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: stage.rawValue > rowStage.rawValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(stage.rawValue > rowStage.rawValue ? Color.voyaTeal : Color.voyaLine)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(.subheadline.weight(stage == rowStage ? .semibold : .medium))
                .foregroundStyle(stage.rawValue >= rowStage.rawValue ? Color.voyaInk : Color.voyaMuted)
            Spacer(minLength: 0)
        }
    }

    private var completionSubtitle: String {
        guard let advice, advice.usedAI else {
            return String(localized: "Available sources collected")
        }
        if advice.isReliableEnoughToOverrideFacts {
            return String(localized: "OpenAI review · \(advice.confidencePercent)% confidence")
        }
        return String(localized: "OpenAI review needs verification · \(advice.confidencePercent)%")
    }

    private var resultText: String {
        if advice?.usedAI == true, advice?.isReliableEnoughToOverrideFacts == true {
            let sections = [advice?.nextItemDescription, advice?.riskOverview]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            if !sections.isEmpty {
                return sections.joined(separator: "\n\n")
            }
        }
        return String(localized: "Route, weather, booking, and provider data have been collected. The summary below is based on the available facts.")
    }
}

struct AssistantFlightInsightsCard: View {
    let insights: [TravelAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "airplane.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaSky)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Flight reliability and aircraft")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Recent punctuality and the assigned aircraft")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: insight.id.hasPrefix("flight-plane-") ? "location.fill" : "chart.bar.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(insight.severity.color)
                                .frame(width: 28, height: 28)
                                .background(insight.severity.color.opacity(0.10))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(insight.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.voyaInk)
                                Text(insight.message)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let url = insight.actionURL {
                            Link(destination: url) {
                                Label("Show aircraft on map", systemImage: "map.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.voyaSky)
                            }
                            .padding(.leading, 37)
                        }
                    }
                    .padding(.vertical, 11)

                    if index < insights.count - 1 {
                        Divider().padding(.leading, 37)
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct AssistantTripRisksCard: View {
    let alerts: [TravelAlert]
    let aiAdvice: AssistantAIAdvice?
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: risks.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(risks.isEmpty ? Color.voyaTeal : Color.voyaCoral)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip risks")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(riskSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer(minLength: 0)
            }

            if risks.isEmpty {
                Text(isRefreshing ? String(localized: "Checking the itinerary…") : String(localized: "Nothing important needs your attention right now."))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(risks.enumerated()), id: \.element.id) { index, alert in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: alert.severity.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(alert.severity.color)
                                .frame(width: 28, height: 28)
                                .background(alert.severity.color.opacity(0.10))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.voyaInk)
                                Text(alert.message)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 11)

                        if index < risks.count - 1 {
                            Divider().padding(.leading, 39)
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

    private var risks: [TravelAlert] {
        var seen = Set<String>()
        let reliableAIRisks = aiAdvice?.isReliableEnoughToOverrideFacts == true
            ? (aiAdvice?.additionalRisks ?? [])
            : []
        let aiRisks = reliableAIRisks.map { risk in
            TravelAlert(
                id: "ai-risk-\(risk.title)-\(risk.description)",
                title: risk.title,
                message: risk.description,
                severity: risk.severity == "action" ? .action : .watch
            )
        }

        return (alerts + aiRisks)
            .filter { $0.severity != .calm }
            .filter {
                !$0.id.hasPrefix("flight-plane-")
                    && !$0.id.hasPrefix("flight-reliability-")
                    && !$0.id.hasPrefix("flight-status-pending-")
            }
            .filter { alert in
                let key = alert.title
                    .lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                return seen.insert(key).inserted
            }
            .sorted { lhs, rhs in
                if severityRank(lhs.severity) != severityRank(rhs.severity) {
                    return severityRank(lhs.severity) > severityRank(rhs.severity)
                }
                return lhs.title < rhs.title
            }
    }

    private func severityRank(_ severity: AlertSeverity) -> Int {
        switch severity {
        case .calm: 0
        case .watch: 1
        case .action: 2
        }
    }

    private var riskSummary: String {
        if isRefreshing && risks.isEmpty {
            return String(localized: "Checking the whole trip")
        }
        if risks.isEmpty {
            return String(localized: "No current concerns")
        }
        return String(localized: "\(risks.count) things to think about before the trip")
    }
}

struct AssistantStatusCard: View {
    let trip: Trip?
    let nextItem: ItineraryItem?
    let intelligence: AssistantIntelligence
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: statusSymbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(intelligence.assessment.tone.color)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                MetricPill(title: "Alerts", value: "\(activeAlertCount)")
                MetricPill(title: "Risk", value: intelligence.assessment.riskLabel)
                MetricPill(
                    title: "Next",
                    value: nextItem?.startsAt.map {
                        ItineraryDateFormatter.displayClock(
                            date: $0,
                            timeZoneOffsetSeconds: nextItem?.startsAtTimeZoneOffsetSeconds
                        )
                    } ?? String(localized: "Set")
                )
            }
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 22, y: 14)
    }

    private var title: String {
        guard let trip else {
            return String(localized: "No active trip")
        }

        return intelligence.assessment.title.isEmpty ? String(localized: "\(trip.title) live support") : intelligence.assessment.title
    }

    private var subtitle: String {
        if isRefreshing {
            return String(localized: "Refreshing routes, flight status, weather, and readiness signals.")
        }

        if let nextItem {
            return String(localized: "Watching \(nextItem.title), route timing, and provider updates.")
        }

        return String(localized: "Import or add itinerary items to activate live trip support.")
    }

    private var statusSymbol: String {
        switch intelligence.assessment.tone {
        case .calm: "shield.checkered"
        case .watch: "clock.badge.exclamationmark"
        case .action: "exclamationmark.triangle.fill"
        }
    }

    private var activeAlertCount: Int {
        intelligence.alerts.filter { $0.severity != .calm }.count
    }
}

struct AssistantSummaryCard: View {
    let intelligence: AssistantIntelligence

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: intelligence.aiAdvice?.usedAI == true && intelligence.aiAdvice?.isReliableEnoughToOverrideFacts == true ? "sparkles" : "text.badge.checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !nextActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nextActions, id: \.self) { action in
                        Label(action, systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var summaryText: String {
        (intelligence.aiAdvice?.isReliableEnoughToOverrideFacts == true
            ? intelligence.aiAdvice?.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil)
            ?? intelligence.assessment.detail
    }

    private var nextActions: [String] {
        guard intelligence.aiAdvice?.isReliableEnoughToOverrideFacts == true else { return [] }
        return Array((intelligence.aiAdvice?.nextActions ?? []).prefix(3))
    }
}

struct AssistantAssessmentCard: View {
    let assessment: AssistantTripAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.voyaLine, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(100, assessment.score))) / 100)
                        .stroke(assessment.tone.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(assessment.scoreText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip assessment")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(assessment.detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                AssessmentSignalPill(title: "Ready", value: assessment.readyCount, tint: Color.voyaTeal)
                AssessmentSignalPill(title: "Watch", value: assessment.watchCount, tint: Color.voyaGold)
                AssessmentSignalPill(title: "Action", value: assessment.actionCount, tint: Color.voyaCoral)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct AssessmentSignalPill: View {
    let title: LocalizedStringKey
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.voyaInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AssistantWeatherPrepCard: View {
    let weather: AssistantWeatherPreparation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.sun.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(weather.severity.color)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(weather.title)
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(weather.summary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(weather.recommendation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voyaInk)
                .fixedSize(horizontal: false, vertical: true)

            if !weather.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(weather.items, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct AssistantSourceBreakdownCard: View {
    let sources: [AssistantSourceSummary]
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Signal sources", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
                Text(MomentDateFormatter.time.string(from: generatedAt))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
            }

            ForEach(sources) { source in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: source.severity.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(source.severity.color)
                        .frame(width: 30, height: 30)
                        .background(source.severity.color.opacity(0.10))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(source.title) · \(source.count)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                        Text(source.detail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct AssistantNextActionCard: View {
    let item: ItineraryItem

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.kind.symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(item.kind.timelineAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Next action")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.kind.timelineAccent)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(actionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var actionText: String {
        switch item.kind {
        case .flight:
            return String(localized: "Keep status, terminal, gate, and airport transfer visible.")
        case .hotel:
            return String(localized: "Check arrival route and check-in timing.")
        case .event:
            return String(localized: "Keep venue route, ticket, and start buffer ready.")
        case .transit:
            return String(localized: "Use the route card for line, departure time, and stop.")
        }
    }
}

struct AssistantCheckInCard: View {
    let actions: [FlightCheckInAction]
    let onOpen: (FlightCheckInAction) -> Void
    @State private var copiedBookingActionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Online check-in")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Registration should be open 24 hours before departure.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            ForEach(actions) { action in
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.flightNumber)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                            Text(action.item.displayTime)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer(minLength: 8)

                        if let airlineName = action.airlineName {
                            Text(airlineName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                                .lineLimit(1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let confirmationCode = action.confirmationCode {
                            HStack(spacing: 8) {
                                Label(String(localized: "Booking reference: \(confirmationCode)"), systemImage: "doc.text")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Button {
                                    copyBookingReference(confirmationCode, for: action)
                                } label: {
                                    Label(copiedBookingActionID == action.id ? String(localized: "Copied") : String(localized: "Copy"), systemImage: copiedBookingActionID == action.id ? "checkmark" : "doc.on.doc")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.voyaInk)
                                        .padding(.horizontal, 9)
                                        .frame(height: 30)
                                        .background(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Label("Booking reference / PNR", systemImage: "doc.text")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(action.requiredDetails.dropFirst(), id: \.self) { detail in
                            Label(detail, systemImage: "doc.text")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        onOpen(action)
                    } label: {
                        Label("Open airline check-in", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private func copyBookingReference(_ value: String, for action: FlightCheckInAction) {
        UIPasteboard.general.string = value
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedBookingActionID = action.id
        }
    }
}

struct AssistantBoardingPassCard: View {
    let entries: [AssistantBoardingPassEntry]
    let message: String?
    let onAdd: (ItineraryItem) -> Void
    let onOpen: (SourceDocument) -> Void
    let onOpenFlight: (ItineraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaCoral)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Boarding pass")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Keep the airport document attached to its flight.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(flightTitle(for: entry.item))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(2)
                            Text(entry.item.displayTime)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer(minLength: 8)

                        Text(entry.document == nil ? String(localized: "Missing") : String(localized: "Ready"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(entry.document == nil ? Color.voyaCoral : Color.voyaTeal)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background((entry.document == nil ? Color.voyaCoral : Color.voyaTeal).opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if let document = entry.document {
                        Text(document.fileName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Add it now so the QR or barcode is one tap away before boarding.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        if let document = entry.document {
                            Button {
                                onOpen(document)
                            } label: {
                                Label("Show", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .foregroundStyle(.white)
                                    .background(Color.voyaInk)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                onAdd(entry.item)
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .foregroundStyle(.white)
                                    .background(Color.voyaInk)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            onOpenFlight(entry.item)
                        } label: {
                            Image(systemName: "airplane")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Open flight"))
                    }
                }
                .padding(14)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private func flightTitle(for item: ItineraryItem) -> String {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Flight")
    }
}

struct AssistantAttentionCard: View {
    let items: [ItineraryItem]
    let onOpen: (ItineraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Review before travel", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.voyaInk)

            ForEach(items) { item in
                Button {
                    onOpen(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.kind.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.voyaCoral)
                            .frame(width: 30, height: 30)
                            .background(Color.voyaCoral.opacity(0.10))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(1)
                            Text(issueText(for: item))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.voyaMuted)
                    }
                    .padding(12)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private func issueText(for item: ItineraryItem) -> String {
        if item.startsAt == nil {
            return String(localized: "Time is missing")
        }
        if item.location.localizedCaseInsensitiveContains("needed") || item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Place needs confirmation")
        }
        return String(localized: "Status needs review")
    }
}

struct AssistantConversationCard: View {
    @Binding var question: String
    let messages: [AssistantChatMessage]
    let isAnswering: Bool
    let prompts: [String]
    let onPrompt: (String) -> Void
    let onSend: () -> Void
    let onClear: () -> Void
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaCoral)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Voya")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("A conversation grounded in this trip")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer(minLength: 8)

                if !messages.isEmpty {
                    Button {
                        isClearConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.voyaMuted)
                            .frame(width: 36, height: 36)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear conversation"))
                }
            }

            if messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask about the current stage, the next move, local conditions, risks, documents, or a change of plans.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Booking references stay on this device.", systemImage: "lock.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaTeal)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.voyaMint.opacity(0.66))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(messages.suffix(8))) { message in
                        AssistantChatBubble(message: message)
                    }

                    if isAnswering {
                        HStack {
                            Label("Thinking with live trip context", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.voyaInk)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(Color.voyaMint.opacity(0.76))
                                .clipShape(Capsule())
                            Spacer(minLength: 44)
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            onPrompt(prompt)
                        } label: {
                            Text(prompt)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .background(Color.voyaSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAnswering)
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Ask about this trip", text: $question, axis: .vertical)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(isAnswering)
                    .submitLabel(.send)
                    .onSubmit {
                        if !isAnswering {
                            onSend()
                        }
                    }

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(canSend ? Color.voyaCoral : Color.voyaMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(Text("Send question"))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear conversation", role: .destructive, action: onClear)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved Voya conversation for this trip from this device.")
        }
    }

    private var canSend: Bool {
        !isAnswering && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct AssistantChatBubble: View {
    let message: AssistantChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(message.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(message.role == .user ? .white : Color.voyaInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if message.role == .assistant, metadata != nil {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield.fill")
                        Text(metadata ?? "")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(message.role == .user ? Color.voyaInk : Color.voyaMint.opacity(0.76))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 17,
                    bottomLeadingRadius: message.role == .assistant ? 5 : 17,
                    bottomTrailingRadius: message.role == .user ? 5 : 17,
                    topTrailingRadius: 17,
                    style: .continuous
                )
            )

            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var metadata: String? {
        var parts: [String] = []
        if !message.sources.isEmpty {
            parts.append(message.sources.prefix(3).joined(separator: " · "))
        }
        if let confidence = message.confidence {
            parts.append(
                confidence >= 0.55
                    ? String(localized: "AI-assisted")
                    : String(localized: "AI answer needs verification")
            )
        }
        return parts.joined(separator: " · ").nilIfEmpty
    }
}

struct HomeBaseSettingsCard: View {
    @Binding var homeLocationName: String
    @Binding var homeLocationAddress: String
    @State private var draftName: String
    @State private var draftAddress: String
    @State private var didSave = false

    init(homeLocationName: Binding<String>, homeLocationAddress: Binding<String>) {
        _homeLocationName = homeLocationName
        _homeLocationAddress = homeLocationAddress
        _draftName = State(initialValue: homeLocationName.wrappedValue)
        _draftAddress = State(initialValue: homeLocationAddress.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Home base")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Default start and return point")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()
            }

            ClearableTextField("Place name", text: $draftName, prompt: "Home")
            ClearableTextField("Address", text: $draftAddress, prompt: "Street address, city, or Google Maps link", lineLimit: 2...4)

            Text("Trips use this address unless custom start or end points are set in trip details.")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.voyaMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    saveHomeBase()
                } label: {
                    Label(didSave ? String(localized: "Saved") : String(localized: "Save home base"), systemImage: didSave ? "checkmark" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(canSave ? Color.voyaInk : Color.voyaMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                if hasChanges {
                    Button {
                        resetDraft()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                            .frame(width: 44, height: 44)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Reset home base changes"))
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
        .onChange(of: draftName) { _, _ in didSave = false }
        .onChange(of: draftAddress) { _, _ in didSave = false }
    }

    private var normalizedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedAddress: String {
        draftAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        normalizedName != homeLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
            || normalizedAddress != homeLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        hasChanges
    }

    private func saveHomeBase() {
        guard canSave else {
            return
        }

        homeLocationName = normalizedName.isEmpty ? String(localized: "Home") : normalizedName
        homeLocationAddress = normalizedAddress
        withAnimation(.easeInOut(duration: 0.18)) {
            didSave = true
        }
    }

    private func resetDraft() {
        draftName = homeLocationName
        draftAddress = homeLocationAddress
        didSave = false
    }
}

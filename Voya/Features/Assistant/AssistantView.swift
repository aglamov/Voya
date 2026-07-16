import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: VoyaStore
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""
    @State private var itemBeingViewed: ItineraryItem?
    @State private var assistantQuestion = String(localized: "What if my flight is delayed?")
    @State private var assistantAnswer: String?
    @State private var isBoardingPassImporterPresented = false
    @State private var boardingPassTarget: ItineraryItem?
    @State private var boardingPassPreviewURL: URL?
    @State private var boardingPassImportMessage: String?
    @State private var intelligence = AssistantIntelligence.empty
    @State private var isAnsweringQuestion = false
    @State private var focusedItemID: UUID?
    @State private var processingStage: AssistantProcessingStage = .local

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
        focusedItem ?? nextItem
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Assistant", subtitle: trip?.title ?? String(localized: "Your trip at a glance"))

                Text("Identified immediately")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)

                if let assistantItem {
                    Button {
                        itemBeingViewed = assistantItem
                    } label: {
                        AssistantNextBriefCard(
                            item: assistantItem,
                            isRefreshing: isRefreshingIntelligence
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    EmptyTripsCard(
                        title: "No trip to watch",
                        message: "Import a confirmation and Voya will turn itinerary timing, alerts, and routes into assistant actions.",
                        symbol: "message.badge"
                    )
                }

                if isRefreshingIntelligence {
                    AssistantTripRisksCard(
                        alerts: intelligence.alerts,
                        aiAdvice: nil,
                        isRefreshing: true
                    )
                }

                AssistantSourcesProcessingCard(
                    stage: processingStage,
                    isProcessing: isRefreshingIntelligence || (trip != nil && intelligence.isPlaceholder),
                    advice: intelligence.aiAdvice
                )

                if !isRefreshingIntelligence && !intelligence.isPlaceholder {
                    AssistantWeatherPrepCard(weather: intelligence.weather)

                    AssistantTripRisksCard(
                        alerts: intelligence.alerts,
                        aiAdvice: intelligence.aiAdvice,
                        isRefreshing: false
                    )
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

                AssistantQuestionCard(
                    question: $assistantQuestion,
                    answer: assistantAnswer,
                    isAnswering: isAnsweringQuestion,
                    prompts: quickPrompts,
                    onPrompt: { prompt in
                        assistantQuestion = prompt
                        Task {
                            await submitAssistantQuestion(prompt)
                        }
                    },
                    onSend: {
                        Task {
                            await submitAssistantQuestion(assistantQuestion)
                        }
                    }
                )

                HomeBaseSettingsCard(
                    homeLocationName: $homeLocationName,
                    homeLocationAddress: $homeLocationAddress
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .sheet(item: $itemBeingViewed) { item in
            ItineraryItemDetailView(item: item, sourceDocument: store.sourceDocument(for: item)) { draft in
                store.updateItineraryItem(
                    item,
                    kind: draft.kind,
                    title: draft.title,
                    startsAt: draft.effectiveStartsAt,
                    endsAt: draft.effectiveEndsAt,
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
        }
        .onChange(of: store.assistantFocusItemID) { _, _ in
            consumeAssistantFocus()
        }
        .task(id: intelligenceRefreshID) {
            await refreshAssistantIntelligenceIfNeeded()
        }
    }

    private var quickPrompts: [String] {
        [
            String(localized: "What should I do next?"),
            String(localized: "When should I leave?"),
            String(localized: "What if my flight is delayed?"),
            String(localized: "What should I pack?")
        ]
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

        if normalized.contains("delay") || normalized.contains("flight") {
            if let flight = itinerary.first(where: { $0.kind == .flight && ItineraryPhase(item: $0) != .past }) {
                if let checkInAction = FlightCheckInAction(item: flight) {
                    let booking = checkInAction.confirmationCode.map { String(localized: "Use booking reference \($0) and the passenger last name.") } ?? String(localized: "Have the booking reference / PNR and passenger last name ready.")
                    return String(localized: "Online check-in should be open for \(checkInAction.flightNumber). \(booking) Use the check-in card in Assistant for the airline link.")
                }
                return String(localized: "Keep \(flight.title) open in the trip. If the provider reports a delay, Voya compares the new arrival with the next item and keeps the booking source handy for airline support.")
            }
            return String(localized: "There is no upcoming flight in \(trip.title). I will focus on route timing and check-in reminders instead.")
        }

        if normalized.contains("leave") || normalized.contains("route") {
            if let routeAlert = intelligence.alerts.first(where: { $0.sourceTitle == String(localized: "Mobility plan") }) {
                return String(localized: "\(routeAlert.title). \(routeAlert.message)")
            }
            if let assistantItem {
                return String(localized: "For \(assistantItem.title), use the transfer card in Trips for live timing. Taxi and car stay concise; public transit shows the line, departure time, and stop to get off.")
            }
            return String(localized: "Add a timed itinerary item and route guidance will appear around it.")
        }

        if normalized.contains("pack") || normalized.contains("wear") || normalized.contains("weather") || normalized.contains("clothes") {
            let items = intelligence.weather.items.joined(separator: " ")
            return String(localized: "\(intelligence.weather.recommendation) \(items)")
        }

        if normalized.contains("alert") || normalized.contains("risk") || normalized.contains("ready") {
            return String(localized: "\(intelligence.assessment.title). \(intelligence.assessment.detail)")
        }

        if let assistantItem {
            return String(localized: "Next: \(assistantItem.title) at \(assistantItem.displayTime). Check the place, route, and status fields; if anything is uncertain, open the item and correct it before travel day.")
        }

        return String(localized: "\(trip.title) is saved, but it needs timed itinerary items before I can produce useful live guidance.")
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
            }
        )
        store.assistantIntelligenceCache[cacheKey] = refreshed
        intelligence = refreshed
        processingStage = .complete
    }

    @MainActor
    private func submitAssistantQuestion(_ question: String) async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            return
        }

        assistantAnswer = answer(for: trimmedQuestion)
        guard trip != nil else {
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
            intelligence: intelligence
        ) {
            assistantAnswer = advice.answer
        }
    }
}

struct AssistantBoardingPassEntry: Identifiable {
    var id: UUID { item.id }
    let item: ItineraryItem
    let document: SourceDocument?
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
        advice?.usedAI == true
            ? String(localized: "OpenAI review complete")
            : String(localized: "Available sources collected")
    }

    private var resultText: String {
        if advice?.usedAI == true {
            let sections = [advice?.nextItemDescription, advice?.riskOverview]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            if !sections.isEmpty {
                return sections.joined(separator: "\n\n")
            }
        }
        return String(localized: "Route, weather, booking, and provider data have been collected. The summary below is based on the available facts.")
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
        let aiRisks = (aiAdvice?.additionalRisks ?? []).map { risk in
            TravelAlert(
                id: "ai-risk-\(risk.title)-\(risk.description)",
                title: risk.title,
                message: risk.description,
                severity: risk.severity == "action" ? .action : .watch
            )
        }

        return (alerts + aiRisks)
            .filter { $0.severity != .calm }
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
                MetricPill(title: "Next", value: nextItem?.startsAt.map { MomentDateFormatter.time.string(from: $0) } ?? String(localized: "Set"))
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
                Image(systemName: intelligence.aiAdvice?.usedAI == true ? "sparkles" : "text.badge.checkmark")
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
        intelligence.aiAdvice?.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? intelligence.assessment.detail
    }

    private var nextActions: [String] {
        Array((intelligence.aiAdvice?.nextActions ?? []).prefix(3))
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

struct AssistantQuestionCard: View {
    @Binding var question: String
    let answer: String?
    let isAnswering: Bool
    let prompts: [String]
    let onPrompt: (String) -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ask Voya", systemImage: "message.badge")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
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
                                .frame(height: 34)
                                .background(Color.voyaSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.voyaMuted : Color.voyaCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isAnswering {
                Label("Thinking with live trip context", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyaMint.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let answer {
                Text(answer)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyaMint.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
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

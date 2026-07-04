import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import UIKit
import Vision

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: VoyaStore
    @State private var selectedTab: VoyaTab = .inspire

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .inspire:
                    InspireView()
                case .trips:
                    TripsView()
                case .import:
                    ImportView(selectedTab: $selectedTab)
                case .assistant:
                    AssistantView()
                }
            }
            .safeAreaPadding(.bottom, 92)

            VoyaTabBar(selectedTab: $selectedTab)
        }
        .tint(.voyaTeal)
        .preferredColorScheme(.light)
        .onAppear {
            store.configure(modelContext: modelContext)
            if store.selectCurrentTripIfAvailable() {
                selectedTab = .trips
            }
        }
    }
}

private enum VoyaTab: String, CaseIterable, Identifiable {
    case inspire = "Inspire"
    case trips = "Trips"
    case `import` = "Import"
    case assistant = "Assistant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspire: String(localized: "Inspire")
        case .trips: String(localized: "Trips")
        case .import: String(localized: "Import")
        case .assistant: String(localized: "Assistant")
        }
    }

    var symbol: String {
        switch self {
        case .inspire: "sparkles"
        case .trips: "calendar"
        case .import: "tray.and.arrow.down"
        case .assistant: "message.badge"
        }
    }
}

private struct InspireView: View {
    @EnvironmentObject private var store: VoyaStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Voya", subtitle: "Tuesday, June 30")

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plan the trip that actually fits.")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .lineSpacing(1)
                                .foregroundStyle(Color.voyaInk)

                            Text("Budget, weather, flights, hotels, events, and calm trade-offs in one place.")
                                .font(.subheadline)
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "location.north.line.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [.voyaInk, .voyaTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.voyaMuted)
                            TextField("Warm 4-day trip under $700", text: $store.inspirationText, axis: .vertical)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(2...4)
                        }
                        .padding(14)
                        .background(.white.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(TripMood.allCases) { mood in
                                    MoodChip(mood: mood, isSelected: mood == store.selectedMood) {
                                        store.selectedMood = mood
                                    }
                                }
                            }
                        }

                        Button {
                        } label: {
                            HStack {
                                Text("Find strong options")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(colors: [.white, .voyaMint], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .foregroundStyle(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 14)

                SectionHeader(title: "Best matches", action: "See all")

                VStack(spacing: 14) {
                    ForEach(store.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct RecommendationCard: View {
    let recommendation: TripRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DestinationMark(destination: recommendation.destination, color: recommendation.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.destination)
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(recommendation.dates) · \(recommendation.fit)")
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()

                Text(recommendation.estimatedCost)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(recommendation.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(recommendation.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                ForEach(recommendation.details.prefix(3), id: \.self) { detail in
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            HStack(spacing: 12) {
                IconTextButton(title: "Compare", symbol: "slider.horizontal.3", style: .secondary)
                IconTextButton(title: "Booking links", symbol: "safari", style: .primary)
            }
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct TripsView: View {
    @EnvironmentObject private var store: VoyaStore
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""
    @State private var itemBeingViewed: ItineraryItem?
    @State private var transferBeingViewed: MobilityTransferContext?
    @State private var tripBeingEdited: Trip?
    @State private var tripAddingItem: Trip?
    @State private var tripListMode: TripListMode = .upcoming
    @State private var mobilityPlans: [String: MobilityPlan] = [:]
    @State private var loadingMobilityPlanIDs: Set<String> = []
    @State private var mobilityPlanErrors: [String: String] = [:]

    private enum TripListMode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case archive = "Archive"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .upcoming: String(localized: "Upcoming")
            case .archive: String(localized: "Archive")
            }
        }
    }

    private var displayedTrips: [Trip] {
        switch tripListMode {
        case .upcoming:
            store.activeTrips
        case .archive:
            store.archivedTrips
        }
    }

    private var displayedTrip: Trip? {
        if let selectedTrip = store.selectedTrip,
           displayedTrips.contains(where: { $0.id == selectedTrip.id }) {
            return selectedTrip
        }

        return displayedTrips.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(
                    title: "Trips",
                    subtitle: displayedTrip.map { "\($0.title), \($0.dates)" } ?? emptySubtitle
                )

                Picker("Trips", selection: $tripListMode) {
                    ForEach(TripListMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if let trip = displayedTrip {
                    TripHeroCard(trip: trip) {
                        tripBeingEdited = trip
                    }
                    .task(id: trip.id) {
                        await store.loadHeroImageIfNeeded(for: trip)
                    }

                    if displayedTrips.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(displayedTrips) { trip in
                                    TripChip(
                                        trip: trip,
                                        isSelected: trip.id == displayedTrip?.id
                                    ) {
                                        store.selectedTripID = trip.id
                                    }
                                }
                            }
                        }
                    }

                    let itinerary = store.itinerary(for: trip)
                    TripOperationsCard(trip: trip, itinerary: itinerary)

                    HStack {
                        Text("Timeline")
                            .font(.title3.bold())
                            .foregroundStyle(Color.voyaInk)
                        Spacer()
                        Button {
                            tripAddingItem = trip
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.voyaTeal)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(itinerary.enumerated()), id: \.element.id) { index, item in
                            if index == 0 {
                                if let context = VercelMobilityService.startTransferContext(
                                    for: trip,
                                    firstItem: item,
                                    defaultHomeAddress: homeLocationAddress,
                                    defaultHomeName: homeLocationName
                                ) {
                                    TransferRecommendationCard(
                                        context: context,
                                        phase: TransferPhase(context: context, plan: mobilityPlans[context.id]),
                                        plan: mobilityPlans[context.id],
                                        errorMessage: mobilityPlanErrors[context.id],
                                        isLoading: loadingMobilityPlanIDs.contains(context.id),
                                        onOpen: {
                                            transferBeingViewed = context
                                        },
                                        onRefresh: {
                                            Task {
                                                await loadMobilityPlan(context: context, forceRefresh: true)
                                            }
                                        }
                                    )
                                    .task(id: context.id) {
                                        await loadMobilityPlan(context: context)
                                    }
                                } else if shouldPromptForStartPoint(trip: trip, firstItem: item) {
                                    MissingStartPointCard {
                                        tripBeingEdited = trip
                                    }
                                }
                            }

                            TimelineRow(
                                item: item,
                                phase: ItineraryPhase(item: item),
                                isLast: index == itinerary.count - 1
                            ) {
                                itemBeingViewed = item
                            }

                            if index + 1 < itinerary.count,
                               let layover = FlightLayoverDisplay(arrivingFlight: item, departingFlight: itinerary[index + 1]) {
                                FlightLayoverCard(layover: layover)
                            }

                            if index + 1 < itinerary.count,
                               let context = VercelMobilityService.transferContext(from: item, to: itinerary[index + 1]) {
                                TransferRecommendationCard(
                                    context: context,
                                    phase: TransferPhase(
                                        context: context,
                                        plan: mobilityPlans[context.id],
                                        fallbackStart: item.endsAt ?? item.startsAt
                                    ),
                                    plan: mobilityPlans[context.id],
                                    errorMessage: mobilityPlanErrors[context.id],
                                    isLoading: loadingMobilityPlanIDs.contains(context.id),
                                    onOpen: {
                                        transferBeingViewed = context
                                    },
                                    onRefresh: {
                                        Task {
                                            await loadMobilityPlan(from: item, to: itinerary[index + 1], forceRefresh: true)
                                        }
                                    }
                                )
                                .task(id: context.id) {
                                    await loadMobilityPlan(from: item, to: itinerary[index + 1])
                                }
                            }

                            if index == itinerary.count - 1 {
                                if let context = VercelMobilityService.endTransferContext(
                                    for: trip,
                                    lastItem: item,
                                    defaultHomeAddress: homeLocationAddress,
                                    defaultHomeName: homeLocationName
                                ) {
                                    TransferRecommendationCard(
                                        context: context,
                                        phase: TransferPhase(context: context, plan: mobilityPlans[context.id]),
                                        plan: mobilityPlans[context.id],
                                        errorMessage: mobilityPlanErrors[context.id],
                                        isLoading: loadingMobilityPlanIDs.contains(context.id),
                                        onOpen: {
                                            transferBeingViewed = context
                                        },
                                        onRefresh: {
                                            Task {
                                                await loadMobilityPlan(context: context, forceRefresh: true)
                                            }
                                        }
                                    )
                                    .task(id: context.id) {
                                        await loadMobilityPlan(context: context)
                                    }
                                } else if shouldPromptForEndPoint(trip: trip, lastItem: item) {
                                    MissingEndPointCard {
                                        tripBeingEdited = trip
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                } else {
                    EmptyTripsCard(
                        title: tripListMode == .archive ? "Archive is empty" : "No upcoming trips",
                        message: tripListMode == .archive ? "Past trips will appear here after they end." : "Import a confirmation to build your next itinerary.",
                        symbol: tripListMode == .archive ? "archivebox" : "calendar.badge.plus"
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .onAppear {
            selectDisplayedTripIfNeeded()
        }
        .onChange(of: tripListMode) { _, _ in
            selectDisplayedTripIfNeeded()
        }
        .onChange(of: store.trips.count) { _, _ in
            selectDisplayedTripIfNeeded()
        }
        .sheet(item: $tripBeingEdited) { trip in
            EditTripView(trip: trip) { draft in
                store.updateTrip(
                    trip,
                    title: draft.title,
                    destination: draft.destination,
                    summary: draft.summary,
                    notes: draft.notes,
                    startLocationName: draft.startLocationName,
                    startLocationAddress: draft.startLocationAddress,
                    endLocationName: draft.endLocationName,
                    endLocationAddress: draft.endLocationAddress
                )
            } onDelete: {
                store.deleteTrip(trip)
            }
        }
        .sheet(item: $tripAddingItem) { trip in
            EditItineraryItemView(mode: .add, tripTitle: trip.title) { draft in
                store.addItineraryItem(
                    to: trip,
                    kind: draft.kind,
                    title: draft.title,
                    startsAt: draft.effectiveStartsAt,
                    endsAt: draft.effectiveEndsAt,
                    location: draft.location,
                    status: draft.status
                )
            }
        }
        .sheet(item: $itemBeingViewed) { item in
            ItineraryItemDetailView(item: item) { draft in
                store.updateItineraryItem(
                    item,
                    kind: draft.kind,
                    title: draft.title,
                    startsAt: draft.effectiveStartsAt,
                    endsAt: draft.effectiveEndsAt,
                    location: draft.location,
                    status: draft.status
                )
            } onDelete: {
                store.deleteItineraryItem(item)
            }
        }
        .sheet(item: $transferBeingViewed) { context in
            TransferDetailView(
                context: context,
                plan: mobilityPlans[context.id],
                errorMessage: mobilityPlanErrors[context.id],
                isLoading: loadingMobilityPlanIDs.contains(context.id),
                onRefresh: {
                    Task {
                        await loadMobilityPlan(context: context, forceRefresh: true)
                    }
                }
            )
            .task(id: context.id) {
                await loadMobilityPlan(context: context)
            }
        }
    }

    private var emptySubtitle: String {
        tripListMode == .archive ? String(localized: "No archived trips") : String(localized: "No upcoming trips")
    }

    private func selectDisplayedTripIfNeeded() {
        guard let firstTrip = displayedTrips.first else {
            return
        }

        if let selectedTrip = store.selectedTrip,
           displayedTrips.contains(where: { $0.id == selectedTrip.id }) {
            return
        }

        store.selectedTripID = firstTrip.id
    }

    @MainActor
    private func loadMobilityPlan(from originItem: ItineraryItem, to destinationItem: ItineraryItem, forceRefresh: Bool = false) async {
        guard let context = VercelMobilityService.transferContext(from: originItem, to: destinationItem) else {
            return
        }
        await loadMobilityPlan(context: context, forceRefresh: forceRefresh)
    }

    @MainActor
    private func loadMobilityPlan(context: MobilityTransferContext, forceRefresh: Bool = false) async {
        if !forceRefresh, mobilityPlans[context.id] != nil {
            return
        }
        guard !loadingMobilityPlanIDs.contains(context.id) else {
            return
        }

        loadingMobilityPlanIDs.insert(context.id)
        mobilityPlanErrors[context.id] = nil
        defer {
            loadingMobilityPlanIDs.remove(context.id)
        }

        do {
            mobilityPlans[context.id] = try await VercelMobilityService().planTransfer(context: context)
        } catch {
            mobilityPlanErrors[context.id] = String(localized: "Route timing unavailable")
        }
    }

    private func shouldPromptForStartPoint(trip: Trip, firstItem: ItineraryItem) -> Bool {
        firstItem.kind != .transit
            && trip.startLocationAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && homeLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !firstItem.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldPromptForEndPoint(trip: Trip, lastItem: ItineraryItem) -> Bool {
        trip.endLocationAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && homeLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastItem.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

private struct ImportView: View {
    @EnvironmentObject private var store: VoyaStore
    @Binding var selectedTab: VoyaTab
    @State private var isFileImporterPresented = false
    @State private var isPhotoImporterPresented = false
    @State private var isPasteImporterPresented = false

    private enum ScrollTarget {
        static let recognition = "import-recognition"
        static let review = "import-review"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HeaderBar(title: "Import", subtitle: "Add confirmation")

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Add confirmation")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.voyaInk)
                                Text("Paste text, choose a file, or read a photo.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 10)

                            Image(systemName: store.isExtractingConfirmation ? "wand.and.stars" : "tray.and.arrow.down.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.voyaInk)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            Button {
                                isFileImporterPresented = true
                            } label: {
                                ImportOption(symbol: "doc.text.magnifyingglass", title: "File", subtitle: "PDF or text", tint: .voyaTeal)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isPasteImporterPresented = true
                            } label: {
                                ImportOption(symbol: "text.alignleft", title: "Paste", subtitle: "Booking text", tint: .voyaGold)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isPhotoImporterPresented = true
                            } label: {
                                ImportOption(symbol: "photo.on.rectangle", title: "Photo", subtitle: "OCR from image", tint: .voyaCoral)
                            }
                            .buttonStyle(.plain)
                        }

                        if let importMessage = store.importMessage {
                            ImportMessageLabel(message: importMessage, isWorking: store.isExtractingConfirmation)
                        }
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                    if store.isExtractingConfirmation {
                        RecognitionAnimationCard(message: store.importMessage ?? "Recognizing confirmation...")
                            .id(ScrollTarget.recognition)
                    }

                    if let importSuccess = store.importSuccess {
                        ImportSuccessAnimationCard(success: importSuccess, actionTitle: "Import") {
                            selectedTab = .trips
                        } onAction: {
                            store.prepareForNextImport()
                            isFileImporterPresented = true
                        }
                    }

                    if let preview = store.extractedPreview {
                        ExtractionReview(preview: preview) { item, draft in
                            store.updatePreviewItem(item, with: draft)
                        } onAddItem: {
                            store.addPreviewItem()
                        } onDeleteItem: { item in
                            store.deletePreviewItem(item)
                        } onConfirm: {
                            store.confirmExtraction()
                        }
                        .id(ScrollTarget.review)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
            }
            .onChange(of: store.isExtractingConfirmation) { _, isExtracting in
                guard isExtracting else { return }
                scroll(to: ScrollTarget.recognition, with: proxy)
            }
            .onChange(of: store.extractedPreview?.id) { _, previewID in
                guard previewID != nil else { return }
                scroll(to: ScrollTarget.review, with: proxy)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $isPhotoImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handlePhotoImport(result)
        }
        .sheet(isPresented: $isPasteImporterPresented) {
            PasteConfirmationView()
                .environmentObject(store)
        }
    }

    private func scroll(to target: String, with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceName = url.lastPathComponent
        if url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
            guard let text = readPDFText(from: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                return
            }
            store.extract(text: text, sourceName: sourceName)
            return
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            store.extract(text: text, sourceName: sourceName)
        } catch {
            store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
        }
    }

    private func handlePhotoImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceName = url.lastPathComponent
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
            return
        }

        do {
            let text = try recognizeText(in: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                return
            }
            store.extract(text: text, sourceName: sourceName)
        } catch {
            store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
        }
    }

    private func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedLines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])
        return recognizedLines.joined(separator: "\n")
    }

    private func readPDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }
}

private struct PasteConfirmationView: View {
    @EnvironmentObject private var store: VoyaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paste")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("Manual confirmation")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pasted confirmation")
                            .font(.headline)
                            .foregroundStyle(Color.voyaInk)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $store.importText)
                                .scrollContentBackground(.hidden)
                                .font(.callout)
                                .foregroundStyle(Color.voyaInk)
                                .frame(minHeight: 188)
                                .padding(12)

                            if store.importText.isEmpty {
                                Text("Paste booking confirmation text")
                                    .font(.callout)
                                    .foregroundStyle(Color.voyaMuted)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Button {
                            guard !store.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                store.extractFromPastedText()
                                return
                            }
                            store.extractFromPastedText()
                            dismiss()
                        } label: {
                            HStack {
                                if store.isExtractingConfirmation {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Extract trip details", systemImage: "wand.and.stars")
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .disabled(store.isExtractingConfirmation)
                        .opacity(store.isExtractingConfirmation ? 0.82 : 1)

                        if let importMessage = store.importMessage {
                            ImportMessageLabel(message: importMessage, isWorking: store.isExtractingConfirmation)
                        }
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct AssistantView: View {
    @EnvironmentObject private var store: VoyaStore
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Assistant", subtitle: "Live support")

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Trip looks calm.")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Voya is watching timing, route changes, and flight updates.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        Image(systemName: "shield.checkered")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.voyaTeal)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        MetricPill(title: "Alerts", value: "3")
                        MetricPill(title: "Risk", value: "Low")
                        MetricPill(title: "Next", value: "06:50")
                    }
                    .foregroundStyle(.white)
                }
                .padding(18)
                .background(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 14)

                VStack(spacing: 12) {
                    ForEach(store.alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }

                HomeBaseSettingsCard(
                    homeLocationName: $homeLocationName,
                    homeLocationAddress: $homeLocationAddress
                )

                HStack(spacing: 12) {
                    Text("What if my flight is delayed?")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.voyaCoral)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct HomeBaseSettingsCard: View {
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
                    Label(didSave ? "Saved" : "Save home base", systemImage: didSave ? "checkmark" : "checkmark.circle")
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
                    .accessibilityLabel("Reset home base changes")
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

private struct HeaderBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                Text(subtitle)
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

private struct VoyaTabBar: View {
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

private struct MoodChip: View {
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

private struct TripChip: View {
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

private struct EmptyTripsCard: View {
    let title: String
    let message: String
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

private struct TripOperationsCard: View {
    let trip: Trip
    let itinerary: [ItineraryItem]

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
                    Text("Trip command")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(commandSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TripMetricTile(title: "Items", value: "\(itinerary.count)", symbol: "checklist")
                TripMetricTile(title: "Next", value: nextItem?.displayTime ?? "Review", symbol: "clock")
                TripMetricTile(title: "Transfers", value: transferCountText, symbol: "tram")
            }

            if let nextItem {
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
                        Text(nextItem.location.isEmpty ? String(localized: "Location needed") : nextItem.location)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var commandSummary: String {
        if let destination = trip.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            return String(localized: "\(destination) · \(trip.dates)")
        }

        if let firstTimedItem, let lastTimedItem, firstTimedItem.id != lastTimedItem.id {
            return String(localized: "\(firstTimedItem.displayTime) to \(lastTimedItem.displayTime)")
        }

        return trip.summary.isEmpty ? String(localized: "Ready for itinerary review") : trip.summary
    }

    private var transferCountText: String {
        guard itinerary.count > 1 else {
            return "0"
        }

        let transferCount = max(itinerary.count - 1, 0)
        return "\(transferCount)"
    }
}

private struct TripMetricTile: View {
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

private struct DestinationMark: View {
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

private struct SectionHeader: View {
    let title: String
    let action: String

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

private enum ButtonChrome {
    case primary
    case secondary
}

private struct IconTextButton: View {
    let title: String
    let symbol: String
    let style: ButtonChrome

    var body: some View {
        Button {
        } label: {
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

private struct MetricPill: View {
    let title: String
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

private struct TripHeroCard: View {
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

private struct TripHeroSummary {
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

private struct TripDateRange {
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

private extension Date {
    func distanceInDays(to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: self, to: date).day ?? 0
    }
}

private struct TripHeroBackground: View {
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

private struct TimelineRow: View {
    let item: ItineraryItem
    let phase: ItineraryPhase
    let isLast: Bool
    let onOpen: () -> Void
    @State private var displayLocation = ""

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(kindAccent)
                        .clipShape(Circle())
                        .opacity(phase.iconOpacity)

                    if !isLast {
                        Rectangle()
                            .fill(kindAccent.opacity(phase.lineOpacity))
                            .frame(width: 2, height: 46)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.displayTime)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.timeColor(accent: kindAccent))

                        Text(item.kind.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(kindAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(kindAccent.opacity(phase.kindBadgeOpacity))
                            .clipShape(Capsule())

                        Spacer()

                        Text(phase.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(phase.badgeBackground)
                            .clipShape(Capsule())
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.title.isEmpty ? String(localized: "Untitled item") : item.title)
                            .font(.headline)
                            .foregroundStyle(phase.titleColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.voyaMuted.opacity(phase.contentOpacity))
                    }

                    Text(displayLocation.isEmpty ? String(localized: "Location needed") : displayLocation)
                        .font(.subheadline)
                        .foregroundStyle(phase.secondaryColor)

                    if !item.status.isEmpty {
                        Text(item.status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(phase.secondaryColor)
                    }
                }
                .padding(.vertical, phase == .current ? 12 : 10)
                .padding(.trailing, 12)
            }
            .padding(.leading, 16)
            .padding(.bottom, isLast ? 8 : 0)
            .background(phase.rowBackground(accent: kindAccent))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(phase.contentOpacity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .task(id: item.location) {
            displayLocation = LocationDisplayResolver.immediateDisplayName(for: item.location)
            displayLocation = await LocationDisplayResolver.resolvedDisplayName(for: item.location)
        }
    }

    private var kindAccent: Color {
        item.kind.timelineAccent
    }
}

private struct FlightLayoverDisplay {
    let airport: String
    let duration: String
    let detail: String

    init?(arrivingFlight: ItineraryItem, departingFlight: ItineraryItem) {
        guard arrivingFlight.kind == .flight,
              departingFlight.kind == .flight,
              let arrival = arrivingFlight.endsAt,
              let departure = departingFlight.startsAt,
              departure > arrival else {
            return nil
        }

        let arrivingAirport = Self.routeParts(in: arrivingFlight.location).last
        let departingAirport = Self.routeParts(in: departingFlight.location).first
        airport = arrivingAirport ?? departingAirport ?? String(localized: "Connection")

        let minutes = Int(departure.timeIntervalSince(arrival) / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 {
            duration = "\(hours)h \(remainder)m"
        } else if hours > 0 {
            duration = "\(hours)h"
        } else {
            duration = "\(remainder)m"
        }

        if let arrivingAirport, let departingAirport, arrivingAirport.localizedCaseInsensitiveCompare(departingAirport) != .orderedSame {
            detail = String(localized: "\(arrivingAirport) to \(departingAirport)")
        } else {
            detail = String(localized: "Connection at \(airport)")
        }
    }

    private static func routeParts(in value: String) -> [String] {
        value
            .replacingOccurrences(of: "→", with: " to ")
            .components(separatedBy: " to ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct FlightLayoverCard: View {
    let layover: FlightLayoverDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hourglass")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.voyaSky)
                .frame(width: 34, height: 34)
                .background(Color.voyaSky.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Connection")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                    Spacer()
                    Text(layover.duration)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaSky)
                }

                Text(layover.airport)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                Text(layover.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
            }
        }
        .padding(13)
        .background(Color.voyaSky.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }
}

private struct TransferRecommendationCard: View {
    let context: MobilityTransferContext
    let phase: TransferPhase
    let plan: MobilityPlan?
    let errorMessage: String?
    let isLoading: Bool
    let onOpen: () -> Void
    let onRefresh: () -> Void
    @State private var displayOrigin = ""
    @State private var displayDestination = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: primaryOption?.mode.symbol ?? "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(phase.accent)
                    .clipShape(Circle())
                    .opacity(phase.iconOpacity)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("Transfer")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.accent)

                        if let primaryOption {
                            Text(primaryOption.mode.displayName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(phase.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(phase.accent.opacity(phase.kindBadgeOpacity))
                                .clipShape(Capsule())
                        }

                        Text(phase.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(phase.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(phase.badgeBackground)
                            .clipShape(Capsule())
                    }

                    Text(routeTitle)
                        .font(.headline)
                        .foregroundStyle(phase.titleColor)
                        .lineLimit(2)

                    Text(primaryDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(phase.secondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    Button(action: onRefresh) {
                        Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isLoading ? Color.voyaMuted : phase.accent)
                            .frame(width: 32, height: 32)
                            .background(Color.voyaSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh transfer timing")

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted.opacity(phase.contentOpacity))
                }
            }

            if isLoading && plan == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.76)
                        .tint(phase.accent)
                    Text("Checking live route timing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(phase.secondaryColor)
                }
            } else if let errorMessage, plan == nil {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
            }

            if let primaryOption {
                HStack(spacing: 10) {
                    Label(leaveByText(for: primaryOption), systemImage: "clock")
                    Spacer(minLength: 8)
                    Label(shortDuration(primaryOption), systemImage: "map")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(phase.accent)
                .padding(12)
                .background(phase.metricBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !alternativeOptions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(alternativeOptions.prefix(2)) { option in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: option.mode.symbol)
                                Text(option.mode.displayName)
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.titleColor)

                            Text(shortDuration(option))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(phase.secondaryColor)
                                .lineLimit(1)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(phase.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(phase.accent.opacity(phase.borderOpacity), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .opacity(phase.contentOpacity)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
        .task(id: context.id) {
            displayOrigin = LocationDisplayResolver.immediateDisplayName(for: context.origin)
            displayDestination = LocationDisplayResolver.immediateDisplayName(for: context.destination)
            async let origin = LocationDisplayResolver.resolvedDisplayName(for: context.origin)
            async let destination = LocationDisplayResolver.resolvedDisplayName(for: context.destination)
            displayOrigin = await origin
            displayDestination = await destination
        }
    }

    private var primaryOption: MobilityRouteOption? {
        plan?.defaultOption
    }

    private var alternativeOptions: [MobilityRouteOption] {
        guard let plan else {
            return []
        }

        return plan.options.filter { option in
            option.id != primaryOption?.id && option.durationMinutes != nil
        }
    }

    private var routeTitle: String {
        "\(shortPlace(displayOrigin.isEmpty ? context.origin : displayOrigin)) -> \(shortPlace(displayDestination.isEmpty ? context.destination : displayDestination))"
    }

    private var primaryDetail: String {
        if let recommendation = plan?.recommendation,
           recommendation.mode == primaryOption?.mode {
            return recommendation.reason
        }

        return String(localized: "Public transport is shown first, with taxi and car alternatives kept for comparison.")
    }

    private func primaryOptionSummary(_ option: MobilityRouteOption) -> String {
        let travel = option.travelMinutes.map { String(localized: "\($0) min travel") }
        let buffer = option.bufferMinutes > 0 ? String(localized: "\(option.bufferMinutes) min buffer") : nil
        let summary = [travel, buffer]
            .compactMap { $0 }
            .joined(separator: " + ")
        return summary.isEmpty ? option.summary : summary
    }

    private func leaveByText(for option: MobilityRouteOption) -> String {
        guard let leaveBy = option.leaveBy,
              let date = MobilityDateFormatter.date(from: leaveBy) else {
            return shortDuration(option)
        }

        return String(localized: "Leave \(MobilityDateFormatter.time.string(from: date))")
    }

    private func shortDuration(_ option: MobilityRouteOption) -> String {
        if let durationMinutes = option.durationMinutes {
            return String(localized: "\(durationMinutes) min total")
        }
        if let travelMinutes = option.travelMinutes {
            return String(localized: "\(travelMinutes) min")
        }
        return String(localized: "Open route")
    }

    private func shortPlace(_ value: String) -> String {
        let shortened = value
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return shortened.isEmpty ? value : shortened
    }
}

private enum TransferPhase: Equatable {
    case past
    case current
    case future
    case undated

    init(context: MobilityTransferContext, plan: MobilityPlan?, fallbackStart: Date? = nil, now: Date = Date()) {
        let option = plan?.recommendedOption
        let start = option?.leaveBy.flatMap(MobilityDateFormatter.date(from:))
            ?? context.targetDepartureAt
            ?? fallbackStart
        let end = option?.arrivalTime.flatMap(MobilityDateFormatter.date(from:))
            ?? context.targetArrivalAt
            ?? context.targetDepartureAt

        guard start != nil || end != nil else {
            self = .undated
            return
        }

        if let start, let end {
            if now >= start && now <= end {
                self = .current
                return
            }

            self = end < now ? .past : .future
            return
        }

        if let start {
            if start < now {
                self = .past
            } else {
                self = .future
            }
            return
        }

        if let end {
            self = end < now ? .past : .future
            return
        }

        self = .undated
    }

    var label: String {
        switch self {
        case .past: String(localized: "Done")
        case .current: String(localized: "Now")
        case .future: String(localized: "Transfer")
        case .undated: String(localized: "Review")
        }
    }

    var accent: Color {
        switch self {
        case .past: Color.voyaMuted
        case .current: Color.voyaTeal
        case .future: Color.voyaInk
        case .undated: Color.voyaGold
        }
    }

    var titleColor: Color {
        self == .past ? Color.voyaMuted : Color.voyaInk
    }

    var secondaryColor: Color {
        self == .past ? Color.voyaMuted.opacity(0.76) : Color.voyaMuted
    }

    var cardBackground: Color {
        switch self {
        case .past: Color.clear
        case .current: Color.voyaTeal.opacity(0.12)
        case .future: Color.voyaTeal.opacity(0.07)
        case .undated: Color.voyaGold.opacity(0.08)
        }
    }

    var badgeBackground: Color {
        switch self {
        case .past: Color.voyaSurface
        case .current: Color.voyaTeal.opacity(0.13)
        case .future: Color.voyaSurface
        case .undated: Color.voyaGold.opacity(0.13)
        }
    }

    var metricBackground: Color {
        switch self {
        case .past: Color.voyaSurface
        case .current: Color.voyaMint.opacity(0.76)
        case .future: Color.voyaMint.opacity(0.72)
        case .undated: Color.voyaGold.opacity(0.10)
        }
    }

    var contentOpacity: Double {
        self == .past ? 0.62 : 1
    }

    var iconOpacity: Double {
        self == .past ? 0.72 : 1
    }

    var borderOpacity: Double {
        self == .past ? 0.08 : 0.16
    }

    var kindBadgeOpacity: Double {
        self == .past ? 0.08 : 0.12
    }
}

private struct TransferDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let context: MobilityTransferContext
    let plan: MobilityPlan?
    let errorMessage: String?
    let isLoading: Bool
    let onRefresh: () -> Void
    @State private var displayOrigin = ""
    @State private var displayDestination = ""

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    routeMapCard

                    if isLoading && plan == nil {
                        loadingCard
                    } else if let errorMessage, plan == nil {
                        errorCard(errorMessage)
                    }

                    if let recommendation = plan?.recommendation,
                       recommendation.mode == primaryOption?.mode {
                        recommendationCard(recommendation)
                    }

                    if let plan {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Options")
                                .font(.title3.bold())
                                .foregroundStyle(Color.voyaInk)

                            ForEach(Array(plan.options.enumerated()), id: \.offset) { _, option in
                                transferOptionCard(option)
                            }
                        }

                        if !plan.warnings.isEmpty {
                            warningsCard(plan.warnings)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: context.id) {
            displayOrigin = LocationDisplayResolver.immediateDisplayName(for: context.origin)
            displayDestination = LocationDisplayResolver.immediateDisplayName(for: context.destination)
            async let origin = LocationDisplayResolver.resolvedDisplayName(for: context.origin)
            async let destination = LocationDisplayResolver.resolvedDisplayName(for: context.destination)
            displayOrigin = await origin
            displayDestination = await destination
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Transfer", systemImage: primaryOption?.mode.symbol ?? "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)

                Text("\(shortPlace(displayOrigin.isEmpty ? context.origin : displayOrigin)) → \(shortPlace(displayDestination.isEmpty ? context.destination : displayDestination))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(primaryDetail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isLoading ? Color.voyaMuted : Color.voyaInk)
                        .frame(width: 42, height: 42)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .frame(width: 42, height: 42)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var routeMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.voyaTeal)
                        .frame(width: 11, height: 11)
                    Rectangle()
                        .fill(Color.voyaTeal.opacity(0.34))
                        .frame(width: 2, height: 34)
                    Circle()
                        .fill(Color.voyaGold)
                        .frame(width: 11, height: 11)
                }

                VStack(alignment: .leading, spacing: 12) {
                    routePlace("From", displayOrigin.isEmpty ? context.origin : displayOrigin)
                    routePlace("To", displayDestination.isEmpty ? context.destination : displayDestination)
                }
            }

            if let primaryOption {
                Button {
                    openURL(primaryOption.mapURL)
                } label: {
                    Label("Open recommended route", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .foregroundStyle(.white)
                        .background(Color.voyaInk)
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

    private func routePlace(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voyaInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.voyaTeal)
            Text("Checking live route timing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voyaMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.voyaCoral)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func recommendationCard(_ recommendation: MobilityRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(recommendation.title, systemImage: recommendation.mode.symbol)
                .font(.headline)
                .foregroundStyle(Color.voyaInk)
            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(Color.voyaMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaMint.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func transferOptionCard(_ option: MobilityRouteOption) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: option.mode.symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(option.id == primaryOption?.id ? Color.voyaTeal : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(option.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                metric("Total", shortDuration(option))
                metric("Travel", option.travelMinutes.map { "\($0) min" } ?? "—")
                metric("Buffer", option.bufferMinutes > 0 ? "\(option.bufferMinutes) min" : "—")
            }

            HStack(spacing: 8) {
                metric("Cost", option.costLevel.capitalized)
                metric("Comfort", option.comfortLevel.capitalized)
                metric("Emissions", option.emissionsLevel.capitalized)
            }

            if !option.tradeoffs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(option.tradeoffs.prefix(3), id: \.self) { tradeoff in
                        Label(tradeoff, systemImage: "checkmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                if let leaveBy = leaveByText(for: option) {
                    Label(leaveBy, systemImage: "clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                }

                Spacer()

                Button {
                    openURL(option.mapURL)
                } label: {
                    Label("Map", systemImage: "map")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.voyaTeal.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(option.id == primaryOption?.id ? Color.voyaTeal.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func warningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Color.voyaInk)
            ForEach(warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var primaryOption: MobilityRouteOption? {
        plan?.defaultOption
    }

    private var primaryDetail: String {
        if let option = primaryOption {
            return "\(option.mode.displayName) · \(shortDuration(option))"
        }
        if let recommendation = plan?.recommendation,
           recommendation.mode == primaryOption?.mode {
            return recommendation.reason
        }
        return String(localized: "Public transport timing and alternatives")
    }

    private func leaveByText(for option: MobilityRouteOption) -> String? {
        guard let leaveBy = option.leaveBy,
              let date = MobilityDateFormatter.date(from: leaveBy) else {
            return nil
        }

        return String(localized: "Leave \(MobilityDateFormatter.time.string(from: date))")
    }

    private func shortDuration(_ option: MobilityRouteOption) -> String {
        if let durationMinutes = option.durationMinutes {
            return String(localized: "\(durationMinutes) min")
        }
        if let travelMinutes = option.travelMinutes {
            return String(localized: "\(travelMinutes) min")
        }
        return String(localized: "Open route")
    }

    private func shortPlace(_ value: String) -> String {
        let shortened = value
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return shortened.isEmpty ? value : shortened
    }
}

private struct MissingStartPointCard: View {
    let onEditTrip: () -> Void

    var body: some View {
        Button(action: onEditTrip) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house.and.flag")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.voyaGold)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start point")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaGold)
                    Text("Add where this trip starts")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                    Text("Set a home address in Assistant or enter a custom start point for this trip.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
            }
            .padding(14)
            .background(Color.voyaGold.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.voyaGold.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct MissingEndPointCard: View {
    let onEditTrip: () -> Void

    var body: some View {
        Button(action: onEditTrip) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.voyaTeal)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("End point")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                    Text("Add where this trip ends")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                    Text("Set a home address in Assistant or enter a custom return point for this trip.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
            }
            .padding(14)
            .background(Color.voyaTeal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.voyaTeal.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private enum MobilityDateFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private enum ItineraryPhase: Equatable {
    case past
    case current
    case future
    case undated

    init(item: ItineraryItem, now: Date = Date()) {
        guard let start = item.startsAt else {
            self = .undated
            return
        }

        let end = item.endsAt ?? start
        if now >= start && now <= end {
            self = .current
            return
        }

        if end < now {
            self = .past
            return
        }

        self = .future
    }

    var label: String {
        switch self {
        case .past: String(localized: "Done")
        case .current: String(localized: "Now")
        case .future: String(localized: "Next")
        case .undated: String(localized: "Review")
        }
    }

    var accent: Color {
        switch self {
        case .past: Color.voyaMuted
        case .current: Color.voyaTeal
        case .future: Color.voyaInk
        case .undated: Color.voyaGold
        }
    }

    func timeColor(accent: Color) -> Color {
        switch self {
        case .current: accent
        case .undated: Color.voyaGold
        case .past: Color.voyaMuted
        case .future: accent
        }
    }

    var titleColor: Color {
        self == .past ? Color.voyaMuted : Color.voyaInk
    }

    var secondaryColor: Color {
        self == .past ? Color.voyaMuted.opacity(0.76) : Color.voyaMuted
    }

    func rowBackground(accent: Color) -> Color {
        switch self {
        case .current: accent.opacity(0.13)
        case .future: accent.opacity(0.055)
        case .undated: Color.voyaGold.opacity(0.08)
        case .past: Color.clear
        }
    }

    var badgeBackground: Color {
        switch self {
        case .current: Color.voyaTeal.opacity(0.13)
        case .undated: Color.voyaGold.opacity(0.13)
        case .past: Color.voyaSurface
        case .future: Color.voyaSurface
        }
    }

    var contentOpacity: Double {
        self == .past ? 0.62 : 1
    }

    var iconOpacity: Double {
        self == .past ? 0.72 : 1
    }

    var lineOpacity: Double {
        self == .past ? 0.18 : 0.42
    }

    var kindBadgeOpacity: Double {
        self == .past ? 0.08 : 0.12
    }

    var insightText: String {
        switch self {
        case .past: String(localized: "Already behind")
        case .current: String(localized: "Focus now")
        case .future: String(localized: "Coming up")
        case .undated: String(localized: "Needs time")
        }
    }
}

struct ItineraryItemDraft {
    var kind: ItineraryKind
    var title: String
    var hasStartDate: Bool
    var startsAt: Date
    var endsAt: Date
    var hasEndDate: Bool
    var location: String
    var status: String

    init(item: ItineraryItem) {
        kind = item.kind
        title = item.title
        hasStartDate = item.startsAt != nil
        startsAt = item.startsAt ?? Date()
        endsAt = item.endsAt ?? item.startsAt ?? Date()
        hasEndDate = item.endsAt != nil
        location = item.location
        status = item.status
    }

    init() {
        kind = .event
        title = ""
        hasStartDate = true
        startsAt = Date()
        endsAt = Date()
        hasEndDate = false
        location = ""
        status = ""
    }

    var effectiveStartsAt: Date? {
        hasStartDate ? startsAt : nil
    }

    var effectiveEndsAt: Date? {
        hasStartDate && hasEndDate ? max(endsAt, startsAt) : nil
    }

    var displayTime: String {
        effectiveStartsAt.map { ItineraryDateFormatter.displayTime(start: $0, end: effectiveEndsAt) } ?? String(localized: "Date needed")
    }
}

private enum LocationLinkResolver {
    static func mapURL(for value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directURL = directURL(from: trimmed) {
            return directURL
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
    }

    static func directURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "comgooglemaps", "maps"].contains(scheme) else {
            return nil
        }

        return url
    }
}

private enum LocationDisplayResolver {
    static func immediateDisplayName(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard let url = googleMapsURL(from: trimmed) else {
            return trimmed
        }

        return placeName(from: url) ?? coordinates(from: url).map { _ in String(localized: "Map point") } ?? String(localized: "Map point")
    }

    static func resolvedDisplayName(for value: String) async -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard let url = googleMapsURL(from: trimmed) else {
            return trimmed
        }

        if let displayName = placeName(from: url) ?? coordinates(from: url).map({ _ in String(localized: "Map point") }) {
            return displayName
        }

        guard isShortGoogleMapsURL(url),
              let resolvedURL = await resolvedURL(from: url),
              resolvedURL != url else {
            return String(localized: "Map point")
        }

        return placeName(from: resolvedURL) ?? coordinates(from: resolvedURL).map { _ in String(localized: "Map point") } ?? String(localized: "Map point")
    }

    private static func googleMapsURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let host = url.host?.lowercased(),
              isGoogleMapsHost(host) else {
            return nil
        }

        return url
    }

    private static func isGoogleMapsHost(_ host: String) -> Bool {
        [
            "google.com",
            "www.google.com",
            "maps.google.com",
            "maps.app.goo.gl",
            "goo.gl"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func isShortGoogleMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "maps.app.goo.gl" || host == "goo.gl"
    }

    private static func placeName(from url: URL) -> String? {
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" || $0.name == "query" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !query.isEmpty,
           coordinates(from: query) == nil {
            return cleanPlaceName(query)
        }

        let path = url.path.removingPercentEncoding ?? url.path
        guard let range = path.range(of: #"/place/([^/]+)"#, options: .regularExpression) else {
            return nil
        }

        let rawName = String(path[range])
            .replacingOccurrences(of: "/place/", with: "")
        return cleanPlaceName(rawName)
    }

    private static func cleanPlaceName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func coordinates(from url: URL) -> (Double, Double)? {
        coordinates(from: url.absoluteString.removingPercentEncoding ?? url.absoluteString)
    }

    private static func coordinates(from value: String) -> (Double, Double)? {
        let patterns = [
            #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:[,/?]|$)"#,
            #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#,
            #"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 1), in: value),
                  let lonRange = Range(match.range(at: 2), in: value),
                  let latitude = Double(value[latRange]),
                  let longitude = Double(value[lonRange]),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                continue
            }

            return (latitude, longitude)
        }

        return nil
    }

    private static func resolvedURL(from url: URL) async -> URL? {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 8
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let resolvedURL = response.url,
                   resolvedURL != url,
                   googleMapsURL(from: resolvedURL.absoluteString) != nil {
                    return resolvedURL
                }
            } catch {
                continue
            }
        }

        return nil
    }
}

private enum ItineraryItemEditorMode {
    case add
    case edit
}

private struct ItineraryItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft: ItineraryItemDraft
    @State private var isEditing = false
    @State private var didCopyLocation = false
    @State private var enrichment: ItemEnrichment?
    @State private var isLoadingEnrichment = false
    let item: ItineraryItem
    let onSave: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        item: ItineraryItem,
        onSave: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader

                    ItemCompanionCard(
                        item: item,
                        phase: ItineraryPhase(item: item),
                        enrichment: enrichment,
                        didCopyLocation: didCopyLocation,
                        onOpenLocation: openMaps,
                        onCopyLocation: copyLocation
                    )
                    ItemInsightPanel(
                        item: item,
                        phase: ItineraryPhase(item: item),
                        enrichment: enrichment,
                        isLoading: isLoadingEnrichment,
                        onRefresh: {
                            Task {
                                await loadEnrichment(forceRefresh: true)
                            }
                        }
                    )

                    DisclosureGroup {
                        itemFormCard
                            .padding(.top, 10)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isEditing ? "square.and.pencil" : "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isEditing ? "Edit booking details" : "Booking details")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text(isEditing ? "Update the source fields for this moment." : "Raw itinerary fields stay here when you need them.")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
                    }
                    .tint(Color.voyaTeal)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, isEditing ? 128 : 30)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                editorActions
            }
        }
        .task(id: item.id) {
            await loadEnrichment()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Label(draft.kind.displayName, systemImage: draft.kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
                Text(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Untitled item") : draft.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(draft.displayTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: isEditing ? "lock.open.fill" : "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isEditing ? .white : Color.voyaInk)
                        .frame(width: 42, height: 42)
                        .background(isEditing ? Color.voyaTeal : .white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isEditing ? "Lock editing" : "Unlock editing")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .frame(width: 42, height: 42)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var itemFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ItineraryKindPicker(selection: $draft.kind)
                .disabled(!isEditing)
            ClearableTextField("Title", text: $draft.title, prompt: "Flight BA2490, hotel stay, dinner reservation")
                .disabled(!isEditing)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Date", isOn: $draft.hasStartDate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .tint(Color.voyaTeal)

                if draft.hasStartDate {
                    DatePicker("Start", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)

                    Toggle("End time", isOn: $draft.hasEndDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .tint(Color.voyaTeal)

                    if draft.hasEndDate {
                        DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaInk)
                    }
                }
            }
            .padding(12)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!isEditing)
            .onChange(of: draft.startsAt) { _, startsAt in
                if draft.endsAt < startsAt {
                    draft.endsAt = startsAt
                }
            }
            .onChange(of: draft.hasStartDate) { _, hasStartDate in
                if !hasStartDate {
                    draft.hasEndDate = false
                }
            }

            ClearableTextField("Place / map link", text: $draft.location, prompt: "Hotel name, airport, venue, address, or Google Maps link")
                .disabled(!isEditing)
            ClearableTextField("Status", text: $draft.status, prompt: "Confirmed, needs review, ticket saved")
                .disabled(!isEditing)

            HStack(spacing: 8) {
                Label(item.sourceName ?? String(localized: "Manual entry"), systemImage: "doc.text")
                Spacer(minLength: 0)
                Label(isEditing ? String(localized: "Unlocked") : String(localized: "Locked"), systemImage: isEditing ? "lock.open.fill" : "lock.fill")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.voyaMuted)
            .padding(.top, 2)
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var locationActions: some View {
        HStack(spacing: 10) {
            Button {
                openMaps()
            } label: {
                Label(locationActionTitle, systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(.white)
                    .background(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

            Button {
                copyLocation()
            } label: {
                Label(didCopyLocation ? "Copied" : "Copy", systemImage: didCopyLocation ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.voyaInk)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var editorActions: some View {
        VStack(spacing: 10) {
            Button {
                onSave(draft)
                dismiss()
            } label: {
                Label("Save changes", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(isSaveDisabled ? Color.voyaMuted : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaveDisabled)

            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Label("Delete item", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.voyaCoral)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var locationActionTitle: String {
        LocationLinkResolver.directURL(from: draft.location) == nil ? String(localized: "Open map") : String(localized: "Open link")
    }

    private func openMaps() {
        guard let url = LocationLinkResolver.mapURL(for: draft.location) else {
            return
        }
        openURL(url)
    }

    private func copyLocation() {
        let value = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        UIPasteboard.general.string = value
        withAnimation(.easeInOut(duration: 0.18)) {
            didCopyLocation = true
        }
    }

    private func loadEnrichment(forceRefresh: Bool = false) async {
        guard !isLoadingEnrichment else {
            return
        }

        isLoadingEnrichment = true
        defer { isLoadingEnrichment = false }

        do {
            enrichment = try await VercelItemEnricher().enrich(item: item, modelContext: modelContext, forceRefresh: forceRefresh)
        } catch {
            enrichment = nil
        }
    }
}

private struct ItemCompanionCard: View {
    let item: ItineraryItem
    let phase: ItineraryPhase
    let enrichment: ItemEnrichment?
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
            }
            .padding(18)

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

        return defaultOperationalNote
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
        item.startsAt.map { MomentDateFormatter.time.string(from: $0) } ?? String(localized: "--:--")
    }

    private var endTimeText: String {
        item.endsAt.map { MomentDateFormatter.time.string(from: $0) } ?? String(localized: "--:--")
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

private struct FlightRouteDisplay {
    let origin: String
    let destination: String
}

private enum MomentDateFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct MomentMetric: View {
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

private struct MomentLocationRow: View {
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
                .accessibilityLabel(isCopied ? "Copied" : "Copy location")
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

private extension ItemEnrichment {
    var hasPlanDetails: Bool {
        !sections.isEmpty || !briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageURLs.isEmpty
    }
}

private struct TravelBriefCard: View {
    @Environment(\.openURL) private var openURL
    let enrichment: ItemEnrichment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Plan details", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
            }

            if !enrichment.sections.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(enrichment.sections) { section in
                        TravelBriefSectionView(section: section)
                    }
                }
            } else if !enrichment.briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownBriefText(markdown: enrichment.briefMarkdown)
            }

            if !enrichment.imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(enrichment.imageURLs, id: \.self) { url in
                            Button {
                                openURL(url)
                            } label: {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        ZStack {
                                            Color.voyaSurface
                                            Image(systemName: "photo")
                                                .font(.title3.weight(.bold))
                                                .foregroundStyle(Color.voyaMuted)
                                        }
                                    }
                                }
                                .frame(width: 132, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
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

private struct MarkdownBriefText: View {
    let markdown: String

    var body: some View {
        Text(attributedText)
            .font(.subheadline)
            .foregroundStyle(Color.voyaInk)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct TravelBriefSectionView: View {
    let section: TravelBriefSection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(section.title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var displayLines: [String] {
        let normalized = section.body
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let protected = normalized
            .replacingOccurrences(of: ". ", with: ".\n")
            .replacingOccurrences(of: "; ", with: ";\n")

        let lines = protected
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? [normalized] : lines
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

private struct AssistantCue: View {
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

private struct ItemInsightPanel: View {
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
                    Text("Signals")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Live context and next actions for this item.")
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

        if let enrichment, !enrichment.routeLegs.isEmpty {
            rows.append(contentsOf: enrichment.routeLegs.prefix(3).map { leg in
                AssistantGuidance(
                    title: leg.title,
                    value: routeValue(for: leg),
                    detail: leg.guidance,
                    symbol: "map",
                    tint: Color.voyaTeal,
                    actionURL: leg.mapURL
                )
            })
        }

        if let enrichment, !enrichment.actions.isEmpty {
            rows.append(contentsOf: enrichment.actions.prefix(3).map { action in
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

        if let enrichment, !enrichment.cards.isEmpty {
            let supportingCards = enrichment.cards.filter { card in
                !["maps", "warning"].contains(card.kind)
            }
            rows.append(contentsOf: supportingCards.prefix(3).map { card in
                AssistantGuidance(
                    title: guidanceTitle(for: card),
                    value: card.value,
                    detail: card.detail,
                    symbol: symbol(for: card.kind),
                    tint: tint(for: card.kind),
                    actionURL: card.actionURL
                )
            })
        }

        if rows.isEmpty {
            rows.append(contentsOf: fallbackRows)
        }

        return rows
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
}

private struct AssistantGuidance: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String?
    let symbol: String
    let tint: Color
    let actionURL: URL?
}

private struct AssistantGuidanceRow: View {
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

private struct EditItineraryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItineraryItemDraft
    @State private var flightLookupNumber: String
    @State private var flightLookupResult: FlightLookupResponse?
    @State private var isFlightLookupLoading = false
    @State private var flightLookupMessage: String?
    let mode: ItineraryItemEditorMode
    let tripTitle: String?
    let onSave: (ItineraryItemDraft) -> Void
    let onDelete: (() -> Void)?

    init(
        item: ItineraryItem,
        onSave: @escaping (ItineraryItemDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        _flightLookupNumber = State(initialValue: Self.firstFlightNumber(in: item.title))
        mode = .edit
        tripTitle = nil
        self.onSave = onSave
        self.onDelete = onDelete
    }

    init(mode: ItineraryItemEditorMode, tripTitle: String, onSave: @escaping (ItineraryItemDraft) -> Void) {
        _draft = State(initialValue: ItineraryItemDraft())
        _flightLookupNumber = State(initialValue: "")
        self.mode = mode
        self.tripTitle = tripTitle
        self.onSave = onSave
        onDelete = nil
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode == .add ? String(localized: "Add item") : String(localized: "Edit item"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text(tripTitle ?? draft.kind.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ItineraryKindPicker(selection: $draft.kind)

                        if draft.kind == .flight {
                            flightLookupPanel
                        }

                        ClearableTextField("Title", text: $draft.title, prompt: "Flight BA2490, hotel stay, dinner reservation")

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Date", isOn: $draft.hasStartDate)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .tint(Color.voyaTeal)

                            if draft.hasStartDate {
                                DatePicker("Start", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.voyaInk)

                                Toggle("End time", isOn: $draft.hasEndDate)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.voyaInk)
                                    .tint(Color.voyaTeal)

                                if draft.hasEndDate {
                                    DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.voyaInk)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: draft.startsAt) { _, startsAt in
                            if draft.endsAt < startsAt {
                                draft.endsAt = startsAt
                            }
                        }
                        .onChange(of: draft.hasStartDate) { _, hasStartDate in
                            if !hasStartDate {
                                draft.hasEndDate = false
                            }
                        }

                        ClearableTextField("Place / map link", text: $draft.location, prompt: "Hotel name, airport, venue, address, or Google Maps link")
                        ClearableTextField("Status", text: $draft.status, prompt: "Confirmed, needs review, ticket saved")
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    onSave(draft)
                    dismiss()
                } label: {
                    Label(mode == .add ? String(localized: "Add to trip") : String(localized: "Save changes"), systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(isSaveDisabled ? Color.voyaMuted : Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaveDisabled)

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete item", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(Color.voyaCoral)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var flightLookupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ClearableTextField("Flight number", text: $flightLookupNumber, prompt: "LH1830")

                Button {
                    Task {
                        await lookupFlight()
                    }
                } label: {
                    Image(systemName: isFlightLookupLoading ? "hourglass" : "magnifyingglass")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(isFlightLookupDisabled ? Color.voyaMuted : Color.voyaTeal)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFlightLookupDisabled)
            }

            if let candidate = flightLookupResult?.candidate {
                Button {
                    apply(candidate)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "airplane.departure")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.voyaTeal)
                            .frame(width: 36, height: 36)
                            .background(Color.voyaTeal.opacity(0.10))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.flightNumber)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                            Text(flightCandidateSummary(candidate))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "arrow.down.doc.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaTeal)
                    }
                    .padding(12)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if let flightLookupMessage {
                Text(flightLookupMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: draft.title) { _, title in
            guard flightLookupNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            flightLookupNumber = Self.firstFlightNumber(in: title)
        }
    }

    private var isFlightLookupDisabled: Bool {
        isFlightLookupLoading || flightLookupNumber.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func lookupFlight() async {
        let flightNumber = flightLookupNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flightNumber.isEmpty else {
            return
        }

        isFlightLookupLoading = true
        flightLookupMessage = nil
        defer { isFlightLookupLoading = false }

        do {
            let response = try await VercelFlightLookupService().lookup(flightNumber: flightNumber, date: draft.startsAt)
            flightLookupResult = response
            if response.candidate == nil {
                flightLookupMessage = response.warnings.first ?? response.validation.reasons.first ?? String(localized: "No matching flight found for this date.")
            }
        } catch {
            flightLookupResult = nil
            flightLookupMessage = String(localized: "Flight lookup is unavailable right now.")
        }
    }

    private func apply(_ candidate: FlightLookupCandidate) {
        draft.kind = .flight
        draft.title = candidate.titleText
        if !candidate.routeText.isEmpty {
            draft.location = candidate.routeText
        }
        draft.status = candidate.statusText

        if let departure = candidate.parsedDepartureAt {
            draft.hasStartDate = true
            draft.startsAt = departure
        }

        if let arrival = candidate.parsedArrivalAt {
            draft.hasEndDate = true
            draft.endsAt = arrival
        }

        flightLookupMessage = String(localized: "Flight details applied.")
    }

    private func flightCandidateSummary(_ candidate: FlightLookupCandidate) -> String {
        var parts: [String] = []
        if !candidate.routeText.isEmpty {
            parts.append(candidate.routeText)
        }
        if let departure = candidate.parsedDepartureAt {
            parts.append(ItineraryDateFormatter.displayTime(start: departure, end: candidate.parsedArrivalAt))
        }
        if let duration = candidate.durationMinutes {
            parts.append(Self.durationText(minutes: duration))
        }
        if let aircraft = candidate.aircraftType?.trimmingCharacters(in: .whitespacesAndNewlines), !aircraft.isEmpty {
            parts.append(aircraft)
        }
        return parts.joined(separator: " · ")
    }

    private static func firstFlightNumber(in value: String) -> String {
        guard let match = value.firstMatch(of: /[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?/) else {
            return ""
        }

        return String(match.output).replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }
}

private struct TripDraft {
    var title: String
    var destination: String
    var summary: String
    var notes: String
    var startLocationName: String
    var startLocationAddress: String
    var endLocationName: String
    var endLocationAddress: String

    init(trip: Trip) {
        title = trip.title
        destination = trip.destination ?? ""
        summary = trip.summary
        notes = trip.notes ?? ""
        startLocationName = trip.startLocationName ?? ""
        startLocationAddress = trip.startLocationAddress ?? ""
        endLocationName = trip.endLocationName ?? ""
        endLocationAddress = trip.endLocationAddress ?? ""
    }
}

private struct EditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TripDraft
    let onSave: (TripDraft) -> Void
    let onDelete: () -> Void

    init(
        trip: Trip,
        onSave: @escaping (TripDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: TripDraft(trip: trip))
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit trip")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("Trip details")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ClearableTextField("Title", text: $draft.title, prompt: "Trip to Rome")
                        ClearableTextField("Destination", text: $draft.destination, prompt: "Rome")
                        ClearableTextField("Summary", text: $draft.summary, prompt: "Confirmed flights and stay")
                        ClearableTextField("Notes", text: $draft.notes, prompt: "Anything useful for this trip", lineLimit: 3...6)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.north.line.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.voyaTeal)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trip start point")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text("Overrides Home for this trip")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }

                            Spacer()
                        }

                        ClearableTextField("Place name", text: $draft.startLocationName, prompt: "Home, Office, Hotel")
                        ClearableTextField("Address", text: $draft.startLocationAddress, prompt: "Leave empty to use Home", lineLimit: 2...4)

                        Text("Leave this blank when the trip starts from your default Home base.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "house.and.flag.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.voyaGold)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trip end point")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text("Overrides Home for the return")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }

                            Spacer()
                        }

                        ClearableTextField("Place name", text: $draft.endLocationName, prompt: "Home, Office, Hotel")
                        ClearableTextField("Address", text: $draft.endLocationAddress, prompt: "Leave empty to return Home", lineLimit: 2...4)

                        Text("Leave this blank when the trip should end at your default Home base.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    onSave(draft)
                    dismiss()
                } label: {
                    Label("Save trip", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(isSaveDisabled ? Color.voyaMuted : Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaveDisabled)

                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete trip", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(Color.voyaCoral)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ImportPrimaryDropZone: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.voyaTeal)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("PDF or text file")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Text("Flights, hotels, events, rail, and transfers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
                .frame(width: 34, height: 34)
                .background(Color.voyaTeal.opacity(0.10))
                .clipShape(Circle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(Color.voyaMint.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.voyaTeal.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ImportOption: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

private struct ImportMessageLabel: View {
    let message: String
    let isWorking: Bool

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isError: Bool {
        message.hasPrefix("AI extraction unavailable") || message.hasPrefix("Could not")
    }

    private var symbol: String {
        if isWorking {
            return "wand.and.stars"
        }

        return isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var color: Color {
        isError ? Color.voyaCoral : Color.voyaTeal
    }
}

private struct RecognitionAnimationCard: View {
    let message: String

    private let tags = [
        String(localized: "Dates"),
        String(localized: "Flights"),
        String(localized: "Hotels"),
        String(localized: "Places")
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let activeStep = Int(phase * 1.15) % 5

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.voyaSurface)
                            .frame(width: 78, height: 92)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.voyaLine, lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index <= activeStep ? Color.voyaTeal : Color.voyaInk.opacity(0.14))
                                    .frame(width: index == 2 ? 34 : 46, height: 5)
                                    .animation(.easeInOut(duration: 0.28), value: activeStep)
                            }
                        }
                        .offset(y: 2)
                    }
                    .frame(width: 86, height: 100)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Reading confirmation")
                            .font(.headline)
                            .foregroundStyle(Color.voyaInk)
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        RecognitionTag(title: tag, isActive: index <= min(activeStep, tags.count - 1))
                    }
                }
            }
            .padding(18)
            .background(.white)
            .foregroundStyle(Color.voyaInk)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct RecognitionTag: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isActive ? Color.voyaInk : Color.voyaMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isActive ? Color.voyaMint : Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .animation(.easeInOut(duration: 0.35), value: isActive)
    }
}

private struct ImportSuccessAnimationCard: View {
    let success: ImportSuccess
    let actionTitle: String
    let onViewTrip: () -> Void
    let onAction: () -> Void
    @State private var isCheckVisible = false

    private var itemLabel: String {
        String(localized: "\(success.itemCount) trip item\(success.itemCount == 1 ? "" : "s")")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.voyaTeal.opacity(0.13))
                        .frame(width: 88, height: 88)

                    Circle()
                        .stroke(Color.voyaTeal.opacity(0.22), lineWidth: 2)
                        .frame(width: 74, height: 74)

                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.voyaTeal)
                        .clipShape(Circle())
                        .shadow(color: Color.voyaTeal.opacity(0.28), radius: 14, y: 8)
                        .scaleEffect(isCheckVisible ? 1 : 0.68)
                        .opacity(isCheckVisible ? 1 : 0)
                }
                .frame(width: 94, height: 94)

                VStack(alignment: .leading, spacing: 7) {
                    Text(success.didCreateTrip ? String(localized: "Trip created") : String(localized: "Added to trip"))
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(itemLabel) from \(success.sourceName) is now in \(success.tripTitle).")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onViewTrip) {
                    Label("View trip", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(Color.voyaInk)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onAction) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 12)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                isCheckVisible = true
            }
        }
    }
}

private struct ExtractionReview: View {
    let preview: ExtractionPreview
    let onItemChange: (ItineraryItem, ItineraryItemDraft) -> Void
    let onAddItem: () -> Void
    let onDeleteItem: (ItineraryItem) -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to review")
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(preview.type) · \(Int(preview.confidence * 100))% confidence")
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()

                ProgressRing(value: preview.confidence)
            }

            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.voyaGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(Color.voyaGold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(spacing: 10) {
                ForEach(preview.fields) { field in
                    HStack(alignment: .top) {
                        Text(field.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.voyaMuted)
                            .frame(width: 72, alignment: .leading)
                        Text(field.value)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 12) {
                ForEach(preview.items) { item in
                    EditableItineraryItem(
                        item: item,
                        onChange: { draft in onItemChange(item, draft) },
                        onDelete: { onDeleteItem(item) }
                    )
                }
            }

            Button(action: onAddItem) {
                Label("Add item", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.voyaInk)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Label("Save to trip", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(preview.items.isEmpty ? Color.voyaMuted : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preview.items.isEmpty)
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct EditableItineraryItem: View {
    @State private var draft: ItineraryItemDraft
    let onChange: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        item: ItineraryItem,
        onChange: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        self.onChange = onChange
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(draft.kind.displayName, systemImage: draft.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
                Text(draft.displayTime)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(draft.hasStartDate ? Color.voyaMuted : Color.voyaCoral)
            }

            ItineraryKindPicker(selection: $draft.kind)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Date", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)

                    Spacer()

                    Toggle("", isOn: $draft.hasStartDate)
                        .labelsHidden()
                        .tint(Color.voyaTeal)
                }

                if draft.hasStartDate {
                    dateTimePickerRow("Start", selection: $draft.startsAt)

                    Toggle("End time", isOn: $draft.hasEndDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .tint(Color.voyaTeal)

                    if draft.hasEndDate {
                        dateTimePickerRow("End", selection: $draft.endsAt, range: draft.startsAt...)
                    }
                }
            }
            .padding(.vertical, 2)

            ClearableTextField("Title", text: $draft.title, prompt: "Flight BA2490, hotel stay, dinner reservation")
            ClearableTextField("Place / map link", text: $draft.location, prompt: "Hotel name, airport, venue, address, or Google Maps link")
            ClearableTextField("Status", text: $draft.status, prompt: "Confirmed, needs review, ticket saved")

            Button(role: .destructive, action: onDelete) {
                Label("Remove from import", systemImage: "minus.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: draft.kind) { _, _ in commitDraft() }
        .onChange(of: draft.title) { _, _ in commitDraft() }
        .onChange(of: draft.location) { _, _ in commitDraft() }
        .onChange(of: draft.status) { _, _ in commitDraft() }
        .onChange(of: draft.hasStartDate) { _, value in
            if !value {
                draft.hasEndDate = false
            }
            commitDraft()
        }
        .onChange(of: draft.hasEndDate) { _, _ in commitDraft() }
        .onChange(of: draft.startsAt) { _, value in
            if draft.endsAt < value {
                draft.endsAt = value
            }
            commitDraft()
        }
        .onChange(of: draft.endsAt) { _, _ in commitDraft() }
    }

    private func dateTimePickerRow(
        _ label: String,
        selection: Binding<Date>,
        range: PartialRangeFrom<Date>? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaInk)
                .frame(width: 82, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let range {
                    DatePicker("", selection: selection, in: range, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(minWidth: 128)
                    DatePicker("", selection: selection, in: range, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(minWidth: 100)
                } else {
                    DatePicker("", selection: selection, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(minWidth: 128)
                    DatePicker("", selection: selection, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(minWidth: 100)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.voyaInk)
        }
    }

    private func commitDraft() {
        onChange(draft)
    }
}

private struct ClearableTextField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let lineLimit: ClosedRange<Int>

    init(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        lineLimit: ClosedRange<Int> = 1...3
    ) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.lineLimit = lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)

            HStack(alignment: .top, spacing: 8) {
                TextField(label, text: $text, prompt: Text(prompt), axis: .vertical)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(lineLimit)
                    .padding(.vertical, 4)
                    .frame(minHeight: lineLimit.lowerBound > 1 ? 88 : 38)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.voyaMuted.opacity(0.72))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label)")
                }
            }
            .padding(.horizontal, 10)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

private struct ItineraryKindPicker: View {
    @Binding var selection: ItineraryKind

    var body: some View {
        Picker("Type", selection: $selection) {
            Text("Flight").tag(ItineraryKind.flight)
            Text("Hotel").tag(ItineraryKind.hotel)
            Text("Event").tag(ItineraryKind.event)
            Text("Transit").tag(ItineraryKind.transit)
        }
        .pickerStyle(.segmented)
    }
}

private struct AlertCard: View {
    let alert: TravelAlert

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: alert.severity.symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(alert.severity.color)
                .frame(width: 42, height: 42)
                .background(alert.severity.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 8)
    }
}

private struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.voyaLine, lineWidth: 5)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.voyaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
                .font(.caption.bold())
                .foregroundStyle(Color.voyaInk)
        }
        .frame(width: 48, height: 48)
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.98, blue: 0.97),
                Color(red: 0.98, green: 0.96, blue: 0.93),
                Color(red: 0.94, green: 0.97, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension AlertSeverity {
    var symbol: String {
        switch self {
        case .calm: "checkmark.circle.fill"
        case .watch: "clock.badge.exclamationmark"
        case .action: "exclamationmark.triangle.fill"
        }
    }
}

private extension Color {
    static let voyaInk = Color(red: 0.08, green: 0.12, blue: 0.16)
    static let voyaMuted = Color(red: 0.34, green: 0.39, blue: 0.43)
    static let voyaTeal = Color(red: 0.00, green: 0.52, blue: 0.48)
    static let voyaMint = Color(red: 0.85, green: 0.96, blue: 0.92)
    static let voyaCoral = Color(red: 0.92, green: 0.32, blue: 0.26)
    static let voyaGold = Color(red: 0.76, green: 0.56, blue: 0.12)
    static let voyaSky = Color(red: 0.16, green: 0.43, blue: 0.88)
    static let voyaPlum = Color(red: 0.45, green: 0.28, blue: 0.68)
    static let voyaSurface = Color(red: 0.95, green: 0.96, blue: 0.95)
    static let voyaLine = Color(red: 0.86, green: 0.89, blue: 0.88)
}

private extension ItineraryKind {
    var timelineAccent: Color {
        switch self {
        case .flight: Color.voyaSky
        case .hotel: Color.voyaPlum
        case .event: Color.voyaCoral
        case .transit: Color.voyaTeal
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(VoyaStore())
    }
}

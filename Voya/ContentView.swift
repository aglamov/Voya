import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers
import UIKit

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
    @State private var itemBeingViewed: ItineraryItem?
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
                            TimelineRow(
                                item: item,
                                phase: ItineraryPhase(item: item),
                                isLast: index == itinerary.count - 1
                            ) {
                                itemBeingViewed = item
                            }

                            if index + 1 < itinerary.count,
                               let context = VercelMobilityService.transferContext(from: item, to: itinerary[index + 1]) {
                                TransferRecommendationCard(
                                    context: context,
                                    plan: mobilityPlans[context.id],
                                    errorMessage: mobilityPlanErrors[context.id],
                                    isLoading: loadingMobilityPlanIDs.contains(context.id),
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
                    notes: draft.notes
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
            mobilityPlans[context.id] = try await VercelMobilityService().planTransfer(from: originItem, to: destinationItem)
        } catch {
            mobilityPlanErrors[context.id] = String(localized: "Route timing unavailable")
        }
    }

}

private struct ImportView: View {
    @EnvironmentObject private var store: VoyaStore
    @Binding var selectedTab: VoyaTab
    @State private var isFileImporterPresented = false
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
                    HeaderBar(title: "Import", subtitle: "Travel inbox")

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Drop confirmations here.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.voyaInk)

                        LazyVGrid(columns: columns, spacing: 12) {
                            Button {
                                isFileImporterPresented = true
                            } label: {
                                ImportOption(symbol: "doc.text", title: "PDF/TXT", tint: .voyaTeal)
                            }
                            .buttonStyle(.plain)

                            ImportOption(symbol: "photo.on.rectangle", title: "Screenshot", tint: .voyaCoral, isEnabled: false)
                            ImportOption(symbol: "camera.viewfinder", title: "Photo", tint: .indigo, isEnabled: false)
                            Button {
                                isPasteImporterPresented = true
                            } label: {
                                ImportOption(symbol: "text.alignleft", title: "Paste", tint: .voyaGold)
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
            statusText = String(localized: "Ready when you are")
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

                    Text(item.location.isEmpty ? String(localized: "Location needed") : item.location)
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
    }

    private var kindAccent: Color {
        item.kind.timelineAccent
    }
}

private struct TransferRecommendationCard: View {
    @Environment(\.openURL) private var openURL
    let context: MobilityTransferContext
    let plan: MobilityPlan?
    let errorMessage: String?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: primaryOption?.mode.symbol ?? "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.voyaTeal)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)

                    Text(routeTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .lineLimit(2)

                    Text(primaryDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: onRefresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isLoading ? Color.voyaMuted : Color.voyaTeal)
                        .frame(width: 32, height: 32)
                        .background(Color.voyaSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel("Refresh transfer timing")
            }

            if isLoading && plan == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.76)
                        .tint(Color.voyaTeal)
                    Text("Checking live route timing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                }
            } else if let errorMessage, plan == nil {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
            }

            if let primaryOption {
                Button {
                    openURL(primaryOption.mapURL)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(primaryOption.mode.displayName)
                                .font(.headline)
                                .foregroundStyle(Color.voyaInk)
                            Text(primaryOptionSummary(primaryOption))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(leaveByText(for: primaryOption))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                            Image(systemName: "map")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                        }
                    }
                    .padding(12)
                    .background(Color.voyaMint.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !alternativeOptions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(alternativeOptions.prefix(2)) { option in
                        Button {
                            openURL(option.mapURL)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) {
                                    Image(systemName: option.mode.symbol)
                                    Text(option.mode.displayName)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.voyaInk)

                                Text(shortDuration(option))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.voyaMuted)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.voyaTeal.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.voyaTeal.opacity(0.16), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private var primaryOption: MobilityRouteOption? {
        plan?.recommendedOption
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
        "\(shortPlace(context.origin)) -> \(shortPlace(context.destination))"
    }

    private var primaryDetail: String {
        if let reason = plan?.recommendation?.reason {
            return reason
        }

        return String(localized: "Voya compares taxi, transit, and own car timing for this leg.")
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

    init(item: ItineraryItem, now: Date = Date(), calendar: Calendar = .current) {
        guard let start = item.startsAt else {
            self = .undated
            return
        }

        let end = item.endsAt ?? start
        if now >= start && now <= end {
            self = .current
            return
        }

        if calendar.isDateInToday(start) || calendar.isDateInToday(end) {
            self = .current
            return
        }

        self = end < now ? .past : .future
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
                        enrichment: enrichment
                    )
                    if let enrichment {
                        TravelBriefCard(enrichment: enrichment)
                    }
                    locationActions
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.kind.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(item.kind.timelineAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(momentTitle)
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(momentSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let summary = enrichment?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(defaultBrief)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                let focusCue = primaryCue
                AssistantCue(title: focusCue.title, value: focusCue.value, symbol: focusCue.symbol)
                let timingCue = secondaryCue
                AssistantCue(title: timingCue.title, value: timingCue.value, symbol: timingCue.symbol)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.white, item.kind.timelineAccent.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(item.kind.timelineAccent.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
    }

    private var momentTitle: String {
        switch item.kind {
        case .flight:
            return String(localized: "Make this flight feel calm.")
        case .hotel:
            return String(localized: "Arrive and settle in.")
        case .event:
            return String(localized: "Make the most of this event.")
        case .transit:
            return String(localized: "Move between places smoothly.")
        }
    }

    private var momentSubtitle: String {
        let place = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if place.isEmpty {
            return item.displayTime
        }
        return "\(item.displayTime) · \(place)"
    }

    private var defaultBrief: String {
        switch item.kind {
        case .flight:
            return String(localized: "Voya can track status, timing, gate context, weather, and the route around this flight once enrichment is available.")
        case .hotel:
            return String(localized: "Use this as the base for check-in timing, the arrival route, nearby essentials, and weather-aware plans.")
        case .event:
            return String(localized: "Voya will turn venue context, timing, weather, and nearby options into a practical plan for getting there and enjoying it.")
        case .transit:
            return String(localized: "This leg should become guidance: when to leave, how much buffer to keep, and what fallback route makes sense.")
        }
    }

    private var primaryCue: CompanionCue {
        if let warning = enrichment?.warnings.first, !warning.isEmpty {
            return CompanionCue(title: String(localized: "Watch"), value: trimmedCue(warning), symbol: "exclamationmark.triangle")
        }

        if item.kind == .flight {
            if let gate = card(titled: "Gate") {
                return CompanionCue(title: String(localized: "Gate"), value: trimmedCue(gate.value), symbol: "rectangle.connected.to.line.below")
            }
            if let delay = card(titled: "Delay") {
                return CompanionCue(title: String(localized: "Delay"), value: trimmedCue(delay.value), symbol: "clock.badge.exclamationmark")
            }
        }

        if let action = enrichment?.actions.first {
            return CompanionCue(title: action.priority == "now" ? String(localized: "Do now") : String(localized: "Next"), value: trimmedCue(action.title), symbol: "checkmark.circle")
        }

        if !item.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CompanionCue(title: String(localized: "Status"), value: trimmedCue(item.status), symbol: "checkmark.seal")
        }

        return CompanionCue(title: String(localized: "Focus"), value: phase.insightText, symbol: "scope")
    }

    private var secondaryCue: CompanionCue {
        if let duration = itemDurationText {
            return CompanionCue(title: String(localized: "Duration"), value: duration, symbol: "timer")
        }

        if let routeLeg = enrichment?.routeLegs.first, let bufferMinutes = routeLeg.bufferMinutes {
            return CompanionCue(title: String(localized: "Buffer"), value: String(localized: "\(bufferMinutes) min"), symbol: "figure.walk")
        }

        if item.startsAt != nil {
            return CompanionCue(title: String(localized: "Time"), value: item.displayTime, symbol: "clock")
        }

        return CompanionCue(title: String(localized: "Time"), value: String(localized: "Add time"), symbol: "clock.badge.questionmark")
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

    private func card(titled title: String) -> ItemEnrichmentCard? {
        enrichment?.cards.first { $0.title.localizedCaseInsensitiveContains(title) }
    }

    private func trimmedCue(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 24 ? "\(trimmed.prefix(21))..." : trimmed
    }
}

private struct CompanionCue {
    let title: String
    let value: String
    let symbol: String
}

private struct TravelBriefCard: View {
    @Environment(\.openURL) private var openURL
    let enrichment: ItemEnrichment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Travel brief", systemImage: "sparkles")
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
                    Text("Assistant guidance")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text("Useful signals, translated into travel decisions.")
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
        var rows = [
            AssistantGuidance(
                title: String(localized: "Next move"),
                value: primaryNextMove,
                detail: primaryNextMoveDetail,
                symbol: "figure.walk.motion",
                tint: Color.voyaTeal,
                actionURL: nil
            )
        ]

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
            rows.append(contentsOf: enrichment.actions.prefix(5).map { action in
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
            rows.append(contentsOf: enrichment.cards.prefix(8).map { card in
                AssistantGuidance(
                    title: guidanceTitle(for: card),
                    value: card.value,
                    detail: card.detail,
                    symbol: symbol(for: card.kind),
                    tint: tint(for: card.kind),
                    actionURL: card.actionURL
                )
            })
        } else {
            rows.append(contentsOf: fallbackRows)
        }

        if let firstWarning = enrichment?.warnings.first, !firstWarning.isEmpty {
            rows.insert(
                AssistantGuidance(
                    title: String(localized: "Watch this"),
                    value: firstWarning,
                    detail: String(localized: "Voya will keep this visible because it may affect the plan."),
                    symbol: "exclamationmark.triangle.fill",
                    tint: Color.voyaCoral,
                    actionURL: nil
                ),
                at: min(1, rows.count)
            )
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

    init(trip: Trip) {
        title = trip.title
        destination = trip.destination ?? ""
        summary = trip.summary
        notes = trip.notes ?? ""
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

private struct ImportOption: View {
    let symbol: String
    let title: String
    let tint: Color
    var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(isEnabled ? tint : Color.voyaMuted)
                .frame(width: 42, height: 42)
                .background((isEnabled ? tint : Color.voyaMuted).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? Color.voyaInk : Color.voyaMuted)
                Spacer()
                if !isEnabled {
                    Text("Soon")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

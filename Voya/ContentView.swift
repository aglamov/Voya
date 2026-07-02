import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

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
    @State private var itemBeingEdited: ItineraryItem?
    @State private var itemPendingDeletion: ItineraryItem?
    @State private var tripPendingDeletion: Trip?
    @State private var tripListMode: TripListMode = .upcoming

    private enum TripListMode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case archive = "Archive"

        var id: String { rawValue }
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
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if let trip = displayedTrip {
                    TripHeroCard(trip: trip) {
                        tripPendingDeletion = trip
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
                    SectionHeader(title: "Timeline", action: "Add")

                    VStack(spacing: 0) {
                        ForEach(Array(itinerary.enumerated()), id: \.element.id) { index, item in
                            TimelineRow(item: item, isLast: index == itinerary.count - 1) {
                                itemBeingEdited = item
                            } onDelete: {
                                itemPendingDeletion = item
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
        .alert("Delete trip item?", isPresented: deleteConfirmationBinding, presenting: itemPendingDeletion) { item in
            Button("Delete", role: .destructive) {
                store.deleteItineraryItem(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { item in
            Text("\(item.title) will be removed from this trip.")
        }
        .alert("Delete trip?", isPresented: tripDeleteConfirmationBinding, presenting: tripPendingDeletion) { trip in
            Button("Delete", role: .destructive) {
                store.deleteTrip(trip)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { trip in
            Text("\(trip.title) and its timeline will be removed.")
        }
        .sheet(item: $itemBeingEdited) { item in
            EditItineraryItemView(item: item) { draft in
                store.updateItineraryItem(
                    item,
                    kind: draft.kind,
                    title: draft.title,
                    startsAt: draft.startsAt,
                    endsAt: draft.effectiveEndsAt,
                    location: draft.location,
                    status: draft.status
                )
            }
        }
    }

    private var emptySubtitle: String {
        tripListMode == .archive ? "No archived trips" : "No upcoming trips"
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

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { itemPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    itemPendingDeletion = nil
                }
            }
        )
    }

    private var tripDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { tripPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    tripPendingDeletion = nil
                }
            }
        )
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
                        ExtractionReview(preview: preview) { item in
                            store.updatePreviewItem(item)
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
                        Text(tab.rawValue)
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
            Text(mood.rawValue)
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
    let trip: Trip
    let onDelete: () -> Void

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

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.voyaCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(trip.title)")
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
        .shadow(color: .black.opacity(0.10), radius: 22, y: 14)
        .accessibilityElement(children: .combine)
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
            statusText = "Starts today"
            phaseText = "Today"
        } else if let range, now >= range.start && now <= range.end {
            statusText = "In progress"
            phaseText = "Live"
        } else if let daysUntilStart, daysUntilStart > 0 {
            statusText = "Starts in \(daysUntilStart) \(daysUntilStart == 1 ? "day" : "days")"
            phaseText = "Ready"
        } else if range != nil {
            statusText = "Trip ended"
            phaseText = "Done"
        } else {
            statusText = "Ready when you are"
            phaseText = "Ready"
        }

        if let nights = range?.nights, nights > 0 {
            durationText = "\(nights) \(nights == 1 ? "night" : "nights")"
        } else if let days = range?.days, days > 0 {
            durationText = "\(days) \(days == 1 ? "day" : "days")"
        } else {
            durationText = trip.dates
        }

        itemCountText = "\(trip.items.count) \(trip.items.count == 1 ? "item" : "items")"

        if let firstItem = trip.items.first {
            firstUpText = "First up: \(firstItem.title)"
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
    let isLast: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.voyaTeal)
                    .clipShape(Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.voyaLine)
                        .frame(width: 2, height: 46)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.displayTime)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaCoral)
                    Spacer()
                    Text(item.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaMuted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.black))
                            .foregroundStyle(Color.voyaMuted)
                            .frame(width: 30, height: 30)
                            .background(Color.voyaSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Actions for \(item.title)")
                }

                Text(item.location)
                    .font(.subheadline)
                    .foregroundStyle(Color.voyaMuted)
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

private struct ItineraryItemDraft {
    var kind: ItineraryKind
    var title: String
    var startsAt: Date
    var endsAt: Date
    var hasEndDate: Bool
    var location: String
    var status: String

    init(item: ItineraryItem) {
        kind = item.kind
        title = item.title
        startsAt = item.startsAt ?? Date()
        endsAt = item.endsAt ?? item.startsAt ?? Date()
        hasEndDate = item.endsAt != nil
        location = item.location
        status = item.status
    }

    var effectiveEndsAt: Date? {
        hasEndDate ? max(endsAt, startsAt) : nil
    }

    var displayTime: String {
        ItineraryDateFormatter.displayTime(start: startsAt, end: effectiveEndsAt)
    }
}

private struct EditItineraryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItineraryItemDraft
    let onSave: (ItineraryItemDraft) -> Void

    init(item: ItineraryItem, onSave: @escaping (ItineraryItemDraft) -> Void) {
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit item")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text(draft.kind.rawValue)
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
                        Picker("Type", selection: $draft.kind) {
                            ForEach(ItineraryKind.allCases, id: \.self) { kind in
                                Label(kind.rawValue, systemImage: kind.symbol)
                                    .tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.voyaInk)

                        editField("Title", text: $draft.title)

                        VStack(alignment: .leading, spacing: 10) {
                            DatePicker("Start", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaInk)

                            Toggle("End time", isOn: $draft.hasEndDate)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaInk)

                            if draft.hasEndDate {
                                DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.voyaInk)
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

                        editField("Place", text: $draft.location)
                        editField("Status", text: $draft.status)
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
            Button {
                onSave(draft)
                dismiss()
            } label: {
                Label("Save changes", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            TextField(label, text: text, axis: .vertical)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
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

    private let tags = ["Dates", "Flights", "Hotels", "Places"]

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
        "\(success.itemCount) trip item\(success.itemCount == 1 ? "" : "s")"
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
                    Text(success.didCreateTrip ? "Trip created" : "Added to trip")
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
    let onItemChange: (ItineraryItem) -> Void
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
                    EditableItineraryItem(item: item, onChange: onItemChange)
                }
            }

            Button(action: onConfirm) {
                Label("Save to trip", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct EditableItineraryItem: View {
    @State private var draft: ItineraryItem
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    let onChange: (ItineraryItem) -> Void

    init(item: ItineraryItem, onChange: @escaping (ItineraryItem) -> Void) {
        _draft = State(initialValue: item)
        _hasStartDate = State(initialValue: item.startsAt != nil)
        _startDate = State(initialValue: item.startsAt ?? Date())
        _hasEndDate = State(initialValue: item.endsAt != nil)
        _endDate = State(initialValue: item.endsAt ?? item.startsAt ?? Date())
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(draft.kind.rawValue, systemImage: draft.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
                Text(draft.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(displayTime, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasStartDate ? Color.voyaInk : Color.voyaCoral)

                if hasStartDate {
                    dateTimePickerRow("Start", selection: $startDate)

                    if hasEndDate {
                        dateTimePickerRow("End", selection: $endDate, range: startDate...)
                    }
                }
            }
            .padding(.vertical, 2)

            editableField("Title", text: $draft.title)
            editableField("Place", text: $draft.location)
        }
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: draft.title) { _, _ in onChange(draft) }
        .onChange(of: draft.location) { _, _ in onChange(draft) }
        .onChange(of: draft.updatedAt) { _, _ in syncDatesFromDraft() }
        .onChange(of: startDate) { _, value in
            if endDate < value {
                endDate = value
            }
            commitDates()
        }
        .onChange(of: endDate) { _, _ in commitDates() }
    }

    private var displayTime: String {
        guard hasStartDate else {
            return "Date needed"
        }

        return ItineraryDateFormatter.displayTime(
            start: startDate,
            end: hasEndDate ? endDate : nil
        )
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

    private func syncDatesFromDraft() {
        hasStartDate = draft.startsAt != nil
        startDate = draft.startsAt ?? Date()
        hasEndDate = draft.endsAt != nil
        endDate = draft.endsAt ?? draft.startsAt ?? Date()
    }

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            TextField(label, text: text, axis: .vertical)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1...3)
                .padding(.vertical, 4)
                .frame(minHeight: 38)
        }
    }

    private func commitDates() {
        draft.startsAt = hasStartDate ? startDate : nil
        draft.endsAt = hasStartDate && hasEndDate ? max(endDate, startDate) : nil
        draft.updatedAt = Date()
        onChange(draft)
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
    static let voyaSurface = Color(red: 0.95, green: 0.96, blue: 0.95)
    static let voyaLine = Color(red: 0.86, green: 0.89, blue: 0.88)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(VoyaStore())
    }
}

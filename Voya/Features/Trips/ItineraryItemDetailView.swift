import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct ItineraryItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: VoyaStore
    @State private var draft: ItineraryItemDraft
    @State private var isEditing = false
    @State private var didCopyLocation = false
    @State private var enrichment: ItemEnrichment?
    @State private var isLoadingEnrichment = false
    @State private var sourcePreviewURL: URL?
    @State private var isBoardingPassImporterPresented = false
    @State private var boardingPassImportMessage: String?
    @State private var flightLookupResponse: FlightLookupResponse?
    @State private var isRefreshingFlightStatus = false
    @State private var flightStatusMessage: String?
    @State private var flightAlertWatchStatus: FlightAlertWatchStatus?
    @State private var isUpdatingFlightAlertWatch = false
    @State private var flightAlertWatchMessage: String?
    let tripID: UUID?
    let item: ItineraryItem
    let sourceDocument: SourceDocument?
    let onSave: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        tripID: UUID?,
        item: ItineraryItem,
        sourceDocument: SourceDocument? = nil,
        onSave: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.tripID = tripID
        self.item = item
        self.sourceDocument = sourceDocument
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
                    if item.kind == .flight {
                        boardingPassCard
                        flightStatusCard
                    }
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

                    if sourceDocument != nil || item.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        sourceCard
                    }

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
        .quickLookPreview($sourcePreviewURL)
        .fileImporter(
            isPresented: $isBoardingPassImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleBoardingPassImport(result)
        }
        .task(id: item.id) {
            await loadEnrichment()
            if item.kind == .flight {
                flightLookupResponse = FlightLookupCache.cachedResponse(for: item)
                if !FlightLookupCache.isFresh(for: item) {
                    await refreshFlightStatus(showCompletionMessage: false)
                }
                await updateFlightAlertWatchState()
            }
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
                        .environment(\.timeZone, draft.startTimeZone)

                    Toggle("End time", isOn: $draft.hasEndDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .tint(Color.voyaTeal)

                    if draft.hasEndDate {
                        DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaInk)
                            .environment(\.timeZone, draft.endTimeZone)
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
            if draft.kind == .flight {
                ClearableTextField("Booking reference / PNR", text: $draft.confirmationCode, prompt: "ABC123")
                    .disabled(!isEditing)
                ClearableTextField("Airline / provider", text: $draft.providerName, prompt: "British Airways")
                    .disabled(!isEditing)
            }

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

    private var sourceCard: some View {
        Button {
            guard let sourceDocument else { return }
            sourcePreviewURL = SourceDocumentPreviewer.temporaryURL(for: sourceDocument.sourceFile)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.viewfinder")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaTeal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Source file")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                    Text(sourceDocument?.fileName ?? item.sourceName ?? String(localized: "Manual entry"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if sourceDocument != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(sourceDocument == nil)
    }

    private var boardingPassCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(boardingPassDocument == nil ? Color.voyaTeal : .white)
                    .frame(width: 42, height: 42)
                    .background(boardingPassDocument == nil ? Color.voyaTeal.opacity(0.12) : Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(boardingPassDocument == nil ? "Boarding pass" : "Boarding pass ready")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(boardingPassSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let boardingPassImportMessage {
                Label(boardingPassImportMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let boardingPassDocument {
                HStack(spacing: 10) {
                    Button {
                        sourcePreviewURL = SourceDocumentPreviewer.temporaryURL(for: boardingPassDocument.sourceFile)
                    } label: {
                        Label("Show", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isBoardingPassImporterPresented = true
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(Color.voyaInk)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        store.removeBoardingPass(from: item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaCoral)
                            .frame(width: 44, height: 44)
                            .background(Color.voyaCoral.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove boarding pass")
                }
            } else {
                Button {
                    isBoardingPassImporterPresented = true
                } label: {
                    Label("Add boarding pass", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
    }

    private var flightStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "airplane.departure")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.voyaSky)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Flight status")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(flightStatusSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        await refreshFlightStatus()
                    }
                } label: {
                    if isRefreshingFlightStatus {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.voyaTeal)
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(flightLookupNumber == nil ? Color.voyaMuted : Color.voyaTeal)
                            .frame(width: 38, height: 38)
                    }
                }
                .background(Color.voyaSurface)
                .clipShape(Circle())
                .buttonStyle(.plain)
                .disabled(isRefreshingFlightStatus || flightLookupNumber == nil)
                .accessibilityLabel("Refresh flight status")
            }

            if let response = flightLookupResponse {
                FlightStatusSummaryView(response: response)
            } else {
                Text(flightStatusMessage ?? String(localized: "Refresh to pull the latest gate, delay estimate, and reliability signal from the flight provider."))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(flightStatusMessage == nil ? Color.voyaMuted : Color.voyaCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            flightAlertWatchControl
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
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

    private var boardingPassDocument: SourceDocument? {
        store.boardingPassDocument(for: item)
    }

    private var boardingPassSubtitle: String {
        if let boardingPassDocument {
            return boardingPassDocument.fileName
        }

        return String(localized: "Attach a PDF or image to this flight for quick access at the airport.")
    }

    private var locationActionTitle: String {
        LocationLinkResolver.directURL(from: draft.location) == nil ? String(localized: "Open map") : String(localized: "Open link")
    }

    private var flightLookupNumber: String? {
        guard item.kind == .flight else {
            return nil
        }

        return store.firstFlightNumber(in: "\(item.title) \(item.location)")
    }

    private var flightStatusSubtitle: String {
        flightLookupNumber.map { String(localized: "Live lookup and push watch for \($0).") }
            ?? String(localized: "Add a flight number to enable live lookup.")
    }

    private var isFlightAlertSubscribed: Bool {
        flightAlertWatchStatus?.subscribed == true
    }

    private var flightAlertWatchControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    await subscribeToFlightAlerts()
                }
            } label: {
                HStack(spacing: 10) {
                    if isUpdatingFlightAlertWatch {
                        ProgressView()
                            .scaleEffect(0.78)
                            .tint(Color.voyaTeal)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: isFlightAlertSubscribed ? "checkmark.circle.fill" : "bell.badge")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isFlightAlertSubscribed ? Color.voyaTeal : Color.voyaInk)
                            .frame(width: 20, height: 20)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isFlightAlertSubscribed ? "Alerts subscribed" : "Subscribe to alerts")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.voyaInk)
                        Text(flightAlertWatchDetail)
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
            .buttonStyle(.plain)
            .disabled(isUpdatingFlightAlertWatch || isFlightAlertSubscribed || flightLookupNumber == nil)
            .opacity(flightLookupNumber == nil ? 0.55 : 1)

            if let message = flightAlertWatchMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isFlightAlertSubscribed ? Color.voyaTeal : Color.voyaCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var flightAlertWatchDetail: String {
        if let error = flightAlertWatchStatus?.error?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return error
        }

        if isFlightAlertSubscribed {
            return String(localized: "FlightAware will notify Voya about major flight changes.")
        }

        if flightAlertWatchStatus?.configured == false {
            return String(localized: "FlightAware alerts are not configured on the backend yet.")
        }

        return String(localized: "Create a FlightAware alert rule for this flight.")
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

    private func handleBoardingPassImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            return
        }

        do {
            let sourceFile = try SourceDocumentFile.imported(from: url)
            store.attachBoardingPass(sourceFile, to: item)
            draft.status = String(localized: "Checked in")
            boardingPassImportMessage = nil
        } catch {
            boardingPassImportMessage = String(localized: "Could not attach this boarding pass.")
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

    @MainActor
    private func refreshFlightStatus(showCompletionMessage: Bool = true) async {
        guard let flightNumber = flightLookupNumber, !isRefreshingFlightStatus else {
            return
        }

        isRefreshingFlightStatus = true
        flightStatusMessage = nil
        defer { isRefreshingFlightStatus = false }

        let route = store.airportRouteCodes(in: item.location)
        do {
            let response = try await VercelFlightLookupService().lookup(
                flightNumber: flightNumber,
                date: item.startsAt,
                dateTimeZoneOffsetSeconds: item.startsAtTimeZoneOffsetSeconds,
                originAirport: route?.origin,
                destinationAirport: route?.destination
            )
            flightLookupResponse = response
            FlightLookupCache.store(response, for: item)
            try? modelContext.save()

            if let candidate = response.candidate {
                let watchResponse = await VoyaPushRegistrationService.shared.registerFlightWatch(for: item, tripID: tripID, candidate: candidate)
                flightAlertWatchStatus = watchResponse?.alertWatch
                if showCompletionMessage {
                    flightStatusMessage = String(localized: "Flight status refreshed.")
                }
            } else {
                let watchResponse = await VoyaPushRegistrationService.shared.registerFlightWatch(for: item, tripID: tripID)
                flightAlertWatchStatus = watchResponse?.alertWatch
                flightStatusMessage = response.warnings.first ?? response.validation.reasons.first ?? String(localized: "No matching live flight was found.")
            }
        } catch {
            if flightLookupResponse == nil {
                flightStatusMessage = String(localized: "Flight lookup is unavailable right now.")
            }
        }
    }

    @MainActor
    private func updateFlightAlertWatchState() async {
        let response = await VoyaPushRegistrationService.shared.registerFlightWatch(for: item, tripID: tripID)
        flightAlertWatchStatus = response?.alertWatch
    }

    @MainActor
    private func subscribeToFlightAlerts() async {
        guard !isUpdatingFlightAlertWatch else {
            return
        }

        isUpdatingFlightAlertWatch = true
        flightAlertWatchMessage = nil
        defer { isUpdatingFlightAlertWatch = false }

        let response = await VoyaPushRegistrationService.shared.registerFlightWatch(
            for: item,
            tripID: tripID,
            candidate: flightLookupResponse?.candidate,
            subscribeToAlerts: true
        )
        flightAlertWatchStatus = response?.alertWatch

        if response?.alertWatch?.subscribed == true {
            flightAlertWatchMessage = String(localized: "Flight alerts are enabled for this flight.")
        } else {
            flightAlertWatchMessage = response?.alertWatch?.error ?? String(localized: "Could not enable FlightAware alerts for this flight.")
        }
    }
}

private struct FlightStatusSummaryView: View {
    @Environment(\.openURL) private var openURL
    @State private var isShowingMore = false
    let response: FlightLookupResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                Spacer(minLength: 8)
                if let providerName = response.provider?.name {
                    Text(providerName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.voyaMuted)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                FlightStatusMetric(title: String(localized: "Gate"), value: gateValue)
                FlightStatusMetric(title: String(localized: "Delay"), value: delayValue)
            }

            if departureTiming != nil || arrivalTiming != nil {
                HStack(spacing: 10) {
                    FlightTimingMetric(
                        airport: response.snapshot?.originAirport ?? response.candidate?.originAirport ?? String(localized: "Departure"),
                        timing: departureTiming
                    )
                    Image(systemName: "airplane")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaSky)
                    FlightTimingMetric(
                        airport: response.snapshot?.destinationAirport ?? response.candidate?.destinationAirport ?? String(localized: "Arrival"),
                        timing: arrivalTiming,
                        alignment: .trailing
                    )
                }
                .padding(12)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let headline = response.delayStats?.headline.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                Label(headline, systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle((response.delayStats?.delayMinutes ?? 0) >= 15 ? Color.voyaCoral : Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reliabilityText {
                Label(reliabilityText, systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasMoreDetails {
                DisclosureGroup(isExpanded: $isShowingMore) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let arrivalDetail {
                            flightDetailRow(symbol: "airplane.arrival", title: String(localized: "Arrival"), value: arrivalDetail)
                        }
                        if let baggage = response.gate?.baggageClaim ?? response.snapshot?.baggageClaim ?? response.candidate?.baggageClaim {
                            flightDetailRow(symbol: "suitcase.fill", title: String(localized: "Baggage"), value: baggage)
                        }
                        if let aircraftDetail {
                            Button {
                                if let position = response.snapshot?.position ?? response.plane?.position,
                                   let url = URL(string: "https://maps.apple.com/?ll=\(position.lat),\(position.lon)") {
                                    openURL(url)
                                }
                            } label: {
                                flightDetailRow(
                                    symbol: "airplane.circle.fill",
                                    title: String(localized: "Aircraft"),
                                    value: aircraftDetail,
                                    showsLink: (response.snapshot?.position ?? response.plane?.position) != nil
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled((response.snapshot?.position ?? response.plane?.position) == nil)
                        }
                        if let routeDetail {
                            flightDetailRow(symbol: "point.topleft.down.curvedto.point.bottomright.up", title: String(localized: "Route"), value: routeDetail)
                        }
                        ForEach(response.intelligence?.disruptions.prefix(3) ?? []) { disruption in
                            flightDetailRow(
                                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                                title: disruption.entityName ?? disruption.entityId ?? disruption.entityType.capitalized,
                                value: disruptionText(disruption)
                            )
                        }
                        if let weatherDetail {
                            flightDetailRow(symbol: "cloud.sun.fill", title: String(localized: "Airport weather"), value: weatherDetail)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("More live details", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaTeal)
                }
            }

            ForEach(response.warnings.filter { !$0.isEmpty }.prefix(3), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let nextAction = response.nextActions?.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                Label(nextAction, systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaTeal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let attribution = response.provider?.attribution.nilIfEmpty {
                Text(attribution)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        if response.provider?.connected == false {
            return String(localized: "Live provider unavailable")
        }
        return response.snapshot?.providerStatus?.nilIfEmpty
            ?? response.candidate?.providerStatus?.nilIfEmpty
            ?? response.snapshot?.status.capitalized
            ?? String(localized: "Provider verified")
    }

    private var statusTint: Color {
        if response.provider?.connected == false { return Color.voyaGold }
        let status = "\(response.snapshot?.status ?? "") \(statusText)".lowercased()
        if status.contains("cancel") || status.contains("divert") { return Color.voyaCoral }
        if status.contains("delay") { return Color.voyaGold }
        return Color.voyaTeal
    }

    private var gateValue: String {
        let terminal = response.gate?.departureTerminal ?? response.candidate?.departureTerminal
        let gate = response.gate?.departureGate ?? response.candidate?.departureGate
        let parts = [
            terminal.map { String(localized: "T\($0)") },
            gate.map { String(localized: "Gate \($0)") }
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }

        return parts.isEmpty ? String(localized: "Not posted") : parts.joined(separator: " · ")
    }

    private var delayValue: String {
        guard let delayMinutes = response.delayStats?.delayMinutes else {
            return response.delayStats?.onTimeProbability.map { "\(Int(($0 * 100).rounded()))%" } ?? String(localized: "Checking")
        }

        if delayMinutes <= 5 {
            return String(localized: "On time")
        }

        return String(localized: "\(delayMinutes) min")
    }

    private var departureTiming: FlightDisplayTiming? {
        timing(
            actual: response.schedule?.actualDepartureAt ?? response.snapshot?.actualDepartureAt,
            estimated: response.schedule?.estimatedDepartureAt ?? response.snapshot?.estimatedDepartureAt,
            scheduled: response.schedule?.scheduledDepartureAt ?? response.snapshot?.scheduledDepartureAt ?? response.candidate?.departureAt
        )
    }

    private var arrivalTiming: FlightDisplayTiming? {
        timing(
            actual: response.schedule?.actualArrivalAt ?? response.snapshot?.actualArrivalAt,
            estimated: response.schedule?.estimatedArrivalAt ?? response.snapshot?.estimatedArrivalAt,
            scheduled: response.schedule?.scheduledArrivalAt ?? response.snapshot?.scheduledArrivalAt ?? response.candidate?.arrivalAt
        )
    }

    private func timing(actual: String?, estimated: String?, scheduled: String?) -> FlightDisplayTiming? {
        if let actual = actual?.nilIfEmpty {
            return FlightDisplayTiming(value: FlightProviderClock.display(actual), label: String(localized: "Actual"), tone: .actual)
        }
        if let estimated = estimated?.nilIfEmpty {
            return FlightDisplayTiming(value: FlightProviderClock.display(estimated), label: String(localized: "Estimated"), tone: .estimated)
        }
        if let scheduled = scheduled?.nilIfEmpty {
            return FlightDisplayTiming(value: FlightProviderClock.display(scheduled), label: String(localized: "Scheduled"), tone: .scheduled)
        }
        return nil
    }

    private var reliabilityText: String? {
        guard let reliability = response.reliability ?? response.intelligence?.history else {
            return response.delayStats?.onTimeProbability.map { String(localized: "\(Int(($0 * 100).rounded()))% Voya on-time estimate") }
        }

        let delayed = reliability.delayed15Rate.map { "\(Int(($0 * 100).rounded()))% delayed" }
        let average = reliability.averageArrivalDelayMinutes.map { "avg arrival delay \(Int($0.rounded())) min" }
        let sample = reliability.sampleSize > 0 ? "\(reliability.sampleSize) recent flights" : nil

        return [sample, delayed, average]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var arrivalDetail: String? {
        let terminal = response.gate?.arrivalTerminal ?? response.snapshot?.arrivalTerminal ?? response.candidate?.arrivalTerminal
        let gate = response.gate?.arrivalGate ?? response.snapshot?.arrivalGate ?? response.candidate?.arrivalGate
        let parts = [
            terminal.map { String(localized: "Terminal \($0)") },
            gate.map { String(localized: "Gate \($0)") }
        ].compactMap { $0?.nilIfEmpty }
        return parts.joined(separator: " · ").nilIfEmpty
    }

    private var aircraftDetail: String? {
        let progress = response.snapshot?.progressPercent ?? response.plane?.progressPercent
        let progressText = progress.map { value in
            String(localized: "\(Int(value.rounded()))% complete")
        }
        let parts = [
            response.snapshot?.aircraftRegistration ?? response.plane?.aircraftRegistration ?? response.candidate?.aircraftRegistration,
            response.snapshot?.aircraftType ?? response.plane?.aircraftType ?? response.candidate?.aircraftType,
            progressText
        ].compactMap { $0?.nilIfEmpty }
        return parts.joined(separator: " · ").nilIfEmpty
    }

    private var routeDetail: String? {
        let route = response.intelligence?.route
        return [route?.routeDistance, route?.route?.prefix(90).description]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var weatherDetail: String? {
        let weather = response.intelligence?.weather
        let origin = weather?.origin
        let destination = weather?.destination
        let originText = [
            origin?.airport,
            origin?.temperatureC.map { "\(Int($0.rounded())) °C" },
            origin?.summary ?? origin?.forecastSummary
        ].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
        let destinationText = [
            destination?.airport,
            destination?.temperatureC.map { "\(Int($0.rounded())) °C" },
            destination?.summary ?? destination?.forecastSummary
        ].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
        return [originText, destinationText].compactMap { $0 }.joined(separator: " → ").nilIfEmpty
    }

    private var hasMoreDetails: Bool {
        arrivalDetail != nil
            || aircraftDetail != nil
            || routeDetail != nil
            || weatherDetail != nil
            || !(response.intelligence?.disruptions.isEmpty ?? true)
            || (response.gate?.baggageClaim ?? response.snapshot?.baggageClaim ?? response.candidate?.baggageClaim) != nil
    }

    private func disruptionText(_ disruption: FlightDisruptionStats) -> String {
        let delayed = disruption.delays.map { String(localized: "\($0) delayed") }
        let cancelled = disruption.cancellations.map { String(localized: "\($0) cancelled") }
        return [delayed, cancelled, disruption.timePeriod].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
    }

    private func flightDetailRow(symbol: String, title: String, value: String, showsLink: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.voyaMuted)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsLink {
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
            }
        }
    }
}

private struct FlightDisplayTiming {
    enum Tone { case actual, estimated, scheduled }
    let value: String
    let label: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .actual: Color.voyaTeal
        case .estimated: Color.voyaGold
        case .scheduled: Color.voyaMuted
        }
    }
}

private struct FlightTimingMetric: View {
    let airport: String
    let timing: FlightDisplayTiming?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(airport)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            Text(timing?.value ?? "—")
                .font(.title3.weight(.bold))
                .foregroundStyle(timing?.color ?? Color.voyaMuted)
            Text(timing?.label ?? String(localized: "Not available"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.voyaMuted)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

private enum FlightProviderClock {
    static func display(_ value: String) -> String {
        let pattern = #"T(\d{2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 0), in: value) else {
            return value
        }
        return value[range].dropFirst().description
    }
}

private struct FlightStatusMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

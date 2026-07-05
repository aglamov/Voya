import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct TripsView: View {
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
    @State private var sourcePreviewURL: URL?

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
                    TripOperationsCard(trip: trip, itinerary: itinerary) { sourceFile in
                        sourcePreviewURL = SourceDocumentPreviewer.temporaryURL(for: sourceFile)
                    }

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
        .quickLookPreview($sourcePreviewURL)
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
            let plan = try await VercelMobilityService().planTransfer(context: context)
            mobilityPlans[context.id] = plan
            if let option = plan.defaultOption {
                await VoyaNotificationScheduler.shared.scheduleTransferNotification(context: context, option: option)
            }
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

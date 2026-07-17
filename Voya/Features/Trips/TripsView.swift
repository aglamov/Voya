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
    @Binding var selectedTab: VoyaTab
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""
    @AppStorage(VoyaPreferenceKey.hiddenTransferIDs) private var hiddenTransferIDsRaw = ""
    @AppStorage(VoyaPreferenceKey.transferBufferOverrides) private var transferBufferOverridesRaw = "{}"
    @AppStorage(VoyaPreferenceKey.arrivalFormalitiesOverrides) private var arrivalFormalitiesOverridesRaw = "{}"
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
                    subtitle: displayedTrip.map { "\($0.destination?.nilIfEmpty ?? $0.title), \($0.displayDates)" } ?? emptySubtitle
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

                    let timeline = store.timelineItinerary(for: trip)
                    TripOperationsCard(trip: trip, itinerary: timeline) { item in
                        store.assistantFocusItemID = item.id
                        selectedTab = .assistant
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

                    if hiddenTransferCount(for: trip, itinerary: timeline) > 0 {
                        RestoreHiddenTransfersCard(
                            count: hiddenTransferCount(for: trip, itinerary: timeline)
                        ) {
                            restoreHiddenTransfers(for: trip, itinerary: timeline)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(timeline.enumerated()), id: \.element.id) { index, item in
                            if index == 0 {
                                if let rawContext = VercelMobilityService.startTransferContext(
                                    for: trip,
                                    firstItem: item,
                                    defaultHomeAddress: homeLocationAddress,
                                    defaultHomeName: homeLocationName
                                ) {
                                    let context = adjustedTransferContext(rawContext)
                                    if !isTransferHidden(context) {
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
                                        .task(id: "\(context.id)-\(context.airportBufferMinutes)-\(context.arrivalFormalitiesMinutes)") {
                                            await loadMobilityPlan(context: context)
                                        }
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
                                isLast: index == timeline.count - 1
                            ) {
                                itemBeingViewed = item
                            }

                            if index + 1 < timeline.count,
                               let layover = FlightLayoverDisplay(arrivingFlight: item, departingFlight: timeline[index + 1]) {
                                FlightLayoverCard(layover: layover)
                            }

                            if index + 1 < timeline.count,
                               let rawContext = VercelMobilityService.transferContext(
                                   from: item,
                                   to: timeline[index + 1],
                                   tripID: trip.id
                               ) {
                                let context = adjustedTransferContext(rawContext)
                                if !isTransferHidden(context) {
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
                                                await loadMobilityPlan(context: context, forceRefresh: true)
                                            }
                                        }
                                    )
                                    .task(id: "\(context.id)-\(context.airportBufferMinutes)-\(context.arrivalFormalitiesMinutes)") {
                                        await loadMobilityPlan(context: context)
                                    }
                                }
                            }

                            if index == timeline.count - 1 {
                                if let rawContext = VercelMobilityService.endTransferContext(
                                    for: trip,
                                    lastItem: item,
                                    defaultHomeAddress: homeLocationAddress,
                                    defaultHomeName: homeLocationName
                                ) {
                                    let context = adjustedTransferContext(rawContext)
                                    if !isTransferHidden(context) {
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
                                        .task(id: "\(context.id)-\(context.airportBufferMinutes)-\(context.arrivalFormalitiesMinutes)") {
                                            await loadMobilityPlan(context: context)
                                        }
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
                    VStack(spacing: 12) {
                        EmptyTripsCard(
                            title: tripListMode == .archive ? "Archive is empty" : "No upcoming trips",
                            message: tripListMode == .archive ? "Past trips will appear here after they end." : "Import a confirmation to build your next itinerary.",
                            symbol: tripListMode == .archive ? "archivebox" : "calendar.badge.plus"
                        )

                        if tripListMode == .upcoming {
                            Button {
                                selectedTab = .import
                            } label: {
                                Label("Import your first trip", systemImage: "tray.and.arrow.down.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .foregroundStyle(.white)
                                    .background(Color.voyaInk)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .onAppear {
            selectDisplayedTripIfNeeded()
            openNotificationItemIfNeeded()
        }
        .onChange(of: tripListMode) { _, _ in
            selectDisplayedTripIfNeeded()
        }
        .onChange(of: store.trips.count) { _, _ in
            selectDisplayedTripIfNeeded()
            openNotificationItemIfNeeded()
        }
        .onChange(of: store.notificationItemID) { _, _ in
            openNotificationItemIfNeeded()
        }
        .sheet(item: $tripBeingEdited) { trip in
            EditTripView(trip: trip) { draft in
                store.updateTrip(
                    trip,
                    title: draft.title,
                    destination: draft.destination,
                    destinationLocation: draft.destinationLocation,
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
            }
        }
        .sheet(item: $itemBeingViewed) { item in
            ItineraryItemDetailView(
                tripID: store.trips.first(where: { trip in trip.items.contains(where: { $0.id == item.id }) })?.id,
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
        .sheet(item: $transferBeingViewed) { context in
            let context = adjustedTransferContext(context)
            TransferDetailView(
                context: context,
                plan: mobilityPlans[context.id],
                errorMessage: mobilityPlanErrors[context.id],
                isLoading: loadingMobilityPlanIDs.contains(context.id),
                onRefresh: { refreshedContext in
                    Task {
                        await loadMobilityPlan(context: refreshedContext, forceRefresh: true)
                    }
                },
                onUpdateBuffers: { beforeMinutes, afterMinutes, routeContext in
                    setTransferBufferOverride(beforeMinutes, for: context)
                    setArrivalFormalitiesOverride(afterMinutes, for: context)
                    VoyaNotificationScheduler.shared.cancelTransferNotification(context: context)
                    Task {
                        await loadMobilityPlan(context: routeContext, forceRefresh: true)
                    }
                },
                onUpdateRoute: { origin, destination in
                    var updatedContext = context
                    updatedContext.origin = origin
                    updatedContext.destination = destination

                    if let tripID = context.tripID,
                       let trip = store.trips.first(where: { $0.id == tripID }) {
                        store.updateTransferRoute(
                            for: context,
                            in: trip,
                            origin: origin,
                            destination: destination
                        )
                    }

                    mobilityPlans[context.id] = nil
                    mobilityPlanErrors[context.id] = nil
                    MobilityPlanCache.clear(for: context)
                    Task {
                        await loadMobilityPlan(context: updatedContext, forceRefresh: true)
                    }
                },
                onDelete: {
                    hideTransfer(context)
                    transferBeingViewed = nil
                }
            )
            .task(id: "\(context.id)-\(context.airportBufferMinutes)-\(context.arrivalFormalitiesMinutes)") {
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

    private func openNotificationItemIfNeeded() {
        guard let itemID = store.notificationItemID,
              let trip = store.trips.first(where: { trip in trip.items.contains(where: { $0.id == itemID }) }),
              trip.items.contains(where: { $0.id == itemID }) else {
            return
        }

        // Consume the route before changing view state so the onChange handler
        // cannot re-enter and attempt to present the same sheet twice.
        store.notificationItemID = nil
        tripListMode = store.isArchived(trip, at: Date()) ? .archive : .upcoming
        store.selectedTripID = trip.id

        Task { @MainActor in
            await Task.yield()
            guard itemBeingViewed == nil,
                  let item = store.trips
                    .flatMap(\.items)
                    .first(where: { $0.id == itemID }) else {
                return
            }
            itemBeingViewed = item
        }
    }

    @MainActor
    private func loadMobilityPlan(context: MobilityTransferContext, forceRefresh: Bool = false) async {
        if !forceRefresh, mobilityPlans[context.id] != nil {
            return
        }
        if !forceRefresh, let cached = MobilityPlanCache.freshPlan(for: adjustedTransferContext(context)) {
            mobilityPlans[context.id] = cached
            if let option = cached.defaultOption {
                await VoyaNotificationScheduler.shared.scheduleTransferNotification(context: adjustedTransferContext(context), option: option)
            }
            return
        }
        guard forceRefresh || !loadingMobilityPlanIDs.contains(context.id) else {
            return
        }

        loadingMobilityPlanIDs.insert(context.id)
        mobilityPlanErrors[context.id] = nil
        defer {
            loadingMobilityPlanIDs.remove(context.id)
        }

        let adjustedContext = adjustedTransferContext(context)

        do {
            let plan = try await VercelMobilityService().planTransfer(context: adjustedContext)
            let currentContext = adjustedTransferContext(context)
            guard currentContext.airportBufferMinutes == adjustedContext.airportBufferMinutes,
                  currentContext.arrivalFormalitiesMinutes == adjustedContext.arrivalFormalitiesMinutes,
                  currentContext.origin == adjustedContext.origin,
                  currentContext.destination == adjustedContext.destination else {
                return
            }
            mobilityPlans[context.id] = plan
            MobilityPlanCache.store(plan, for: adjustedContext)
            if let option = plan.defaultOption {
                await VoyaNotificationScheduler.shared.scheduleTransferNotification(context: adjustedContext, option: option)
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

    private var hiddenTransferIDs: Set<String> {
        Set(hiddenTransferIDsRaw.split(separator: "\n").map(String.init))
    }

    private func isTransferHidden(_ context: MobilityTransferContext) -> Bool {
        hiddenTransferIDs.contains(context.id)
    }

    private func hideTransfer(_ context: MobilityTransferContext) {
        VoyaNotificationScheduler.shared.cancelTransferNotification(context: context)
        var ids = hiddenTransferIDs
        ids.insert(context.id)
        hiddenTransferIDsRaw = ids.sorted().joined(separator: "\n")
        mobilityPlans[context.id] = nil
        mobilityPlanErrors[context.id] = nil
        loadingMobilityPlanIDs.remove(context.id)
        MobilityPlanCache.clear(for: context)
    }

    private var transferBufferOverrides: [String: Int] {
        guard let data = transferBufferOverridesRaw.data(using: .utf8),
              let overrides = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return overrides
    }

    private var arrivalFormalitiesOverrides: [String: Int] {
        guard let data = arrivalFormalitiesOverridesRaw.data(using: .utf8),
              let overrides = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return overrides
    }

    private func adjustedTransferContext(_ context: MobilityTransferContext) -> MobilityTransferContext {
        var adjustedContext = context

        if let bufferMinutes = transferBufferOverrides[context.id] {
            adjustedContext.airportBufferMinutes = bufferMinutes
        }

        if let formalitiesMinutes = arrivalFormalitiesOverrides[context.id] {
            adjustedContext = adjustedContext.adjustingArrivalFormalities(to: formalitiesMinutes)
        }

        if let tripID = context.tripID,
           let trip = store.trips.first(where: { $0.id == tripID }),
           let routeOverride = trip.transferRouteOverride(for: context.id) {
            adjustedContext.origin = routeOverride.origin
            adjustedContext.destination = routeOverride.destination
        }

        return adjustedContext
    }

    private func setTransferBufferOverride(_ minutes: Int, for context: MobilityTransferContext) {
        var overrides = transferBufferOverrides
        overrides[context.id] = minutes
        if let data = try? JSONEncoder().encode(overrides),
           let rawValue = String(data: data, encoding: .utf8) {
            transferBufferOverridesRaw = rawValue
        }
        mobilityPlans[context.id] = nil
        mobilityPlanErrors[context.id] = nil
    }

    private func setArrivalFormalitiesOverride(_ minutes: Int, for context: MobilityTransferContext) {
        let boundedMinutes = min(max(minutes, 0), 180)
        var overrides = arrivalFormalitiesOverrides
        overrides[context.id] = boundedMinutes
        if let data = try? JSONEncoder().encode(overrides),
           let rawValue = String(data: data, encoding: .utf8) {
            arrivalFormalitiesOverridesRaw = rawValue
        }

        mobilityPlans[context.id] = nil
        mobilityPlanErrors[context.id] = nil
    }

    private func transferContexts(for trip: Trip, itinerary: [ItineraryItem]) -> [MobilityTransferContext] {
        guard !itinerary.isEmpty else {
            return []
        }

        var contexts: [MobilityTransferContext] = []

        if let firstItem = itinerary.first,
           let context = VercelMobilityService.startTransferContext(
            for: trip,
            firstItem: firstItem,
            defaultHomeAddress: homeLocationAddress,
            defaultHomeName: homeLocationName
           ) {
            contexts.append(context)
        }

        for index in itinerary.indices.dropLast() {
            if let context = VercelMobilityService.transferContext(
                from: itinerary[index],
                to: itinerary[index + 1],
                tripID: trip.id
            ) {
                contexts.append(context)
            }
        }

        if let lastItem = itinerary.last,
           let context = VercelMobilityService.endTransferContext(
            for: trip,
            lastItem: lastItem,
            defaultHomeAddress: homeLocationAddress,
            defaultHomeName: homeLocationName
           ) {
            contexts.append(context)
        }

        return contexts
    }

    private func hiddenTransferCount(for trip: Trip, itinerary: [ItineraryItem]) -> Int {
        transferContexts(for: trip, itinerary: itinerary)
            .filter { hiddenTransferIDs.contains($0.id) }
            .count
    }

    private func restoreHiddenTransfers(for trip: Trip, itinerary: [ItineraryItem]) {
        let restorableIDs = Set(transferContexts(for: trip, itinerary: itinerary).map(\.id))
        let remainingIDs = hiddenTransferIDs.subtracting(restorableIDs)
        hiddenTransferIDsRaw = remainingIDs.sorted().joined(separator: "\n")
    }

}

struct RestoreHiddenTransfersCard: View {
    let count: Int
    let onRestore: () -> Void

    var body: some View {
        Button(action: onRestore) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
                    .frame(width: 34, height: 34)
                    .background(Color.voyaTeal.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Hidden transfers")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                    Text(count == 1 ? "Restore hidden transfer" : "Restore \(count) hidden transfers")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
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
                    .stroke(Color.voyaTeal.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

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
    @EnvironmentObject private var store: VoyaStore
    @AppStorage(VoyaPreferenceKey.homeLocationName) private var homeLocationName = "Home"
    @AppStorage(VoyaPreferenceKey.homeLocationAddress) private var homeLocationAddress = ""
    @State private var itemBeingViewed: ItineraryItem?
    @State private var assistantQuestion = String(localized: "What if my flight is delayed?")
    @State private var assistantAnswer: String?

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

    private var attentionItems: [ItineraryItem] {
        itinerary.filter { item in
            item.startsAt == nil
                || item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.location.localizedCaseInsensitiveContains("needed")
                || item.status.localizedCaseInsensitiveContains("needs")
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Assistant", subtitle: "Live support")

                AssistantStatusCard(
                    trip: trip,
                    nextItem: nextItem,
                    alertCount: store.alerts.count,
                    attentionCount: attentionItems.count
                )

                if let nextItem {
                    Button {
                        itemBeingViewed = nextItem
                    } label: {
                        AssistantNextActionCard(item: nextItem)
                    }
                    .buttonStyle(.plain)
                } else {
                    EmptyTripsCard(
                        title: "No trip to watch",
                        message: "Import a confirmation and Voya will turn itinerary timing, alerts, and routes into assistant actions.",
                        symbol: "message.badge"
                    )
                }

                if !attentionItems.isEmpty {
                    AssistantAttentionCard(items: Array(attentionItems.prefix(3))) { item in
                        itemBeingViewed = item
                    }
                }

                AssistantQuestionCard(
                    question: $assistantQuestion,
                    answer: assistantAnswer,
                    prompts: quickPrompts,
                    onPrompt: { prompt in
                        assistantQuestion = prompt
                        assistantAnswer = answer(for: prompt)
                    },
                    onSend: {
                        assistantAnswer = answer(for: assistantQuestion)
                    }
                )

                VStack(spacing: 12) {
                    ForEach(store.alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }

                HomeBaseSettingsCard(
                    homeLocationName: $homeLocationName,
                    homeLocationAddress: $homeLocationAddress
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
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

    private var quickPrompts: [String] {
        [
            String(localized: "What should I do next?"),
            String(localized: "When should I leave?"),
            String(localized: "What if my flight is delayed?")
        ]
    }

    private func answer(for question: String) -> String {
        let normalized = question.lowercased()
        guard let trip else {
            return String(localized: "Import a confirmation first. After that I can watch timing, route choices, flight status, and missing booking fields.")
        }

        if normalized.contains("delay") || normalized.contains("flight") {
            if let flight = itinerary.first(where: { $0.kind == .flight && ItineraryPhase(item: $0) != .past }) {
                return String(localized: "Keep \(flight.title) open in the trip. If the provider reports a delay, Voya compares the new arrival with the next item and keeps the booking source handy for airline support.")
            }
            return String(localized: "There is no upcoming flight in \(trip.title). I will focus on route timing and check-in reminders instead.")
        }

        if normalized.contains("leave") || normalized.contains("route") {
            if let nextItem {
                return String(localized: "For \(nextItem.title), use the transfer card in Trips for live timing. Taxi and car stay concise; public transit shows the line, departure time, and stop to get off.")
            }
            return String(localized: "Add a timed itinerary item and route guidance will appear around it.")
        }

        if let nextItem {
            return String(localized: "Next: \(nextItem.title) at \(nextItem.displayTime). Check the place, route, and status fields; if anything is uncertain, open the item and correct it before travel day.")
        }

        return String(localized: "\(trip.title) is saved, but it needs timed itinerary items before I can produce useful live guidance.")
    }
}

struct AssistantStatusCard: View {
    let trip: Trip?
    let nextItem: ItineraryItem?
    let alertCount: Int
    let attentionCount: Int

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

                Image(systemName: attentionCount == 0 ? "shield.checkered" : "exclamationmark.triangle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(attentionCount == 0 ? Color.voyaTeal : Color.voyaCoral)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                MetricPill(title: "Alerts", value: "\(alertCount)")
                MetricPill(title: "Risk", value: attentionCount == 0 ? "Low" : "Review")
                MetricPill(title: "Next", value: nextItem?.startsAt.map { MomentDateFormatter.time.string(from: $0) } ?? "Set")
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

        return attentionCount == 0 ? String(localized: "\(trip.title) looks calm.") : String(localized: "\(trip.title) needs review.")
    }

    private var subtitle: String {
        if let nextItem {
            return String(localized: "Watching \(nextItem.title), route timing, and provider updates.")
        }

        return String(localized: "Import or add itinerary items to activate live trip support.")
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

            if let answer {
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

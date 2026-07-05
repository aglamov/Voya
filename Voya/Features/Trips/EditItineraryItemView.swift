import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct EditItineraryItemView: View {
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

struct TripDraft {
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

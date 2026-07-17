import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct TimelineRow: View {
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

struct FlightLayoverDisplay {
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

struct FlightLayoverCard: View {
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

struct TransferRecommendationCard: View {
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
                    Text(routeTitle)
                        .font(.headline)
                        .foregroundStyle(phase.titleColor)
                        .lineLimit(2)

                    if transitOption == nil {
                        Text(primaryDetail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(phase.secondaryColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    .accessibilityLabel(Text("Refresh transfer timing"))

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

            if !visibleOptions.isEmpty {
                VStack(spacing: 8) {
                    if let transitOption {
                        optionPreviewTile(transitOption, isProminent: true)
                    }

                    let compactOptions = visibleOptions.filter { $0.mode != .transit }
                    if !compactOptions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(compactOptions.prefix(2)) { option in
                                optionPreviewTile(option, isProminent: false)
                            }
                        }
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

    private var transitOption: MobilityRouteOption? {
        visibleOptions.first { $0.mode == .transit }
    }

    private var visibleOptions: [MobilityRouteOption] {
        guard let plan else {
            return primaryOption.map { [$0] } ?? []
        }

        let orderedModes: [MobilityRouteMode] = [.transit, .taxi, .drive]
        return orderedModes.compactMap { mode in
            plan.options.first { option in
                option.mode == mode && (option.travelMinutes != nil || option.durationMinutes != nil)
            }
        }
    }

    private var routeTitle: String {
        "\(shortPlace(displayOrigin.isEmpty ? context.origin : displayOrigin)) -> \(shortPlace(displayDestination.isEmpty ? context.destination : displayDestination))"
    }

    private var primaryDetail: String {
        if let primaryOption {
            return conciseGuidance(for: primaryOption)
        }

        return String(localized: "Public transport is shown first, with taxi and car alternatives kept for comparison.")
    }

    private func conciseGuidance(for option: MobilityRouteOption) -> String {
        switch option.mode {
        case .taxi:
            return String(localized: "Book a taxi around \(departureTimeText(for: option) ?? "departure time"); open the map when you are ready.")
        case .drive:
            return String(localized: "Drive timing is enough here: leave \(departureTimeText(for: option) ?? "on time") and open the map when you go.")
        case .transit:
            return transitInstruction(for: option) ?? option.summary
        case .walk, .bike:
            return String(localized: "\(option.mode.displayName) · \(shortDuration(option)). Open the map for turn-by-turn details.")
        }
    }

    private func shortDuration(_ option: MobilityRouteOption) -> String {
        if let travelMinutes = option.travelMinutes {
            return String(localized: "\(travelMinutes) min")
        }
        if let durationMinutes = option.durationMinutes {
            return String(localized: "\(durationMinutes) min")
        }
        return String(localized: "Open route")
    }

    private func optionPreviewTile(_ option: MobilityRouteOption, isProminent: Bool) -> some View {
        Group {
            if isProminent {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 9) {
                        optionIcon(option, size: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.mode.displayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(phase.titleColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Text(routeTimeRangeText(for: option) ?? String(localized: "Open route"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(phase.secondaryColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer(minLength: 4)

                        Text(shortDuration(option))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.accent)
                            .lineLimit(1)
                    }

                    if let steps = transitSteps(for: option), !steps.isEmpty {
                        transitLegsView(steps)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        optionIcon(option, size: 22)

                        Text(option.mode.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(phase.titleColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Text(compactOptionDetail(option))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(phase.secondaryColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(isProminent ? 11 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isProminent ? phase.metricBackground : Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func optionIcon(_ option: MobilityRouteOption, size: CGFloat) -> some View {
        Image(systemName: option.mode.symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(phase.accent)
            .frame(width: size, height: size)
            .background(phase.metricBackground)
            .clipShape(Circle())
    }

    private func compactOptionDetail(_ option: MobilityRouteOption) -> String {
        if let timeText = routeTimeRangeText(for: option) {
            return "\(timeText) · \(shortDuration(option))"
        }
        return shortDuration(option)
    }

    private func departureTimeText(for option: MobilityRouteOption) -> String? {
        if let value = option.departureTime ?? option.leaveBy,
           let date = MobilityDateFormatter.date(from: value) {
            return MobilityDateFormatter.timeString(
                from: date,
                timeZoneIdentifier: option.departureTimeZone
            )
        }
        if let localized = option.steps?.compactMap(\.departureTimeText).first?.nilIfEmpty {
            return localized
        }
        return routeDepartureDate(for: option)
            .map { MobilityDateFormatter.time.string(from: $0) }
    }

    private func routeTimeRangeText(for option: MobilityRouteOption) -> String? {
        guard let departure = departureTimeText(for: option) else {
            return arrivalTimeText(for: option).map { String(localized: "Arrive \($0)") }
        }

        if let arrival = arrivalTimeText(for: option) {
            return "\(departure)-\(arrival)"
        }
        return String(localized: "Leave \(departure)")
    }

    private func arrivalTimeText(for option: MobilityRouteOption) -> String? {
        if let value = option.arrivalTime,
           let date = MobilityDateFormatter.date(from: value) {
            return MobilityDateFormatter.timeString(
                from: date,
                timeZoneIdentifier: option.arrivalTimeZone
            )
        }
        if let localized = option.steps?.compactMap(\.arrivalTimeText).last?.nilIfEmpty {
            return localized
        }
        return routeArrivalDate(for: option)
            .map { MobilityDateFormatter.time.string(from: $0) }
    }

    private func routeDepartureDate(for option: MobilityRouteOption) -> Date? {
        option.departureTime.flatMap(MobilityDateFormatter.date(from:))
            ?? option.leaveBy.flatMap(MobilityDateFormatter.date(from:))
            ?? (option.steps?.compactMap { $0.departureTime.flatMap(MobilityDateFormatter.date(from:)) } ?? []).min()
    }

    private func routeArrivalDate(for option: MobilityRouteOption) -> Date? {
        if let arrival = option.arrivalTime.flatMap(MobilityDateFormatter.date(from:)) {
            return arrival
        }

        if let stepArrival = (option.steps?.compactMap { $0.arrivalTime.flatMap(MobilityDateFormatter.date(from:)) } ?? []).max() {
            return stepArrival
        }

        if let departure = routeDepartureDate(for: option),
           let travelMinutes = option.travelMinutes {
            return departure.addingTimeInterval(TimeInterval(travelMinutes * 60))
        }

        return nil
    }

    private func transitSteps(for option: MobilityRouteOption) -> [MobilityRouteStep]? {
        guard let steps = option.steps else {
            return nil
        }

        let transitSteps = steps.filter { $0.kind == "transit" }
        let routeSteps = transitSteps.isEmpty ? steps.filter { $0.kind != "walk" } : transitSteps
        return routeSteps.isEmpty ? nil : routeSteps
    }

    private func transitLegsView(_ steps: [MobilityRouteStep]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(steps.prefix(3)) { step in
                transitLegRow(step)
            }
        }
        .padding(.top, 2)
    }

    private func transitLegRow(_ step: MobilityRouteStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(transitLegTitle(step))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(phase.titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    if let timeText = transitLegTimeText(step) {
                        Text(timeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(phase.accent)
                            .lineLimit(1)
                    }
                }

                if let detail = transitLegDetail(step) {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(phase.secondaryColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func transitLegTitle(_ step: MobilityRouteStep) -> String {
        step.lineName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? step.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "Public transport")
    }

    private func transitLegDetail(_ step: MobilityRouteStep) -> String? {
        if let departureStop = step.departureStop?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let arrivalStop = step.arrivalStop?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "\(departureStop) -> \(arrivalStop)"
        }

        return step.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func transitLegTimeText(_ step: MobilityRouteStep) -> String? {
        if let departure = step.departureTimeText?.nilIfEmpty,
           let arrival = step.arrivalTimeText?.nilIfEmpty {
            return "\(departure)-\(arrival)"
        }
        if let departure = step.departureTimeText?.nilIfEmpty { return departure }
        if let arrival = step.arrivalTimeText?.nilIfEmpty { return arrival }

        let departure = step.departureTime.flatMap(MobilityDateFormatter.date(from:))
        let arrival = step.arrivalTime.flatMap(MobilityDateFormatter.date(from:))

        if let departure, let arrival {
            return "\(MobilityDateFormatter.time.string(from: departure))-\(MobilityDateFormatter.time.string(from: arrival))"
        }
        if let departure {
            return MobilityDateFormatter.time.string(from: departure)
        }
        if let arrival {
            return MobilityDateFormatter.time.string(from: arrival)
        }
        return nil
    }

    private func transitInstruction(for option: MobilityRouteOption) -> String? {
        guard let step = option.steps?.first(where: { $0.kind == "transit" }) else {
            return nil
        }

        let line = step.lineName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? step.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "public transport")
        let departure = step.departureTimeText?.nilIfEmpty
            ?? step.departureTime.flatMap(MobilityDateFormatter.date(from:)).map { MobilityDateFormatter.time.string(from: $0) }
        let arrival = step.arrivalTimeText?.nilIfEmpty
            ?? step.arrivalTime.flatMap(MobilityDateFormatter.date(from:)).map { MobilityDateFormatter.time.string(from: $0) }
        let from = step.departureStop?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let to = step.arrivalStop?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if let departure, let arrival, let from, let to {
            return String(localized: "Take \(line) at \(departure) from \(from); arrive \(arrival) at \(to).")
        }
        if let departure, let from, let to {
            return String(localized: "Take \(line) at \(departure) from \(from); get off at \(to).")
        }
        if let departure, let arrival, let to {
            return String(localized: "Take \(line) at \(departure); arrive \(arrival) at \(to).")
        }
        if let departure, let to {
            return String(localized: "Take \(line) at \(departure); get off at \(to).")
        }
        if let to {
            return String(localized: "Take \(line); get off at \(to).")
        }
        return String(localized: "Take \(line).")
    }

    private func shortPlace(_ value: String) -> String {
        let parts = value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2,
           ["arrivals", "departures"].contains(parts[0].lowercased()) {
            return "\(parts[0]) \(parts[1])"
        }
        let shortened = parts.first ?? ""
        return shortened.isEmpty ? value : shortened
    }
}

enum TransferPhase: Equatable {
    case past
    case current
    case future
    case undated

    init(context: MobilityTransferContext, plan: MobilityPlan?, fallbackStart: Date? = nil, now: Date = Date()) {
        let option = plan?.defaultOption
        let plannedStart = option?.leaveBy.flatMap(MobilityDateFormatter.date(from:))
            ?? option?.departureTime.flatMap(MobilityDateFormatter.date(from:))
        let plannedEnd = option?.arrivalTime.flatMap(MobilityDateFormatter.date(from:))
        let earliestPossibleStart = context.targetDepartureAt ?? fallbackStart
        let latestRequiredArrival = context.targetArrivalAt
        let planStartsTooEarly = earliestPossibleStart.map { earliest in
            plannedStart.map { $0 < earliest } ?? false
        } ?? false
        let planEndsTooLate = latestRequiredArrival.map { latest in
            plannedEnd.map { $0 > latest } ?? false
        } ?? false
        let usePlannedTiming = !planStartsTooEarly && !planEndsTooLate

        let start = (usePlannedTiming ? plannedStart : nil)
            ?? context.targetDepartureAt
            ?? fallbackStart
        let end = (usePlannedTiming ? plannedEnd : nil)
            ?? context.targetArrivalAt
            ?? context.targetDepartureAt
            ?? fallbackStart

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

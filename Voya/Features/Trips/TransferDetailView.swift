import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct TransferDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let context: MobilityTransferContext
    let plan: MobilityPlan?
    let errorMessage: String?
    let isLoading: Bool
    let onRefresh: () -> Void
    let onUpdateBuffer: (Int) -> Void
    let onDelete: () -> Void
    @State private var displayOrigin = ""
    @State private var displayDestination = ""
    @State private var draftBufferMinutes: Int?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    routeMapCard
                    bufferControlCard

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
        .alert("Delete transfer?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the transfer recommendation from the timeline. You can restore hidden transfers from the trip timeline.")
        }
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
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.voyaCoral)
                        .frame(width: 42, height: 42)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)

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

    private var bufferControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Buffer", systemImage: "timer")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)

                Spacer()

                Text("\(effectiveBufferMinutes) min")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
            }

            Stepper(
                value: Binding(
                    get: { effectiveBufferMinutes },
                    set: { newValue in
                        let boundedValue = min(max(newValue, 0), 240)
                        draftBufferMinutes = boundedValue
                        onUpdateBuffer(boundedValue)
                    }
                ),
                in: 0...240,
                step: 5
            ) {
                Text("Extra time before arrival or departure")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
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
                    Text(optionSummary(option))
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                metric("Depart", departureTimeText(for: option) ?? "—")
                metric("Arrive", arrivalTimeText(for: option) ?? "—")
                metric("Travel", travelDurationText(option))
            }

            if option.mode == .transit, !option.tradeoffs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(option.tradeoffs.prefix(3), id: \.self) { tradeoff in
                        Label(tradeoff, systemImage: "checkmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if option.mode == .transit, let steps = publicTransitSteps(for: option), !steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps.prefix(3)) { step in
                        routeStepRow(step)
                    }
                }
                .padding(12)
                .background(Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                if let routeTime = routeTimeRangeText(for: option) {
                    Label(routeTime, systemImage: "clock")
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

    private func routeStepRow(_ step: MobilityRouteStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)

                    if let timeText = routeStepTimeText(step) {
                        Text(timeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.voyaTeal)
                            .lineLimit(1)
                    } else if let durationMinutes = step.durationMinutes {
                        Text("\(durationMinutes) min")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.voyaMuted)
                            .lineLimit(1)
                    }
                }

                if let detail = routeStepDetail(step) {
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func routeStepDetail(_ step: MobilityRouteStep) -> String? {
        if let departureStop = step.departureStop,
           let arrivalStop = step.arrivalStop {
            return "\(departureStop) → \(arrivalStop)"
        }

        return step.detail
    }

    private func publicTransitSteps(for option: MobilityRouteOption) -> [MobilityRouteStep]? {
        guard let steps = option.steps else {
            return nil
        }

        let transitSteps = steps.filter { $0.kind == "transit" }
        return transitSteps.isEmpty ? steps.filter { $0.kind != "walk" } : transitSteps
    }

    private func optionSummary(_ option: MobilityRouteOption) -> String {
        switch option.mode {
        case .taxi:
            return String(localized: "Taxi · \(travelDurationText(option)). Open the map when you are ready.")
        case .drive:
            return String(localized: "Own car · \(travelDurationText(option)). Keep leave time visible and use the map for navigation.")
        case .transit:
            return transitInstruction(for: option) ?? option.summary
        case .walk, .bike:
            return String(localized: "\(option.mode.displayName) · \(travelDurationText(option)).")
        }
    }

    private func transitInstruction(for option: MobilityRouteOption) -> String? {
        guard let step = option.steps?.first(where: { $0.kind == "transit" }) else {
            return nil
        }

        let line = step.lineName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? step.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "public transport")
        let departure = step.departureTime
            .flatMap(MobilityDateFormatter.date(from:))
            .map { MobilityDateFormatter.time.string(from: $0) }
        let arrival = step.arrivalTime
            .flatMap(MobilityDateFormatter.date(from:))
            .map { MobilityDateFormatter.time.string(from: $0) }
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

    private func routeStepTimeText(_ step: MobilityRouteStep) -> String? {
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

    private var effectiveBufferMinutes: Int {
        draftBufferMinutes ?? context.airportBufferMinutes
    }

    private var primaryDetail: String {
        if let option = primaryOption {
            return "\(option.mode.displayName) · \(travelDurationText(option))"
        }
        if let recommendation = plan?.recommendation,
           recommendation.mode == primaryOption?.mode {
            return recommendation.reason
        }
        return String(localized: "Public transport timing and alternatives")
    }

    private func departureTimeText(for option: MobilityRouteOption) -> String? {
        routeDepartureDate(for: option)
            .map { MobilityDateFormatter.time.string(from: $0) }
    }

    private func arrivalTimeText(for option: MobilityRouteOption) -> String? {
        routeArrivalDate(for: option)
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

    private func routeDepartureDate(for option: MobilityRouteOption) -> Date? {
        earliestStepDate(option.steps?.compactMap { $0.departureTime.flatMap(MobilityDateFormatter.date(from:)) } ?? [])
            ?? option.departureTime.flatMap(MobilityDateFormatter.date(from:))
            ?? option.leaveBy.flatMap(MobilityDateFormatter.date(from:))
    }

    private func routeArrivalDate(for option: MobilityRouteOption) -> Date? {
        if let stepArrival = latestStepDate(option.steps?.compactMap { $0.arrivalTime.flatMap(MobilityDateFormatter.date(from:)) } ?? []) {
            return stepArrival
        }

        if let departure = routeDepartureDate(for: option),
           let travelMinutes = option.travelMinutes {
            return departure.addingTimeInterval(TimeInterval(travelMinutes * 60))
        }

        return option.arrivalTime.flatMap(MobilityDateFormatter.date(from:))
    }

    private func earliestStepDate(_ dates: [Date]) -> Date? {
        dates.min()
    }

    private func latestStepDate(_ dates: [Date]) -> Date? {
        dates.max()
    }

    private func travelDurationText(_ option: MobilityRouteOption) -> String {
        if let travelMinutes = option.travelMinutes {
            return String(localized: "\(travelMinutes) min")
        }
        return shortDuration(option)
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

struct MissingStartPointCard: View {
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

struct MissingEndPointCard: View {
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

enum MobilityDateFormatter {
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

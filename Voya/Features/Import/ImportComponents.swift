import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct ImportPrimaryDropZone: View {
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.voyaTeal.opacity(0.18), lineWidth: 1)
        )
    }
}

struct ImportOption: View {
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ImportActionTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension CGImagePropertyOrientation {
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

struct ImportMessageLabel: View {
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

struct ImportPreparationStatusPanel: View {
    let status: ImportPreparationStatus
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .center, spacing: 12) {
                        ImportPreparationOrb(isActive: status.isActive && !status.hasFailure)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Preparing preview")
                                .font(.headline)
                                .foregroundStyle(Color.voyaInk)
                            Text(status.sourceName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.voyaMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 8)

                        Text("\(status.completedStepCount)/\(status.steps.count)")
                            .font(.caption.bold())
                            .foregroundStyle(status.hasFailure ? Color.voyaCoral : Color.voyaTeal)
                            .frame(width: 42, height: 30)
                            .background((status.hasFailure ? Color.voyaCoral : Color.voyaTeal).opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    ImportPreparationProgressBar(progress: status.progress, hasFailure: status.hasFailure)

                    VStack(spacing: 9) {
                        ForEach(status.steps) { step in
                            ImportPreparationStepRow(step: step)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 22, y: 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: status.hasFailure ? "exclamationmark.triangle.fill" : "wand.and.stars")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(status.hasFailure ? Color.voyaCoral : Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.summary)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                            .lineLimit(1)
                        Text(status.hasFailure ? "Needs attention" : "Tap for details")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.voyaMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.voyaMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.voyaSurface)
                        .clipShape(Circle())
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.82), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ImportPreparationStepRow: View {
    let step: ImportPreparationStep

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ImportPreparationStepIndicator(state: step.state)

            Image(systemName: step.id.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                    .lineLimit(1)
                Text(step.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(.easeInOut(duration: 0.24), value: step.state)
    }

    private var iconColor: Color {
        switch step.state {
        case .completed:
            Color.voyaTeal
        case .running:
            Color.voyaSky
        case .failed:
            Color.voyaCoral
        case .skipped:
            Color.voyaGold
        case .pending:
            Color.voyaMuted
        }
    }

    private var rowBackground: Color {
        switch step.state {
        case .running:
            Color.voyaSky.opacity(0.08)
        case .completed:
            Color.voyaTeal.opacity(0.08)
        case .failed:
            Color.voyaCoral.opacity(0.09)
        case .skipped:
            Color.voyaGold.opacity(0.08)
        case .pending:
            Color.voyaSurface
        }
    }
}

struct ImportPreparationStepIndicator: View {
    let state: ImportPreparationStepState

    var body: some View {
        switch state {
        case .running:
            TimelineView(.animation) { timeline in
                let rotation = timeline.date.timeIntervalSinceReferenceDate * 210
                Circle()
                    .trim(from: 0.12, to: 0.82)
                    .stroke(Color.voyaSky, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(rotation))
                    .frame(width: 20, height: 20)
            }
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.voyaTeal)
        case .skipped:
            Image(systemName: "minus.square.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.voyaGold)
        case .failed:
            Image(systemName: "exclamationmark.square.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.voyaCoral)
        case .pending:
            Image(systemName: "square")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.voyaMuted.opacity(0.62))
        }
    }
}

struct ImportPreparationProgressBar: View {
    let progress: Double
    let hasFailure: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.voyaSurface)

                Capsule()
                    .fill(hasFailure ? Color.voyaCoral : Color.voyaTeal)
                    .frame(width: max(8, geometry.size.width * progress))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: progress)
    }
}

struct ImportPreparationOrb: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let scale = isActive ? 1 + sin(phase * 4.5) * 0.08 : 1

            ZStack {
                Circle()
                    .fill(Color.voyaTeal.opacity(isActive ? 0.16 : 0.09))
                    .frame(width: 48, height: 48)
                    .scaleEffect(scale)

                Circle()
                    .stroke(Color.voyaTeal.opacity(0.24), lineWidth: 2)
                    .frame(width: 39, height: 39)

                Image(systemName: isActive ? "sparkles" : "checkmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(isActive ? Color.voyaTeal : Color.voyaInk)
                    .clipShape(Circle())
            }
        }
        .frame(width: 50, height: 50)
    }
}

struct RecognitionAnimationCard: View {
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

struct RecognitionTag: View {
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

struct ImportSuccessAnimationCard: View {
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

struct ExtractionReview: View {
    let preview: ExtractionPreview
    let isConfirming: Bool
    let statusMessage: String?
    let onOpenSource: (SourceDocumentFile) -> Void
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

            ImportRecognitionStatusCard(
                preview: preview,
                isConfirming: isConfirming,
                statusMessage: statusMessage,
                onOpenSource: onOpenSource
            )

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
                Label(isConfirming ? "Checking flights" : "Save to trip", systemImage: isConfirming ? "airplane.circle" : "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(preview.items.isEmpty || isConfirming ? Color.voyaMuted : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preview.items.isEmpty || isConfirming)
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct ImportRecognitionStatusCard: View {
    let preview: ExtractionPreview
    let isConfirming: Bool
    let statusMessage: String?
    let onOpenSource: (SourceDocumentFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isConfirming ? "waveform.path.ecg" : "doc.text.magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(isConfirming ? Color.voyaTeal : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isConfirming ? "Checking imported details" : "Filled from source")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(detailText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                SourceStepPill(title: "Source", symbol: "doc.text", isActive: true)
                SourceStepPill(title: "Recognition", symbol: "text.viewfinder", isActive: true)
                SourceStepPill(title: "Tracking", symbol: "antenna.radiowaves.left.and.right", isActive: isConfirming)
            }

            if let sourceFile = preview.sourceFile {
                Button {
                    onOpenSource(sourceFile)
                } label: {
                    Label("Open source", systemImage: "doc.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(Color.voyaInk)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.voyaTeal.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detailText: String {
        if let statusMessage, !statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return statusMessage
        }

        return String(localized: "Filled from source. Not enough details yet, checking tracking services.")
    }
}

struct SourceStepPill: View {
    let title: LocalizedStringKey
    let symbol: String
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(isActive ? Color.voyaInk : Color.voyaMuted)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(isActive ? .white : Color.voyaSurface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EditableItineraryItem: View {
    @State private var draft: ItineraryItemDraft
    @State private var isApplyingExternalItemUpdate = false
    let item: ItineraryItem
    let onChange: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        item: ItineraryItem,
        onChange: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        self.item = item
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
        .onChange(of: item.updatedAt) { _, _ in syncDraftFromItem() }
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
        guard !isApplyingExternalItemUpdate else {
            return
        }

        onChange(draft)
    }

    private func syncDraftFromItem() {
        let updatedDraft = ItineraryItemDraft(item: item)
        guard !draft.matches(updatedDraft) else {
            return
        }

        isApplyingExternalItemUpdate = true
        draft = updatedDraft
        DispatchQueue.main.async {
            isApplyingExternalItemUpdate = false
        }
    }
}

struct ClearableTextField: View {
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

struct ItineraryKindPicker: View {
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

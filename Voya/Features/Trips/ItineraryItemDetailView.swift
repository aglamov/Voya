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
    let item: ItineraryItem
    let sourceDocument: SourceDocument?
    let onSave: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        item: ItineraryItem,
        sourceDocument: SourceDocument? = nil,
        onSave: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
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
}

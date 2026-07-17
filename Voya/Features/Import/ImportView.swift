import SwiftUI
import SwiftData
import ImageIO
import PDFKit
@preconcurrency import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct ImportView: View {
    @EnvironmentObject private var store: VoyaStore
    @Binding var selectedTab: VoyaTab
    @State private var isFileImporterPresented = false
    @State private var isPasteImporterPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var sourcePreviewURL: URL?
    @State private var isPreparationStatusVisible = false
    @State private var isPreparationStatusExpanded = true
    @State private var preparationStatusDismissTask: Task<Void, Never>?

    private enum ScrollTarget {
        static let review = "import-review"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HeaderBar(title: "Import", subtitle: "Add confirmation")

                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Add confirmation")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.voyaInk)
                                    Text("Paste text, choose a file, or read a photo.")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.voyaMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 10)

                                Image(systemName: store.isExtractingConfirmation ? "wand.and.stars" : "tray.and.arrow.down.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Color.voyaInk)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            HStack(spacing: 10) {
                                Button {
                                    isFileImporterPresented = true
                                } label: {
                                    ImportActionTile(symbol: "doc.text.magnifyingglass", title: "File", subtitle: "PDF or text", tint: .voyaTeal)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    isPasteImporterPresented = true
                                } label: {
                                    ImportActionTile(symbol: "text.alignleft", title: "Paste", subtitle: "Booking text", tint: .voyaGold)
                                }
                                .buttonStyle(.plain)

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    ImportActionTile(symbol: "photo.on.rectangle", title: "Photo", subtitle: "OCR image", tint: .voyaCoral)
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

                        if let importSuccess = store.importSuccess {
                            ImportSuccessAnimationCard(success: importSuccess, actionTitle: "Import") {
                                selectedTab = .trips
                            } onAction: {
                                store.prepareForNextImport()
                                isFileImporterPresented = true
                            }
                        }

                        if let preview = store.extractedPreview {
                            ExtractionReview(
                                preview: preview,
                                isConfirming: store.isConfirmingExtraction,
                                statusMessage: store.importMessage,
                                trips: store.trips,
                                suggestedTripID: store.suggestedImportTripID(for: preview.items),
                                destination: Binding(
                                    get: { store.importTripDestination },
                                    set: { store.selectImportTripDestination($0) }
                                ),
                                onOpenSource: openSourceDocument
                            ) { item, draft in
                                store.updatePreviewItem(item, with: draft)
                            } onAddItem: {
                                store.addPreviewItem()
                            } onDeleteItem: { item in
                                store.deletePreviewItem(item)
                            } onConfirm: {
                                store.confirmExtraction()
                            }
                            .id(ScrollTarget.review)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                }
                .onChange(of: store.extractedPreview?.id) { _, previewID in
                    guard previewID != nil else { return }
                    scroll(to: ScrollTarget.review, with: proxy)
                }
            }

            if let status = store.importPreparationStatus, isPreparationStatusVisible {
                GeometryReader { geometry in
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            ImportPreparationStatusPanel(status: status, isExpanded: $isPreparationStatusExpanded)
                                .frame(width: min(332, max(240, geometry.size.width - 36)))
                                .padding(.trailing, 18)
                                .padding(.bottom, 14)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .zIndex(5)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.importPreparationStatus)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isPreparationStatusVisible)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            handlePhotoImport(item)
        }
        .onChange(of: store.importPreparationStatus) { _, status in
            handlePreparationStatusChange(status)
        }
        .sheet(isPresented: $isPasteImporterPresented) {
            PasteConfirmationView()
                .environmentObject(store)
        }
        .quickLookPreview($sourcePreviewURL)
        .onDisappear {
            preparationStatusDismissTask?.cancel()
        }
    }

    private func scroll(to target: String, with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func handlePreparationStatusChange(_ status: ImportPreparationStatus?) {
        preparationStatusDismissTask?.cancel()

        guard let status else {
            isPreparationStatusVisible = false
            isPreparationStatusExpanded = true
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isPreparationStatusVisible = true
            if status.isActive || status.hasFailure {
                isPreparationStatusExpanded = true
            }
        }

        guard !status.isActive, !status.hasFailure else {
            return
        }

        let statusID = status.id
        preparationStatusDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            guard store.importPreparationStatus?.id == statusID else { return }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                isPreparationStatusExpanded = false
            }

            try? await Task.sleep(nanoseconds: 650_000_000)
            guard store.importPreparationStatus?.id == statusID else { return }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.90)) {
                isPreparationStatusVisible = false
            }

            try? await Task.sleep(nanoseconds: 450_000_000)
            guard store.importPreparationStatus?.id == statusID else { return }
            store.importPreparationStatus = nil
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
        store.beginImportPreparation(sourceName: sourceName, sourceDetail: String(localized: "Reading file"))
        let sourceData = try? Data(contentsOf: url)
        let sourceFile = sourceData.map {
            SourceDocumentFile(
                fileName: sourceName,
                contentType: UTType(filenameExtension: url.pathExtension)?.identifier ?? "application/octet-stream",
                data: $0
            )
        }
        if url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
            guard let text = readPDFText(from: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                store.failImportPreparation(with: ImportErrorMessage.unreadableFile(sourceName).message)
                return
            }
            store.extract(text: text, sourceName: sourceName, sourceFile: sourceFile)
            return
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            store.extract(text: text, sourceName: sourceName, sourceFile: sourceFile)
        } catch {
            store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
            store.failImportPreparation(with: ImportErrorMessage.unreadableFile(sourceName).message)
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task { @MainActor in
            let sourceName = String(localized: "Photo confirmation")
            store.beginImportPreparation(sourceName: sourceName, sourceDetail: String(localized: "Reading photo"))
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let cgImage = image.cgImage else {
                    store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                    store.failImportPreparation(with: ImportErrorMessage.unreadableFile(sourceName).message)
                    selectedPhotoItem = nil
                    return
                }

                store.updateImportPreparationStep(
                    .source,
                    state: .running,
                    detail: String(localized: "Running on-device OCR")
                )
                let text = try recognizeText(in: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                    store.failImportPreparation(with: ImportErrorMessage.unreadableFile(sourceName).message)
                    selectedPhotoItem = nil
                    return
                }

                let sourceFile = SourceDocumentFile(fileName: "Photo confirmation.jpg", contentType: UTType.jpeg.identifier, data: data)
                store.extract(text: text, sourceName: sourceName, sourceFile: sourceFile)
                selectedPhotoItem = nil
            } catch {
                store.importMessage = ImportErrorMessage.unreadableFile(sourceName).message
                store.failImportPreparation(with: ImportErrorMessage.unreadableFile(sourceName).message)
                selectedPhotoItem = nil
            }
        }
    }

    private func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedLines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])
        return recognizedLines.joined(separator: "\n")
    }

    private func readPDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private func openSourceDocument(_ sourceFile: SourceDocumentFile) {
        sourcePreviewURL = SourceDocumentPreviewer.temporaryURL(for: sourceFile)
    }
}

struct PasteConfirmationView: View {
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

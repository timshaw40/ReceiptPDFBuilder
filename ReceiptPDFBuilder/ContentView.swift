import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sourcePDFURL: URL?
    @State private var receiptURLs: [URL] = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var lastOutputURL: URL?
    @State private var isGenerating = false
    @State private var isPDFDropTargeted = false
    @State private var isReceiptDropTargeted = false

    private let receiptExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "pdf"]

    private var canGenerate: Bool {
        sourcePDFURL != nil && !receiptURLs.isEmpty && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receipt PDF Builder")
                        .font(.title2.bold())
                    Text("Combine an existing PDF with black & white receipt images and PDFs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            sourceSection
            photosSection

            Spacer(minLength: 4)

            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 640)
    }

    // MARK: - Source PDF

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1.  Existing PDF")
                .font(.headline)

            if let url = sourcePDFURL {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Replace…") { choosePDF() }
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                DropZone(title: "Drop PDF here",
                         subtitle: "or use the button below",
                         isTargeted: isPDFDropTargeted)
                    .dropDestination(for: URL.self, action: { urls, _ in
                        guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else {
                            return false
                        }
                        acceptSourcePDF(pdf)
                        return true
                    }, isTargeted: { isPDFDropTargeted = $0 })
                Button("Choose PDF…") { choosePDF() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor)))
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("2.  Receipt files")
                    .font(.headline)
                if !receiptURLs.isEmpty {
                    Text("(\(receiptURLs.count))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            DropZone(title: "Drop JPG / HEIC / PNG photos or PDFs here",
                     subtitle: "Receipt photos and PDF pages are converted to black & white",
                     isTargeted: isReceiptDropTargeted)
                .dropDestination(for: URL.self, action: { urls, _ in
                    let accepted = acceptedReceiptURLs(urls)
                    guard !accepted.isEmpty else { return false }
                    addReceipts(accepted)
                    return true
                }, isTargeted: { isReceiptDropTargeted = $0 })

            if !receiptURLs.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(receiptURLs.enumerated()), id: \.element) { index, url in
                            ReceiptRow(url: url) {
                                receiptURLs.remove(at: index)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            HStack {
                Button("Add Receipts…") { chooseReceipts() }
                    .buttonStyle(.bordered)
                Button("Paste Photo") { pastePhoto() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("v", modifiers: .command)
                    .help("Paste a receipt image from the clipboard (e.g. a screenshot)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor)))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Create Receipt PDF") {
                    generate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Converting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let url = lastOutputURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                }
            }

            if let message = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved: \(message)")
                        .font(.caption)
                }
            } else if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "Choose the PDF to extend"
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            acceptSourcePDF(url)
        }
    }

    /// Validates the PDF before adopting it so a broken file surfaces an error
    /// immediately instead of failing later at generate time.
    private func acceptSourcePDF(_ url: URL) {
        guard PDFDocument(url: url) != nil else {
            clearResults()
            errorMessage = "Could not read the PDF \"\(url.lastPathComponent)\"."
            return
        }
        clearResults()
        sourcePDFURL = url
    }

    private func chooseReceipts() {
        let panel = NSOpenPanel()
        panel.title = "Choose receipt photos or PDFs"
        panel.allowedContentTypes = [.jpeg, .heic, .heif, .png, .pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            addReceipts(panel.urls)
        }
    }

    /// Adds the clipboard image (screenshot, copied photo) as a PNG receipt.
    private func pastePhoto() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            errorMessage = "No image on the clipboard. Copy or screenshot a receipt first."
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptPDFBuilder-pasted-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
        } catch {
            errorMessage = "Could not save the pasted image: \(error.localizedDescription)"
            return
        }
        addReceipts([url])
    }

    private func addReceipts(_ urls: [URL]) {
        let accepted = acceptedReceiptURLs(urls)
        guard !accepted.isEmpty else { return }
        for url in accepted where !receiptURLs.contains(url) {
            receiptURLs.append(url)
        }
        clearResults()
    }

    private func acceptedReceiptURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return false
            }
            return receiptExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private func clearResults() {
        statusMessage = nil
        errorMessage = nil
        lastOutputURL = nil
    }

    private func generate() {
        guard let source = sourcePDFURL, !receiptURLs.isEmpty else { return }
        isGenerating = true
        clearResults()
        let urls = receiptURLs

        Task.detached(priority: .userInitiated) {
            do {
                let outputURL = try PDFBuilder.buildPDF(sourceURL: source, photoURLs: urls)
                await MainActor.run {
                    statusMessage = outputURL.lastPathComponent
                    lastOutputURL = outputURL
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    }

// MARK: - Support views

struct DropZone: View {
    let title: String
    let subtitle: String
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text(title)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

struct ReceiptRow: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let thumbnail = ThumbnailLoader.load(url) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.3)))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                    .frame(width: 34, height: 34)
            }
            Text(url.lastPathComponent)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this receipt")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

enum ThumbnailLoader {
    static func load(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: NSSize(width: 96, height: 96), for: .mediaBox)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

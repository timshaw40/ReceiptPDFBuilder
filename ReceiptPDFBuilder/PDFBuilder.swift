import AppKit
import CoreGraphics
import Foundation
import PDFKit

enum PDFBuilderError: LocalizedError {
    case pdfLoadFailed(String)
    case imageDecodeFailed(String)
    case grayscaleFailed(String)
    case pdfGenerationFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed(let name):
            return "Could not open the PDF \"\(name)\"."
        case .imageDecodeFailed(let name):
            return "Could not read the image \"\(name)\"."
        case .grayscaleFailed(let message):
            return "Could not convert an image to black & white: \(message)"
        case .pdfGenerationFailed:
            return "Could not build the output PDF."
        case .writeFailed(let message):
            return "Could not save the PDF: \(message)"
        }
    }
}

enum PDFBuilder {

    /// US Letter page size in points (612 x 792).
    static let pageSize = CGSize(width: 612, height: 792)
    /// 0.5 inch margin around each receipt page.
    static let pageMargin: CGFloat = 36

    /// Appends one black & white PDF page per photo to a copy of the source PDF
    /// and writes the combined PDF next to the source as
    /// "<source>-receipts-<timestamp>.pdf".
    ///
    /// - Returns: The URL the combined PDF was written to.
    static func buildPDF(sourceURL: URL, photoURLs: [URL], date: Date = Date()) throws -> URL {
        var doc: PDFDocument?
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            doc = PDFDocument(url: sourceURL)
            if doc == nil {
                throw PDFBuilderError.pdfLoadFailed(sourceURL.lastPathComponent)
            }
        }
        if doc == nil {
            doc = PDFDocument()
        }
        guard let document = doc else {
            throw PDFBuilderError.pdfLoadFailed(sourceURL.lastPathComponent)
        }

        guard !photoURLs.isEmpty else {
            throw PDFBuilderError.pdfGenerationFailed
        }

        // Render each receipt image into its own PDF page via a Core Graphics
        // PDF context, then splice those pages onto the source document.
        let mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        let output = NSMutableData()
        var box = mediaBox
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw PDFBuilderError.pdfGenerationFailed
        }

        for url in photoURLs {
            let image = try ImageProcessor.decodeImage(at: url)
            let grayscale = try ImageProcessor.grayscale(image)

            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)
            context.interpolationQuality = .high

            let drawRect = mediaBox.insetBy(dx: pageMargin, dy: pageMargin)
            let imageSize = CGSize(width: grayscale.width, height: grayscale.height)
            context.draw(grayscale, in: aspectFitRect(imageSize: imageSize, in: drawRect))
            context.endPDFPage()
        }
        context.closePDF()

        guard let receiptDocument = PDFDocument(data: output as Data) else {
            throw PDFBuilderError.pdfGenerationFailed
        }

        for index in 0..<receiptDocument.pageCount {
            guard let page = receiptDocument.page(at: index) else { continue }
            document.insert(page, at: document.pageCount)
        }

        let stamp = timestampString(for: date)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let outputFolder = sourceURL.deletingLastPathComponent()
        var outputURL = outputFolder.appendingPathComponent("\(baseName)-receipts-\(stamp).pdf")
        var uniqueSuffix = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = outputFolder.appendingPathComponent("\(baseName)-receipts-\(stamp)-\(uniqueSuffix).pdf")
            uniqueSuffix += 1
        }

        let data: Data
        do {
            guard let representation = document.dataRepresentation() else {
                throw PDFBuilderError.writeFailed("no data produced")
            }
            data = representation
        } catch {
            throw PDFBuilderError.writeFailed(error.localizedDescription)
        }
        do {
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw PDFBuilderError.writeFailed(error.localizedDescription)
        }
        return outputURL
    }

    /// Scales an image to fit `container` while preserving aspect ratio.
    static func aspectFitRect(imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: container.midX, y: container.midY, width: 0, height: 0)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: container.midX - size.width / 2,
                      y: container.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    static func timestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
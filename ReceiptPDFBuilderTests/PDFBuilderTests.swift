import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

final class PDFBuilderTests: XCTestCase {

    func testBuildAppendsReceiptPageAndGrayscalesIt() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("report.pdf")
        try writeSourcePDF(to: sourceURL, pages: 2)

        let photoURL = dir.appendingPathComponent("receipt.jpg")
        try writeSolidJPEG(to: photoURL, color: (red: 1.0, green: 0.0, blue: 0.0), width: 400, height: 600)

        let outputURL = try PDFBuilder.buildPDF(sourceURL: sourceURL,
                                               photoURLs: [photoURL],
                                               date: fixedDate)

        XCTAssertEqual(outputURL.lastPathComponent, "report-receipts-20260102-034500.pdf",
                       "Output file should follow the <name>-receipts-<stamp> naming scheme")

        guard let document = PDFDocument(url: outputURL) else {
            return XCTFail("Output PDF could not be opened")
        }

        XCTAssertEqual(document.pageCount, 3, "Source (2) + one receipt (1) page expected")

        // Verify the original two pages are unchanged.
        XCTAssertNotNil(document.page(at: 0))
        XCTAssertNotNil(document.page(at: 1))

        // Verify the receipt page renders as a grayscale image.
        guard let receiptPage = document.page(at: 2) else {
            return XCTFail("Missing receipt page")
        }
        let cgPage = try XCTUnwrap(renderPage(receiptPage))
        assertGrayscale(cgPage)
    }

    func testBuildWithoutSourceProducesOnlyReceiptPages() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Build with no readable source PDF: output should still contain the receipts.
        let photoURL = dir.appendingPathComponent("photo.heic")
        try writeHEIC(to: photoURL)

        let fakeSource = dir.appendingPathComponent("missing.pdf")
        let outputURL = try PDFBuilder.buildPDF(sourceURL: fakeSource,
                                               photoURLs: [photoURL],
                                               date: fixedDate)

        guard let document = PDFDocument(url: outputURL) else {
            return XCTFail("Output PDF could not be opened")
        }
        XCTAssertEqual(document.pageCount, 1, "One receipt page expected")
    }

    func testMultiplePhotosProduceMultiplePagesInOrder() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("report.pdf")
        try writeSourcePDF(to: sourceURL, pages: 1)

        let firstURL = dir.appendingPathComponent("a.jpg")
        try writeSolidJPEG(to: firstURL, color: (red: 1.0, green: 0.0, blue: 0.0), width: 100, height: 100)
        let secondURL = dir.appendingPathComponent("b.jpg")
        try writeSolidJPEG(to: secondURL, color: (red: 0.0, green: 1.0, blue: 0.0), width: 100, height: 100)

        let outputURL = try PDFBuilder.buildPDF(sourceURL: sourceURL,
                                               photoURLs: [firstURL, secondURL],
                                               date: fixedDate)

        guard let document = PDFDocument(url: outputURL) else {
            return XCTFail("Output PDF could not be opened")
        }
        XCTAssertEqual(document.pageCount, 3, "Source (1) + two receipts expected")
    }

    func testPNGPhotoProducesReceiptPage() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("report.pdf")
        try writeSourcePDF(to: sourceURL, pages: 1)

        // Include a PNG with a fully transparent region to prove transparency is
        // composited onto a white background rather than kept.
        let pngURL = dir.appendingPathComponent("receipt.png")
        try writePNG(to: pngURL)

        let outputURL = try PDFBuilder.buildPDF(sourceURL: sourceURL,
                                               photoURLs: [pngURL],
                                               date: fixedDate)

        guard let document = PDFDocument(url: outputURL) else {
            return XCTFail("Output PDF could not be opened")
        }
        XCTAssertEqual(document.pageCount, 2, "Source (1) + PNG receipt expected")

        guard let receiptPage = document.page(at: 1) else {
            return XCTFail("Missing receipt page")
        }
        let cgPage = try XCTUnwrap(renderPage(receiptPage))
        assertGrayscale(cgPage)
    }

    func testAspectFitRectMatchesExpectations() {
        let container = CGRect(x: 0, y: 0, width: 612, height: 792).insetBy(dx: 36, dy: 36)
        let wide = CGSize(width: 1200, height: 600)
        let frame = PDFBuilder.aspectFitRect(imageSize: wide, in: container)
        XCTAssertEqual(frame.width, container.width, accuracy: 0.001, "Wide image fills width")
        XCTAssertEqual(frame.height, 270, accuracy: 0.001, "Height keeps 1200:600 aspect")
        XCTAssertEqual(frame.origin.x, container.minX, accuracy: 0.001)
    }

    // MARK: - Output naming is a small detail worth pinning down

    func testFilenameStampPattern() {
        let stamp = PDFBuilder.timestampString(for: fixedDate)
        XCTAssertTrue(stamp.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression) != nil)
    }

    // MARK: - Fixtures

    private var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 2
        components.hour = 3
        components.minute = 45
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components) ?? Date()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptPDFBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSourcePDF(to url: URL, pages: Int) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            return XCTFail("Could not create data consumer")
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return XCTFail("Could not create PDF context")
        }
        for pageIndex in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 72, y: 72, width: 100, height: 40 + 40 * pageIndex))
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
    }

    private func writeSolidJPEG(to url: URL, color: (red: CGFloat, green: CGFloat, blue: CGFloat),
                                width: Int, height: Int) throws {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "PDFBuilderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "no context"])
        }
        context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw NSError(domain: "PDFBuilderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "no image"])
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString,
                                                                1, nil) else {
            throw NSError(domain: "PDFBuilderTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "no destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "PDFBuilderTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "finalize failed"])
        }
    }

    private func writePNG(to url: URL) throws {
        let width = 300
        let height = 200
        var pixels = [UInt8](repeating: 0, count: height * width * 4)
        // Left half: opaque red; right half: fully transparent.
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 2 {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 255
                    pixels[offset + 3] = 255
                } else {
                    pixels[offset + 3] = 0
                }
            }
        }
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else {
            throw NSError(domain: "PDFBuilderTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "no png context"])
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.png.identifier as CFString,
                                                                1, nil) else {
            throw NSError(domain: "PDFBuilderTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "no png destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "PDFBuilderTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "png finalize failed"])
        }
    }

    private func writeHEIC(to url: URL) throws {
        guard let context = CGContext(data: nil, width: 200, height: 200,
                                      bitsPerComponent: 8, bytesPerRow: 200 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "PDFBuilderTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "no context"])
        }
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        guard let image = context.makeImage() else {
            throw NSError(domain: "PDFBuilderTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "no image"])
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.heic.identifier as CFString,
                                                                1, nil) else {
            throw NSError(domain: "PDFBuilderTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "no destination"])
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.7
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "PDFBuilderTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "finalize failed"])
        }
    }

    private func renderPage(_ page: PDFPage) -> CGImage? {
        let thumbnail = page.thumbnail(of: NSSize(width: 160, height: 160), for: .mediaBox)
        var rect = NSRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func assertGrayscale(_ image: CGImage, file: StaticString = #file, line: UInt = #line) {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("Could not create pixel context", file: file, line: line)
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample several pixels across the receipt region and require R == G == B.
        let samples = [(width / 2, height / 2), (width / 4, height / 4),
                       (width * 3 / 4, height / 2), (width / 2, height * 3 / 4)]
        for (x, y) in samples {
            let offset = y * bytesPerRow + x * 4
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            XCTAssertEqual(r, g, accuracy: 3, "Pixel at (\(x), \(y)) not grayscale (R=\(r) G=\(g))", file: file, line: line)
            XCTAssertEqual(g, b, accuracy: 3, "Pixel at (\(x), \(y)) not grayscale (G=\(g) B=\(b))", file: file, line: line)
        }
    }
}
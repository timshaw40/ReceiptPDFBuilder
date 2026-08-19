import CoreImage
import CoreGraphics
import ImageIO
import Foundation

enum ImageProcessor {

    /// Decodes an image file (JPG, HEIC, PNG, ...) into a CGImage.
    ///
    /// Decodes through a thumbnail pipeline capped at `maxPixelSize` so large
    /// phone photos stay fast while remaining sharp enough for a printed page
    /// (~300 dpi). EXIF orientation is applied.
    static func decodeImage(at url: URL, maxPixelSize: Int = 3000) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PDFBuilderError.imageDecodeFailed(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PDFBuilderError.imageDecodeFailed(url.lastPathComponent)
        }
        return cgImage
    }

    /// Renders an image as black & white (photo-effect mono) composited over a
    /// white background so the result is opaque and print-friendly.
    static func grayscale(_ image: CGImage) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else {
            throw PDFBuilderError.grayscaleFailed("filter unavailable")
        }
        filter.setDefaults()
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let mono = filter.outputImage else {
            throw PDFBuilderError.grayscaleFailed("filter produced no output")
        }

        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: mono.extent)
        let composited = mono.composited(over: white)

        // NSNull working color space keeps conversion simple and predictable.
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let output = context.createCGImage(composited, from: composited.extent) else {
            throw PDFBuilderError.grayscaleFailed("could not render output")
        }
        return output
    }
}
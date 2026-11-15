import Foundation
import CoreGraphics

enum CaptureGeometry {
    /// The centered pixel crop shown by a resizeAspectFill preview of the oriented frame.
    static func cropRect(source: CGRect, viewport: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              viewport.width.isFinite, viewport.height.isFinite else { return source }
        let ratio = viewport.width / viewport.height
        let width = min(source.width, source.height * ratio)
        let height = min(source.height, source.width / ratio)
        // Keep pixel boundaries inside the original frame, with at most one pixel of rounding.
        let pixelWidth = max(1, floor(width))
        let pixelHeight = max(1, floor(height))
        return CGRect(x: source.minX + floor((source.width - pixelWidth) / 2),
                      y: source.minY + floor((source.height - pixelHeight) / 2),
                      width: pixelWidth, height: pixelHeight).intersection(source)
    }
}

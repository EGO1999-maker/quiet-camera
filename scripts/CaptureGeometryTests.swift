import Foundation
import CoreGraphics

@main
enum CaptureGeometryTests {
    static func main() {
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 9, height: 16)) == portrait)
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 1, height: 1)) == CGRect(x: 0, y: 420, width: 1080, height: 1080))
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 430, height: 932)) == CGRect(x: 97, y: 0, width: 885, height: 1920))
        let landscape = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Both landscape orientations deliver the same dimensions; test the
        // wider phone viewport and its portrait counterpart for matching crops.
        for phone in [CGSize(width: 667, height: 375), CGSize(width: 932, height: 430), CGSize(width: 956, height: 440)] {
            let horizontal = CaptureGeometry.cropRect(source: landscape, viewport: phone)
            let vertical = CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: phone.height, height: phone.width))
            assert(landscape.contains(horizontal))
            assert(horizontal.width == vertical.height && horizontal.height == vertical.width)
            assert(abs(horizontal.midX - landscape.midX) <= 0.5 && abs(horizontal.midY - landscape.midY) <= 0.5)
        }
        assert(CaptureGeometry.cropRect(source: landscape, viewport: CGSize(width: 4, height: 3)) == CGRect(x: 240, y: 0, width: 1440, height: 1080))
        let shifted = CGRect(x: 100, y: 200, width: 1080, height: 1920)
        assert(CaptureGeometry.cropRect(source: shifted, viewport: CGSize(width: 1, height: 1)) == CGRect(x: 100, y: 620, width: 1080, height: 1080))
        assert(CaptureGeometry.cropRect(source: portrait, viewport: .zero) == portrait)
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: CGFloat.nan, height: 1)) == portrait)
        for size in [CGSize(width: 375, height: 667), CGSize(width: 430, height: 932), CGSize(width: 440, height: 956)] {
            let result = CaptureGeometry.cropRect(source: portrait, viewport: size)
            assert(portrait.contains(result))
            assert(abs(result.midX - portrait.midX) <= 0.5 && abs(result.midY - portrait.midY) <= 0.5)
            assert(abs(result.width / result.height - size.width / size.height) < 0.001)
        }
        print("Capture geometry checks passed: portrait, landscape, square, phone ratios, centered bounds and invalid input.")
    }
}

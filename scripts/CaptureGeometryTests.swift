import Foundation

@main
enum CaptureGeometryTests {
    static func main() {
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 9, height: 16)) == portrait)
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 1, height: 1)) == CGRect(x: 0, y: 420, width: 1080, height: 1080))
        assert(CaptureGeometry.cropRect(source: portrait, viewport: CGSize(width: 430, height: 932)) == CGRect(x: 97, y: 0, width: 885, height: 1920))
        let landscape = CGRect(x: 0, y: 0, width: 1920, height: 1080)
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

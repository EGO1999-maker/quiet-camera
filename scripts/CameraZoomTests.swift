import Foundation

@main
struct CameraZoomTests {
    static func main() {
        let ultraWide = CameraZoom(wideSwitchFactor: 2, minimum: 1, maximum: 40)
        assert(ultraWide.minimum == 0.5 && ultraWide.maximum == 8)
        assert(ultraWide.nativeFactor(for: 0.5) == 1)
        assert(ultraWide.nativeFactor(for: 1) == 2)
        assert(ultraWide.nativeFactor(for: 0.1) == 1)
        assert(ultraWide.nativeFactor(for: 99) == 16)
        for display in [0.5, 0.75, 1, 2, 5, 8] {
            assert(ultraWide.displayFactor(for: ultraWide.nativeFactor(for: display)) == display)
        }
        // Front/single wide lens cannot pretend to provide an ultra-wide field of view.
        let single = CameraZoom(wideSwitchFactor: nil, minimum: 1, maximum: 6)
        assert(single.minimum == 1 && single.maximum == 6)
        assert(single.nativeFactor(for: 0.5) == 1 && single.nativeFactor(for: 1) == 1)
        let constrained = CameraZoom(wideSwitchFactor: 2, minimum: 2, maximum: 10)
        assert(constrained.minimum == 1 && constrained.maximum == 5)
        assert(constrained.nativeFactor(for: 0.5) == 2)
        let invalid = CameraZoom(wideSwitchFactor: .nan, minimum: 1, maximum: 8)
        assert(invalid.nativeFactor(for: 1) == 1)
        print("Camera zoom checks passed: ultra-wide, 1x mapping, device limits, single-lens fallback and round trips.")
    }
}

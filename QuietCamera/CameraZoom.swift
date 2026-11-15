import Foundation

/// UI zoom is relative to the wide lens. AVFoundation zoom is relative to
/// the widest constituent lens and must never be set below its native limit.
struct CameraZoom {
    let nativePerOneX: Double
    let nativeMinimum: Double
    let nativeMaximum: Double

    init(wideSwitchFactor: Double?, minimum: Double, maximum: Double) {
        let factor = wideSwitchFactor ?? 1
        nativePerOneX = factor.isFinite && factor >= 1 ? factor : 1
        nativeMinimum = minimum
        nativeMaximum = max(minimum, min(maximum, 8 * nativePerOneX))
    }

    var minimum: Double { nativeMinimum / nativePerOneX }
    var maximum: Double { nativeMaximum / nativePerOneX }

    func nativeFactor(for display: Double) -> Double {
        min(max(display * nativePerOneX, nativeMinimum), nativeMaximum)
    }

    func displayFactor(for native: Double) -> Double { native / nativePerOneX }
}

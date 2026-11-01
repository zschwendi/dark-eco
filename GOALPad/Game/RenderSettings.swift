import Foundation

nonisolated struct RenderSettingsConfiguration: Equatable, Sendable {
    let defaultsKey: String
    let defaultScale: Int

    static let jak1 = RenderSettingsConfiguration(
        defaultsKey: "internalResolutionScale",
        defaultScale: 2)
    static let jak2 = RenderSettingsConfiguration(
        defaultsKey: "jak2InternalResolutionScale",
        defaultScale: 4)
}

/// The game's internal render resolution.
///
/// The PS2 games draw into a 640x480 target and the video hardware scans that out; OpenGOAL's
/// renderers keep that structure, drawing the game into an offscreen target and then presenting it
/// into a letterboxed region of the window. The internal target is therefore a free choice, and on
/// a Retina iPad 640x480 is far below the panel.
///
/// The scale is a whole multiple of 640x480 so the game keeps its 4:3 aspect and its HUD keeps its
/// proportions. The default is 2x - clearly better than the PS2, well inside what an M-series iPad
/// should manage, and conservative until the fused renderer can actually be measured on hardware.
@MainActor
@Observable
final class RenderSettings {
    static let baseWidth = 640
    static let baseHeight = 480
    static let availableScales = [1, 2, 3, 4]

    private let configuration: RenderSettingsConfiguration
    private let defaults: UserDefaults

    var horizontalPlusEnabled = false {
        didSet { apply() }
    }

    var internalResolutionScale: Int {
        didSet {
            let clamped = min(max(internalResolutionScale, 1), Self.availableScales.count)
            if clamped != internalResolutionScale {
                internalResolutionScale = clamped
                return
            }
            defaults.set(clamped, forKey: configuration.defaultsKey)
            apply()
        }
    }

    var internalWidth: Int { Self.baseWidth * internalResolutionScale }
    var internalHeight: Int { Self.baseHeight * internalResolutionScale }

    /// Immersive per-eye render height level. It is stored separately from the windowed scale so
    /// the headset can render sharper eyes without changing the window. Levels 1...4 keep their
    /// stored 480-line multiples; level 5 is 2160 lines per eye.
    static let immersiveDefaultsKey = "immersiveResolutionScale"
    static let immersiveAvailableScales = [1, 2, 3, 4, 5]
    static let immersiveEyeHeights = [480, 960, 1440, 1920, 2160]
    static let immersiveDefaultScale = 5

    static func immersiveEyeHeight(for scale: Int) -> Int {
        let index = min(max(scale, 1), immersiveEyeHeights.count) - 1
        return immersiveEyeHeights[index]
    }

    var immersiveResolutionScale: Int {
        didSet {
            let clamped = min(max(immersiveResolutionScale, 1), Self.immersiveAvailableScales.count)
            if clamped != immersiveResolutionScale {
                immersiveResolutionScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.immersiveDefaultsKey)
        }
    }

    var immersiveEyeHeight: Int { Self.immersiveEyeHeight(for: immersiveResolutionScale) }

    init(configuration: RenderSettingsConfiguration, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.defaults = defaults
        let stored = defaults.integer(forKey: configuration.defaultsKey)
        internalResolutionScale = Self.availableScales.contains(stored)
            ? stored : configuration.defaultScale
        let storedImmersive = defaults.integer(forKey: Self.immersiveDefaultsKey)
        immersiveResolutionScale = Self.immersiveAvailableScales.contains(storedImmersive)
            ? storedImmersive : Self.immersiveDefaultScale
        apply()
    }

    /// Per-eye target size for a chosen height, widened to the widest eye's aspect so neither
    /// eye's projection is cropped. Returns nil for a nonpositive height, an empty, nonfinite or
    /// nonpositive aspect, or a width that does not fit in a 32-bit texture dimension.
    nonisolated static func immersiveEyeDimensions(height: Int,
                                                   aspects: [Float]) -> (width: Int, height: Int)? {
        guard height > 0, height <= Int(Int32.max), !aspects.isEmpty,
              aspects.allSatisfy({ $0.isFinite && $0 > 0 }),
              let aspect = aspects.max() else { return nil }
        let width = (Double(height) * Double(aspect)).rounded(.up)
        guard width.isFinite, width >= 1, width <= Double(Int32.max) else { return nil }
        return (Int(width), height)
    }

    convenience init() {
        self.init(configuration: .jak1)
    }

    func apply() {
        let surface = GOALPadRenderSurface.shared
        surface.setInternalResolutionScale(Int32(internalResolutionScale))
        surface.setHorizontalPlusEnabled(horizontalPlusEnabled)
    }

    func restoreDefaults() {
        internalResolutionScale = configuration.defaultScale
    }

    func label(for scale: Int) -> String {
        "\(Self.baseWidth * scale)x\(Self.baseHeight * scale)"
    }

    func immersiveLabel(for scale: Int) -> String {
        "\(Self.immersiveEyeHeight(for: scale))p per eye"
    }
}

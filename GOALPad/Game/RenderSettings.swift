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

    init(configuration: RenderSettingsConfiguration, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.defaults = defaults
        let stored = defaults.integer(forKey: configuration.defaultsKey)
        internalResolutionScale = Self.availableScales.contains(stored)
            ? stored : configuration.defaultScale
        apply()
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
}

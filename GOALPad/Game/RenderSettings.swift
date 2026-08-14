import Foundation

/// The game's internal render resolution.
///
/// The PS2 drew Jak 1 into a 640x480 target and the video hardware scanned that out; OpenGOAL's
/// renderers keep that structure, drawing the game into an offscreen target and then presenting it
/// into a letterboxed region of the window. The internal target is therefore a free choice, and on
/// a Retina iPad 640x480 is far below the panel.
///
/// The scale is a whole multiple of 640x480 so the game keeps its 4:3 aspect and its HUD keeps its
/// proportions. The shared app defaults to 2x. Eco Jak II Dev uses 4x after physical 2x
/// validation.
@MainActor
@Observable
final class RenderSettings {
    static let baseWidth = 640
    static let baseHeight = 480
    static let availableScales = [1, 2, 3, 4]

    private static let defaultsKey = "internalResolutionScale"
    private static var configuredDefaultScale: Int? {
        Bundle.main.bundleIdentifier == "com.zephyrstudiosllc.eco.jak2dev" ? 4 : nil
    }

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
            UserDefaults.standard.set(clamped, forKey: Self.defaultsKey)
            apply()
        }
    }

    var internalWidth: Int { Self.baseWidth * internalResolutionScale }
    var internalHeight: Int { Self.baseHeight * internalResolutionScale }

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: Self.defaultsKey)
        if let configured = Self.configuredDefaultScale {
            let migrationKey = "\(Self.defaultsKey).target-default-\(configured)"
            if !defaults.bool(forKey: migrationKey) {
                internalResolutionScale = stored == 0 || stored == 2 ? configured : stored
                defaults.set(internalResolutionScale, forKey: Self.defaultsKey)
                defaults.set(true, forKey: migrationKey)
            } else {
                internalResolutionScale = Self.availableScales.contains(stored) ? stored : configured
            }
        } else {
            internalResolutionScale = Self.availableScales.contains(stored) ? stored : 2
        }
        apply()
    }

    func apply() {
        let surface = GOALPadRenderSurface.shared
        surface.setInternalResolutionScale(Int32(internalResolutionScale))
        surface.setHorizontalPlusEnabled(horizontalPlusEnabled)
    }

    func label(for scale: Int) -> String {
        "\(Self.baseWidth * scale)x\(Self.baseHeight * scale)"
    }
}

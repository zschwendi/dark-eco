import Foundation
import CoreGraphics

nonisolated struct TouchSafeAreaInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = TouchSafeAreaInsets()
}

nonisolated enum TouchLayoutProfile: String, CaseIterable, Codable, Sendable {
    case modern
    case classic

    var title: String { rawValue.capitalized }
}

nonisolated enum TouchLayoutAction: String, CaseIterable, Codable, Hashable, Sendable {
    case movementStick
    case cameraStick
    case cross
    case square
    case circle
    case crouch
    case triangle
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case select
    case stats
    case start
    case leftShoulder
    case rightShoulder

    var title: String {
        switch self {
        case .movementStick: "Movement Stick"
        case .cameraStick: "Camera Stick"
        case .cross: "Jump (Cross)"
        case .square: "Attack (Square)"
        case .circle: "Spin (Circle)"
        case .crouch: "Crouch"
        case .triangle: "Triangle"
        case .dpadUp: "D-Pad Up"
        case .dpadDown: "D-Pad Down"
        case .dpadLeft: "D-Pad Left"
        case .dpadRight: "D-Pad Right"
        case .select: "Select / Skip"
        case .stats: "Stats"
        case .start: "Pause / Resume"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        }
    }

    var shortLabel: String {
        switch self {
        case .movementStick: "L"
        case .cameraStick: "R"
        case .cross: "✕"
        case .square: "□"
        case .circle: "○"
        case .crouch: "↓"
        case .triangle: "△"
        case .dpadUp: "↑"
        case .dpadDown: "↓"
        case .dpadLeft: "←"
        case .dpadRight: "→"
        case .select: "SELECT"
        case .stats: "STATS"
        case .start: "START"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        }
    }
}

nonisolated enum TouchGestureDirection: String, CaseIterable, Codable, Sendable {
    case up
    case left
    case right
    case down

    var title: String { rawValue.capitalized }

    static let remappableCases: [Self] = [.up, .left, .right]
}

nonisolated struct TouchGestureActionMapping: Codable, Equatable, Sendable {
    static let standard = Self(up: .cross, left: .square, right: .circle, down: .crouch)

    static let remappableActions: [TouchLayoutAction] = [.cross, .square, .circle]
    private static let remappableActionSet = Set(remappableActions)

    var up: TouchLayoutAction
    var left: TouchLayoutAction
    var right: TouchLayoutAction
    private(set) var down: TouchLayoutAction

    init(up: TouchLayoutAction, left: TouchLayoutAction,
         right: TouchLayoutAction, down: TouchLayoutAction) {
        let faceActions = [up, left, right]
        if down == .crouch,
           faceActions.allSatisfy(Self.remappableActionSet.contains),
           Set(faceActions).count == TouchGestureDirection.remappableCases.count {
            self.up = up
            self.left = left
            self.right = right
            self.down = down
        } else {
            self.up = .cross
            self.left = .square
            self.right = .circle
            self.down = .crouch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case up
        case left
        case right
        case down
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                up: try container.decode(TouchLayoutAction.self, forKey: .up),
                left: try container.decode(TouchLayoutAction.self, forKey: .left),
                right: try container.decode(TouchLayoutAction.self, forKey: .right),
                down: try container.decode(TouchLayoutAction.self, forKey: .down))
        } catch {
            self = .standard
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(up, forKey: .up)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        try container.encode(down, forKey: .down)
    }

    func action(for direction: TouchGestureDirection) -> TouchLayoutAction {
        switch direction {
        case .up: up
        case .left: left
        case .right: right
        case .down: down
        }
    }

    mutating func setAction(_ action: TouchLayoutAction,
                            for direction: TouchGestureDirection) {
        guard TouchGestureDirection.remappableCases.contains(direction),
              Self.remappableActionSet.contains(action) else { return }
        let oldAction = self.action(for: direction)
        guard oldAction != action else { return }
        if let occupied = TouchGestureDirection.remappableCases.first(where: {
            $0 != direction && self.action(for: $0) == action
        }) {
            setDirect(oldAction, for: occupied)
        }
        setDirect(action, for: direction)
    }

    var isValid: Bool {
        let actions = TouchGestureDirection.remappableCases.map(action(for:))
        return down == .crouch
            && actions.allSatisfy(Self.remappableActionSet.contains)
            && Set(actions).count == TouchGestureDirection.remappableCases.count
    }

    private mutating func setDirect(_ action: TouchLayoutAction,
                                    for direction: TouchGestureDirection) {
        switch direction {
        case .up: up = action
        case .left: left = action
        case .right: right = action
        case .down: break
        }
    }
}

nonisolated enum TouchLayoutControlID: String, CaseIterable, Codable, Hashable, Sendable,
                                         Identifiable {
    case modernMovement
    case modernCamera
    case modernActions
    case modernSelect
    case modernStats
    case modernStart

    case classicMovement
    case classicCamera
    case classicDpadUp
    case classicDpadDown
    case classicDpadLeft
    case classicDpadRight
    case classicSelect
    case classicStats
    case classicStart
    case classicLeftShoulder
    case classicRightShoulder
    case classicTriangle
    case classicSquare
    case classicCircle
    case classicCross

    var id: String { rawValue }

    var profile: TouchLayoutProfile {
        rawValue.hasPrefix("modern") ? .modern : .classic
    }

    var title: String {
        switch self {
        case .modernMovement, .classicMovement: "Movement Stick"
        case .modernCamera, .classicCamera: "Camera Stick"
        case .modernActions: "Action Gestures"
        case .modernSelect, .classicSelect: "Select / Skip"
        case .modernStats, .classicStats: "Stats"
        case .modernStart, .classicStart: "Pause / Resume"
        case .classicDpadUp: "D-Pad Up"
        case .classicDpadDown: "D-Pad Down"
        case .classicDpadLeft: "D-Pad Left"
        case .classicDpadRight: "D-Pad Right"
        case .classicLeftShoulder: "L1"
        case .classicRightShoulder: "R1"
        case .classicTriangle: "Triangle"
        case .classicSquare: "Square"
        case .classicCircle: "Circle"
        case .classicCross: "Cross"
        }
    }

    var defaultAction: TouchLayoutAction? {
        switch self {
        case .modernMovement, .classicMovement: .movementStick
        case .modernCamera, .classicCamera: .cameraStick
        case .modernActions: nil
        case .modernSelect, .classicSelect: .select
        case .modernStats, .classicStats: .stats
        case .modernStart, .classicStart: .start
        case .classicDpadUp: .dpadUp
        case .classicDpadDown: .dpadDown
        case .classicDpadLeft: .dpadLeft
        case .classicDpadRight: .dpadRight
        case .classicLeftShoulder: .leftShoulder
        case .classicRightShoulder: .rightShoulder
        case .classicTriangle: .triangle
        case .classicSquare: .square
        case .classicCircle: .circle
        case .classicCross: .cross
        }
    }

    var compatibleActions: [TouchLayoutAction] {
        switch self {
        case .modernMovement, .modernCamera, .classicMovement, .classicCamera:
            [.movementStick, .cameraStick]
        case .modernActions:
            []
        case .modernSelect, .modernStats, .modernStart,
             .classicSelect, .classicStats, .classicStart:
            [.select, .stats, .start]
        case .classicDpadUp, .classicDpadDown, .classicDpadLeft, .classicDpadRight:
            [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]
        case .classicLeftShoulder, .classicRightShoulder:
            [.leftShoulder, .rightShoulder]
        case .classicTriangle, .classicSquare, .classicCircle, .classicCross:
            [.triangle, .square, .circle, .cross]
        }
    }

    static func controls(for profile: TouchLayoutProfile) -> [Self] {
        allCases.filter { $0.profile == profile }
    }

    static func visualOrder(for profile: TouchLayoutProfile) -> [Self] {
        switch profile {
        case .modern:
            [
                .modernMovement, .modernActions,
                .modernSelect, .modernStats, .modernStart,
                .modernCamera,
            ]
        case .classic:
            [
                .classicMovement, .classicCamera,
                .classicDpadUp, .classicDpadDown, .classicDpadLeft, .classicDpadRight,
                .classicSelect, .classicStats, .classicStart,
                .classicLeftShoulder, .classicRightShoulder,
                .classicTriangle, .classicSquare, .classicCircle, .classicCross,
            ]
        }
    }

    static func hitTestOrder(for profile: TouchLayoutProfile) -> [Self] {
        Array(visualOrder(for: profile).reversed())
    }
}

nonisolated struct NormalizedTouchPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(1, max(0, x.isFinite ? x : 0.5))
        self.y = min(1, max(0, y.isFinite ? y : 0.5))
    }
}

nonisolated struct TouchControlCustomization: Codable, Equatable, Sendable, Identifiable {
    let id: TouchLayoutControlID
    var position: NormalizedTouchPosition?
    var action: TouchLayoutAction?
    var gestureActions: TouchGestureActionMapping?
    var opacityPercent: Int?
    var sizePercent: Int?

    init(id: TouchLayoutControlID,
         position: NormalizedTouchPosition? = nil,
         action: TouchLayoutAction? = nil,
         gestureActions: TouchGestureActionMapping? = nil,
         opacityPercent: Int? = nil,
         sizePercent: Int? = nil) {
        self.id = id
        self.position = position
        self.action = action
        self.gestureActions = gestureActions
        self.opacityPercent = opacityPercent
        self.sizePercent = sizePercent
        canonicalize()
    }

    var isDefault: Bool {
        position == nil && action == nil && gestureActions == nil
            && opacityPercent == nil && sizePercent == nil
    }

    mutating func canonicalize() {
        if let position {
            self.position = NormalizedTouchPosition(x: position.x, y: position.y)
        }
        if let action, !id.compatibleActions.contains(action) || action == id.defaultAction {
            self.action = nil
        }
        if id == .modernActions {
            if gestureActions?.isValid != true || gestureActions == .standard {
                gestureActions = nil
            }
        } else {
            gestureActions = nil
        }
        if let opacityPercent {
            let bounded = min(100, max(25, opacityPercent))
            self.opacityPercent = bounded == 100 ? nil : bounded
        }
        if let sizePercent {
            let bounded = min(160, max(65, sizePercent))
            self.sizePercent = bounded == 100 ? nil : bounded
        }
    }
}

nonisolated struct TouchLayoutCustomization: Codable, Equatable, Sendable {
    static let standard = Self()

    private(set) var controls: [TouchControlCustomization]

    init(controls: [TouchControlCustomization] = []) {
        var unique: [TouchLayoutControlID: TouchControlCustomization] = [:]
        for var control in controls {
            control.canonicalize()
            if !control.isDefault { unique[control.id] = control }
        }
        for profile in TouchLayoutProfile.allCases {
            let profileControls = TouchLayoutControlID.controls(for: profile)
            var visitedSets = Set<[TouchLayoutAction]>()
            for control in profileControls where !control.compatibleActions.isEmpty {
                let actionSet = control.compatibleActions.sorted { $0.rawValue < $1.rawValue }
                guard visitedSets.insert(actionSet).inserted else { continue }
                let group = profileControls.filter { $0.compatibleActions == control.compatibleActions }
                let actions = group.compactMap { id in
                    unique[id]?.action ?? id.defaultAction
                }
                guard actions.count == group.count, Set(actions).count != group.count else {
                    continue
                }
                for id in group where unique[id] != nil {
                    unique[id]?.action = nil
                    unique[id]?.canonicalize()
                    if unique[id]?.isDefault == true { unique[id] = nil }
                }
            }
        }
        self.controls = TouchLayoutControlID.allCases.compactMap { unique[$0] }
    }

    private enum CodingKeys: String, CodingKey {
        case controls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(controls: try container.decodeIfPresent(
            [TouchControlCustomization].self, forKey: .controls) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controls, forKey: .controls)
    }

    var isDefault: Bool { controls.isEmpty }

    func customization(for id: TouchLayoutControlID) -> TouchControlCustomization? {
        controls.first { $0.id == id }
    }

    func position(for id: TouchLayoutControlID) -> NormalizedTouchPosition? {
        customization(for: id)?.position
    }

    func action(for id: TouchLayoutControlID) -> TouchLayoutAction? {
        guard let defaultAction = id.defaultAction else { return nil }
        let candidate = customization(for: id)?.action ?? defaultAction
        return id.compatibleActions.contains(candidate) ? candidate : defaultAction
    }

    func gestureAction(for direction: TouchGestureDirection) -> TouchLayoutAction {
        let mapping = customization(for: .modernActions)?.gestureActions ?? .standard
        return mapping.isValid ? mapping.action(for: direction) : TouchGestureActionMapping.standard
            .action(for: direction)
    }

    func opacity(for id: TouchLayoutControlID) -> Double {
        Double(customization(for: id)?.opacityPercent ?? 100) / 100
    }

    func scale(for id: TouchLayoutControlID) -> CGFloat {
        CGFloat(customization(for: id)?.sizePercent ?? 100) / 100
    }

    func hasCustomGeometry(for id: TouchLayoutControlID) -> Bool {
        let value = customization(for: id)
        return value?.position != nil || value?.sizePercent != nil
    }

    mutating func setPosition(_ position: NormalizedTouchPosition?,
                              for id: TouchLayoutControlID) {
        update(id) { $0.position = position }
    }

    mutating func setOpacityPercent(_ percent: Int, for id: TouchLayoutControlID) {
        update(id) { $0.opacityPercent = percent }
    }

    mutating func setSizePercent(_ percent: Int, for id: TouchLayoutControlID) {
        update(id) { $0.sizePercent = percent }
    }

    mutating func setAction(_ action: TouchLayoutAction,
                            for id: TouchLayoutControlID) {
        guard id.defaultAction != nil, id.compatibleActions.contains(action) else { return }
        let currentAction = self.action(for: id)
        guard currentAction != action else { return }
        if let occupied = TouchLayoutControlID.controls(for: id.profile).first(where: {
            $0 != id && $0.compatibleActions == id.compatibleActions
                && self.action(for: $0) == action
        }) {
            update(occupied) { $0.action = currentAction }
        }
        update(id) { $0.action = action }
    }

    mutating func setGestureAction(_ action: TouchLayoutAction,
                                   for direction: TouchGestureDirection) {
        guard TouchGestureDirection.remappableCases.contains(direction),
              TouchGestureActionMapping.remappableActions.contains(action) else { return }
        var mapping = customization(for: .modernActions)?.gestureActions ?? .standard
        mapping.setAction(action, for: direction)
        update(.modernActions) { $0.gestureActions = mapping }
    }

    mutating func reset(_ id: TouchLayoutControlID) {
        if let defaultAction = id.defaultAction,
           let currentAction = action(for: id), currentAction != defaultAction,
           let occupied = TouchLayoutControlID.controls(for: id.profile).first(where: {
               $0 != id && $0.compatibleActions == id.compatibleActions
                   && action(for: $0) == defaultAction
           }) {
            update(occupied) { $0.action = currentAction }
        }
        controls.removeAll { $0.id == id }
    }

    mutating func resetAll() {
        controls.removeAll()
    }

    private mutating func update(_ id: TouchLayoutControlID,
                                 _ body: (inout TouchControlCustomization) -> Void) {
        var value = customization(for: id) ?? TouchControlCustomization(id: id)
        body(&value)
        value.canonicalize()
        controls.removeAll { $0.id == id }
        if !value.isDefault { controls.append(value) }
        controls.sort {
            let lhs = TouchLayoutControlID.allCases.firstIndex(of: $0.id) ?? 0
            let rhs = TouchLayoutControlID.allCases.firstIndex(of: $1.id) ?? 0
            return lhs < rhs
        }
    }
}

nonisolated enum TouchLayoutGeometry {
    static let minimumHitDimension: CGFloat = 44

    static func safeBounds(in size: CGSize,
                           insets: TouchSafeAreaInsets,
                           padding: CGFloat = 0) -> CGRect {
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let leading = min(max(0, insets.leading), bounds.width)
        let trailing = min(max(0, insets.trailing), bounds.width - leading)
        let top = min(max(0, insets.top), bounds.height)
        let bottom = min(max(0, insets.bottom), bounds.height - top)
        let safe = CGRect(x: leading, y: top,
                          width: bounds.width - leading - trailing,
                          height: bounds.height - top - bottom)
        let inset = min(max(0, padding), min(safe.width, safe.height) / 2)
        return safe.insetBy(dx: inset, dy: inset)
    }

    static func visualFrame(default defaultFrame: CGRect,
                            control id: TouchLayoutControlID,
                            customization: TouchLayoutCustomization,
                            safeBounds: CGRect) -> CGRect {
        let scale = customization.scale(for: id)
        let requestedSize = CGSize(width: max(0, defaultFrame.width * scale),
                                   height: max(0, defaultFrame.height * scale))
        let fittedSize = CGSize(width: min(safeBounds.width, requestedSize.width),
                                height: min(safeBounds.height, requestedSize.height))
        let requestedCentre: CGPoint
        if let position = customization.position(for: id) {
            requestedCentre = CGPoint(x: safeBounds.minX + CGFloat(position.x) * safeBounds.width,
                                      y: safeBounds.minY + CGFloat(position.y) * safeBounds.height)
        } else {
            requestedCentre = CGPoint(x: defaultFrame.midX, y: defaultFrame.midY)
        }
        let centre = clampedCentre(requestedCentre, size: fittedSize, in: safeBounds)
        return CGRect(x: centre.x - fittedSize.width / 2,
                      y: centre.y - fittedSize.height / 2,
                      width: fittedSize.width, height: fittedSize.height)
    }

    static func minimumHitFrame(for visualFrame: CGRect, in safeBounds: CGRect) -> CGRect {
        let size = CGSize(width: min(safeBounds.width,
                                    max(minimumHitDimension, visualFrame.width)),
                          height: min(safeBounds.height,
                                      max(minimumHitDimension, visualFrame.height)))
        let centre = clampedCentre(CGPoint(x: visualFrame.midX, y: visualFrame.midY),
                                   size: size, in: safeBounds)
        return CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func normalizedPosition(for requestedCentre: CGPoint,
                                   visualSize: CGSize,
                                   in safeBounds: CGRect) -> NormalizedTouchPosition {
        let fitted = CGSize(width: min(safeBounds.width, max(0, visualSize.width)),
                            height: min(safeBounds.height, max(0, visualSize.height)))
        let centre = clampedCentre(requestedCentre, size: fitted, in: safeBounds)
        let x = safeBounds.width > 0 ? Double((centre.x - safeBounds.minX) / safeBounds.width) : 0.5
        let y = safeBounds.height > 0 ? Double((centre.y - safeBounds.minY) / safeBounds.height) : 0.5
        return NormalizedTouchPosition(x: x, y: y)
    }

    private static func clampedCentre(_ centre: CGPoint,
                                      size: CGSize,
                                      in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(bounds.minX + size.width / 2, centre.x),
                   bounds.maxX - size.width / 2),
            y: min(max(bounds.minY + size.height / 2, centre.y),
                   bounds.maxY - size.height / 2)
        )
    }
}

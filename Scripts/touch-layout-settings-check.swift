import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

private func isInside(_ frame: CGRect, _ bounds: CGRect, tolerance: CGFloat = 0.001) -> Bool {
    frame.minX >= bounds.minX - tolerance && frame.maxX <= bounds.maxX + tolerance
        && frame.minY >= bounds.minY - tolerance && frame.maxY <= bounds.maxY + tolerance
}

private func controlInventoryIsActiveAndTypeSafe() {
    print("touch layout inventory contains only active Modern and Classic controls")
    let modern = TouchLayoutControlID.controls(for: .modern)
    let classic = TouchLayoutControlID.controls(for: .classic)
    check(modern.count == 6 && Set(modern).count == modern.count,
          "Modern exposes movement, camera, gestures, and three active pills exactly once")
    check(classic.count == 15 && Set(classic).count == classic.count,
          "Classic exposes two sticks and its thirteen active direct controls exactly once")
    check(!TouchLayoutControlID.allCases.contains {
        $0.rawValue.localizedCaseInsensitiveContains("l2")
            || $0.rawValue.localizedCaseInsensitiveContains("r2")
    }, "inactive Classic L2 and R2 controls are not representable")
    check(!TouchLayoutAction.allCases.contains {
        $0.rawValue.localizedCaseInsensitiveContains("l2")
            || $0.rawValue.localizedCaseInsensitiveContains("r2")
    }, "inactive Classic trigger actions cannot be assigned")

    let modernVisualOrder = TouchLayoutControlID.visualOrder(for: .modern)
    let classicVisualOrder = TouchLayoutControlID.visualOrder(for: .classic)
    check(modernVisualOrder == [
        .modernMovement, .modernActions,
        .modernSelect, .modernStats, .modernStart, .modernCamera,
    ], "Modern visual order places camera last and topmost")
    check(classicVisualOrder == [
        .classicMovement, .classicCamera,
        .classicDpadUp, .classicDpadDown, .classicDpadLeft, .classicDpadRight,
        .classicSelect, .classicStats, .classicStart,
        .classicLeftShoulder, .classicRightShoulder,
        .classicTriangle, .classicSquare, .classicCircle, .classicCross,
    ], "Classic visual order matches the gameplay Z stack")
    check(Set(modernVisualOrder) == Set(modern)
          && Set(classicVisualOrder) == Set(classic)
          && TouchLayoutControlID.hitTestOrder(for: .modern)
            == Array(modernVisualOrder.reversed())
          && TouchLayoutControlID.hitTestOrder(for: .classic)
            == Array(classicVisualOrder.reversed()),
          "both profiles hit-test every visible control in reverse visual order")

    for control in TouchLayoutControlID.allCases where control != .modernActions {
        check(control.defaultAction.map(control.compatibleActions.contains) == true,
              "\(control.title) has a compatible typed default action")
    }
}

private func remappingSwapsOnlyWithinCompatibleSets() {
    print("remapping swaps ownership within a compatible action set")
    var layout = TouchLayoutCustomization.standard
    layout.setAction(.cameraStick, for: .modernMovement)
    check(layout.action(for: .modernMovement) == .cameraStick
          && layout.action(for: .modernCamera) == .movementStick,
          "Modern whole-stick output remapping swaps movement and camera")
    layout.setAction(.triangle, for: .classicCross)
    check(layout.action(for: .classicCross) == .triangle
          && layout.action(for: .classicTriangle) == .cross,
          "Classic face remapping keeps each safe action uniquely owned")
    let before = layout
    layout.setAction(.stats, for: .classicCross)
    check(layout == before, "an incompatible system action cannot enter a face control")

    layout.reset(.classicCross)
    check(layout.action(for: .classicCross) == .cross
          && layout.action(for: .classicTriangle) == .triangle,
          "an individual reset safely restores both sides of an action swap")

    layout.setGestureAction(.square, for: .up)
    check(layout.gestureAction(for: .up) == .square
          && layout.gestureAction(for: .left) == .cross,
          "gesture remapping swaps the two safe face actions")
    let gestureActions = Set(TouchGestureDirection.allCases.map(layout.gestureAction(for:)))
    check(gestureActions == Set([.cross, .square, .circle, .crouch]),
          "the action rose retains all four established outputs exactly once")
    let remapped = layout
    layout.setGestureAction(.circle, for: .down)
    layout.setGestureAction(.crouch, for: .up)
    check(layout == remapped && layout.gestureAction(for: .down) == .crouch,
          "Down stays fixed to Crouch and Crouch cannot enter another direction")
    check(TouchGestureDirection.remappableCases == [.up, .left, .right]
          && TouchGestureActionMapping.remappableActions == [.cross, .square, .circle],
          "only the three established face swipes are representable as remappable")
    check(TouchGestureActionMapping(up: .square, left: .cross,
                                    right: .circle, down: .cross) == .standard,
          "the mapping model itself fails closed when constructed with movable Crouch")
}

private func defaultsAreOmittedAndDecodingIsBounded() throws {
    print("customization encoding omits safe defaults and bounds decoded values")
    check(TouchStickSize.allCases == [.small, .medium, .large]
          && TouchStickSize.small.ringDiameter == 76
          && TouchStickSize.medium.ringDiameter == 120
          && TouchStickSize.large.ringDiameter == 180,
          "the three stick choices preserve camera, current, and original ring sizes")
    var layout = TouchLayoutCustomization.standard
    layout.setOpacityPercent(100, for: .modernCamera)
    layout.setStickSize(.small, for: .modernCamera)
    layout.setAction(.cameraStick, for: .modernCamera)
    check(layout.isDefault && layout.controls.isEmpty,
          "default opacity, size, and action do not create an override")

    layout.setPosition(NormalizedTouchPosition(x: 0.2, y: 0.8), for: .modernCamera)
    layout.setOpacityPercent(5, for: .modernCamera)
    layout.setStickSize(.large, for: .modernCamera)
    let encoded = try JSONEncoder().encode(layout)
    let decoded = try JSONDecoder().decode(TouchLayoutCustomization.self, from: encoded)
    check(decoded.position(for: .modernCamera) == NormalizedTouchPosition(x: 0.2, y: 0.8),
          "normalized coordinates survive deterministic JSON round-trip")
    check(decoded.opacity(for: .modernCamera) == 0.25
          && decoded.stickSize(for: .modernCamera) == .large,
          "opacity is bounded and the discrete large stick survives decoding")
    check(!String(decoding: encoded, as: UTF8.self).contains("action"),
          "an unchanged action remains absent from persisted customization")

    let malformed = Data(
        #"{"controls":[{"id":"modernMovement","action":"cameraStick"}]}"#.utf8)
    let safe = try JSONDecoder().decode(TouchLayoutCustomization.self, from: malformed)
    check(safe.action(for: .modernMovement) == .movementStick
          && safe.action(for: .modernCamera) == .cameraStick,
          "a partial duplicate-output document fails back to the safe stick defaults")

    let malformedGesture = Data(
        #"{"controls":[{"id":"modernActions","gestureActions":{"up":"square","left":"cross","right":"circle","down":"cross"}}]}"#.utf8)
    let safeGesture = try JSONDecoder().decode(TouchLayoutCustomization.self,
                                                from: malformedGesture)
    check(safeGesture.isDefault
          && TouchGestureDirection.allCases.map(safeGesture.gestureAction(for:))
            == [.cross, .square, .circle, .crouch],
          "a decoded mapping that moves Crouch away from Down fails closed to the standard rose")
}

private func dragAndRotationStayInsideSafeBounds() {
    print("drag normalization clamps controls across safe areas and rotation")
    let portraitSize = CGSize(width: 393, height: 852)
    let portraitInsets = TouchSafeAreaInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    let portraitSafe = TouchLayoutGeometry.safeBounds(in: portraitSize, insets: portraitInsets,
                                                      padding: 12)
    let visualSize = CGSize(width: 118, height: 118)
    let position = TouchLayoutGeometry.normalizedPosition(
        for: CGPoint(x: -500, y: 2_000), visualSize: visualSize, in: portraitSafe)
    check(position.x >= 0 && position.x <= 1 && position.y >= 0 && position.y <= 1,
          "an out-of-range drag stores bounded normalized coordinates")

    var layout = TouchLayoutCustomization.standard
    layout.setPosition(position, for: .modernCamera)
    layout.setSizePercent(160, for: .modernCamera)
    let defaultPortrait = CGRect(x: 280, y: 650, width: 76, height: 76)
    let portraitFrame = TouchLayoutGeometry.visualFrame(
        default: defaultPortrait, control: .modernCamera,
        customization: layout, safeBounds: portraitSafe)
    let portraitHit = TouchLayoutGeometry.minimumHitFrame(for: portraitFrame, in: portraitSafe)
    check(isInside(portraitFrame, portraitSafe) && isInside(portraitHit, portraitSafe),
          "the dragged and enlarged control stays in the portrait safe area")
    check(portraitHit.width >= 44 && portraitHit.height >= 44,
          "the portrait hit target remains at least 44 by 44 points")

    let landscapeSize = CGSize(width: 852, height: 393)
    let landscapeInsets = TouchSafeAreaInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
    let landscapeSafe = TouchLayoutGeometry.safeBounds(in: landscapeSize,
                                                       insets: landscapeInsets, padding: 12)
    let defaultLandscape = CGRect(x: 700, y: 280, width: 76, height: 76)
    let landscapeFrame = TouchLayoutGeometry.visualFrame(
        default: defaultLandscape, control: .modernCamera,
        customization: layout, safeBounds: landscapeSafe)
    let landscapeHit = TouchLayoutGeometry.minimumHitFrame(for: landscapeFrame,
                                                           in: landscapeSafe)
    check(isInside(landscapeFrame, landscapeSafe) && isInside(landscapeHit, landscapeSafe),
          "the same normalized position remains on-screen after rotation")
    check(landscapeHit.width >= 44 && landscapeHit.height >= 44,
          "the rotated hit target remains at least 44 by 44 points")
}

@main
private struct TouchLayoutSettingsCheck {
    static func main() {
        do {
            controlInventoryIsActiveAndTypeSafe()
            remappingSwapsOnlyWithinCompatibleSets()
            try defaultsAreOmittedAndDecodingIsBounded()
            dragAndRotationStayInsideSafeBounds()
        } catch {
            print("  FAIL unexpected error: \(error)")
            failures += 1
        }

        print(failures == 0 ? "touch layout settings checks passed"
              : "touch layout settings checks failed: \(failures)")
        Foundation.exit(failures == 0 ? 0 : 1)
    }
}

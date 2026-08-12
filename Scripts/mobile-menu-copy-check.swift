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

private func source(at path: String) -> String {
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  FAIL could not read \(path)")
        Foundation.exit(1)
    }
    return value
}

private func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start),
          let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[lower.lowerBound..<upper.lowerBound])
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift Scripts/mobile-menu-copy-check.swift <repository-root>")
    Foundation.exit(2)
}

let root = CommandLine.arguments[1]
let progress = source(at: root + "/OpenGOAL/goal_src/jak1/pc/progress-pc.gc")
let mobileTitle = section(progress,
                          from: "(define *title-managed-display*",
                          to: "(define *speedrun-options*")
let menuRouting = section(progress,
                          from: "(defun init-game-options",
                          to: "(defmethod respond-common")

check(["new-game", "load-game", "options", "quit-game", "back"].allSatisfy {
    mobileTitle.contains("(text-id \($0))")
}, "the managed-display title menu keeps every supported user action")
check(!mobileTitle.contains("(text-id secrets)")
        && !mobileTitle.contains("disable-auto-save"),
      "the managed-display title menu exposes no unsupported custom-text rows")
check(menuRouting.contains("(if (pc-host-manages-display?)\n          *main-options*")
        && menuRouting.contains("*main-options-secrets* *main-options-pc*")
        && menuRouting.contains("(if (pc-host-manages-display?) *title-managed-display* *title-pc*)"),
      "mobile uses retail-labeled pause and title rows while desktop keeps its extended menus")

if failures == 0 {
    print("mobile menu copy checks passed")
} else {
    print("mobile menu copy checks failed: \(failures)")
    Foundation.exit(1)
}

import Foundation

private typealias Rejection = VisionImmersiveMappingRejection

nonisolated private struct FixtureDrawable {
    let target: Rejection.Target
    let viewCount: Int
    let colorCount: Int
    let depthCount: Int
}

nonisolated private final class ReadCounter: @unchecked Sendable {
    var views = 0
    var textures = 0
}

@main
nonisolated enum MappingRejectionCheck {
    static func main() {
        let root = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1])
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        checkDocumentBounds()
        checkRecorder()
        checkPresenterSource(root: root)
        print("mapping rejection metadata and cancelled-frame source checks passed")
    }

    private static func document(attempt: UInt64,
                                 _ fixtures: [FixtureDrawable],
                                 counter: ReadCounter = ReadCounter()) -> Rejection.Document {
        Rejection.document(
            attempt: attempt, layerFrameIndex: 9, rejectedGuard: .passPlan,
            failingDrawableIndex: 1, drawables: fixtures,
            accessors: Rejection.Accessors(
                target: { $0.target },
                viewCount: { $0.viewCount },
                rasterizationRateMapCount: { _ in 1 },
                colorTextureCount: { $0.colorCount },
                depthTextureCount: { $0.depthCount },
                view: { _, index in
                    counter.views += 1
                    return Rejection.ViewInput(
                        textureIndex: index, sliceIndex: 1, originX: 0, originY: 0.5,
                        width: 1888.25, height: 1792, nearDepth: .infinity, farDepth: -.nan)
                },
                colorTexture: { _, _ in
                    counter.textures += 1
                    return Rejection.TextureInput(textureType: 3, width: 1888, height: 1792,
                                                  arrayLength: 2)
                },
                depthTexture: { _, _ in
                    counter.textures += 1
                    return Rejection.TextureInput(textureType: 3, width: 1888, height: 1792,
                                                  arrayLength: 2)
                }))
    }

    private static func checkDocumentBounds() {
        let fixtures = [
            FixtureDrawable(target: .builtIn, viewCount: 6, colorCount: 5, depthCount: 5),
            FixtureDrawable(target: .capture, viewCount: 9, colorCount: 2, depthCount: 9),
            FixtureDrawable(target: .unknown, viewCount: 3, colorCount: 1, depthCount: 1),
            FixtureDrawable(target: .builtIn, viewCount: 2, colorCount: 1, depthCount: 1),
            FixtureDrawable(target: .capture, viewCount: 7, colorCount: 4, depthCount: 4),
        ]
        let counter = ReadCounter()
        let result = document(attempt: 4, fixtures, counter: counter)
        precondition(counter.views == 8 && counter.textures == 8, "global caps bound detailed reads")
        precondition(result.drawableCount == 5 && result.drawables.count == 4)
        precondition(result.omittedDrawableCount == 1 && result.builtInDrawableCount == 2)
        precondition(result.totalViewCount == 27 && result.omittedViewCount == 19)
        precondition(result.totalColorTextureCount == 13 && result.totalDepthTextureCount == 20)
        precondition(result.omittedTextureCount == 25 && result.totalRasterizationRateMapCount == 5)
        precondition(result.drawables.map(\.viewCount) == [6, 9, 3, 2])
        precondition(result.drawables.map(\.colorTextureCount) == [5, 2, 1, 1])
        precondition(result.drawables.map(\.depthTextureCount) == [5, 9, 1, 1])
        precondition(result.drawables.map(\.target) == [.builtIn, .capture, .unknown, .builtIn])
        precondition(result.drawables.map { $0.views.count } == [6, 2, 0, 0])
        precondition(result.drawables[1].views.map(\.index) == [0, 1])
        precondition(result.drawables.map { $0.textures.count } == [8, 0, 0, 0])
        precondition(result.drawables[0].textures.map(\.role)
            == Array(repeating: .color, count: 5) + Array(repeating: .depth, count: 3))
        precondition(result.drawables[0].textures.map(\.index) == [0, 1, 2, 3, 4, 0, 1, 2])
        let view = result.drawables[0].views[0]
        precondition(view.width.value == 1888.25 && view.originY.value == 0.5)
        precondition(view.nearDepth.kind == .positiveInfinity && view.nearDepth.value == nil)
        precondition(view.farDepth.kind == .nan && view.farDepth.value == nil)
        let encoded = try! JSONEncoder().encode(result)
        precondition(try! JSONDecoder().decode(Rejection.Document.self, from: encoded) == result)
    }

    private static func checkRecorder() {
        let fixture = [FixtureDrawable(target: .builtIn, viewCount: 1, colorCount: 1, depthCount: 1)]
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "mapping-rejection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "immersive-mapping-rejection.json")
        let recorder = VisionImmersiveMappingRejectionRecorder(outputURL: url)
        func stored() -> Rejection.Document {
            recorder.flush()
            return try! JSONDecoder().decode(Rejection.Document.self,
                                             from: Data(contentsOf: url))
        }
        let first = document(attempt: 4, fixture)
        recorder.record(first)
        recorder.record(document(attempt: 4, fixtures2(fixture)))
        precondition(stored() == first, "same-attempt rejection must not overwrite the first")
        recorder.record(document(attempt: 3, fixture))
        precondition(stored() == first, "stale attempt must not overwrite")
        let newer = document(attempt: 5, fixtures2(fixture))
        recorder.record(newer)
        precondition(stored() == newer, "higher attempt replaces the sidecar")
        let unwritable = VisionImmersiveMappingRejectionRecorder(
            outputURL: URL(fileURLWithPath: "/dev/null/x/y.json"))
        unwritable.record(first)
        unwritable.flush()
    }

    private static func fixtures2(_ fixture: [FixtureDrawable]) -> [FixtureDrawable] {
        fixture + fixture
    }

    private static func checkPresenterSource(root: URL) {
        let source = try! String(
            contentsOf: root.appending(
                path: "GOALPad/Vision/Immersive/VisionImmersiveFramePresenter.swift"),
            encoding: .utf8)
        func offset(_ needle: String, after start: String.Index? = nil) -> String.Index {
            let range = source.range(of: needle, range: (start ?? source.startIndex)..<source.endIndex)
            guard let range else { fatalError("missing presenter source: \(needle)") }
            return range.lowerBound
        }
        let render = offset("private func renderFrame()")
        let query = offset("let drawables = layerFrame.queryDrawables()\n", after: render)
        let emptyGuard = offset("guard !drawables.isEmpty else { return }\n", after: query)
        let prepare = offset("prepare(drawables, layerFrameIndex: layerFrame.frameIndex)",
                             after: emptyGuard)
        let submission = offset("layerFrame.startSubmission()", after: prepare)
        let tick = offset("tickGame(request:", after: submission)
        precondition(query < emptyGuard && emptyGuard < prepare && submission < tick)
        let queryToGuard = String(source[query..<emptyGuard])
            .replacingOccurrences(of: "let drawables = layerFrame.queryDrawables()", with: "")
        let codeBetween = queryToGuard.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined()
        precondition(codeBetween.trimmingCharacters(in: .whitespaces).isEmpty,
                     "no frame/drawable access between query and the cancelled-frame guard")
        precondition(!source[render..<prepare].contains("frameIndex")
            || source[render..<emptyGuard].range(of: "frameIndex") == nil,
                     "frameIndex is read only after the empty guard")
        let emptyLine = source[emptyGuard...].prefix(while: { $0 != "\n" })
        precondition(!emptyLine.contains("fail(") && !emptyLine.contains("record")
            && !emptyLine.contains("Log"))
        precondition(!source.contains("guard !drawables.isEmpty,"),
                     "prepare has no second terminal empty path")

        let calls = source.components(separatedBy: "recordMappingRejection(.").dropFirst()
        precondition(calls.count == 5, "five mapping rejection guards record metadata")
        for call in calls {
            let tail = call.split(separator: "\n", omittingEmptySubsequences: false).prefix(5)
                .joined(separator: "\n")
            precondition(tail.contains("fail(Self.unpresentableMapping)"),
                         "each rejection guard keeps the generic user-visible failure")
        }
        let message = offset("private static let unpresentableMapping =")
        let messageLine = source[message...].prefix(150)
        precondition(!messageLine.contains("\\("), "generic failure has no technical metadata")
        precondition(!source.contains("fail(Self.unpresentableMapping +")
            && !source.contains("unpresentableMapping + "))
    }
}

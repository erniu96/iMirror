import Foundation

@main
private struct UnitTests {
    private static var failures = 0

    static func main() throws {
        let defaults = try ReceiverConfiguration(baseName: "  Living Room  ", installationTag: "A7K2")
        expect(defaults.baseName == "Living Room", "接收器名称会去除首尾空白")
        expect(defaults.advertisedName == "Living Room-A7K2", "接收器名称包含稳定的本机标记")

        do {
            _ = try ReceiverConfiguration(baseName: "iMirror", installationTag: "O0I1")
            expect(false, "拒绝容易混淆或不在约定字符集内的标记")
        } catch {
            expect(true, "拒绝容易混淆或不在约定字符集内的标记")
        }

        testReceiverNameLimits()
        try testSettingsRecovery()
        testAnnexBParserEdges()

        let stream = Data([0, 0, 0, 1, 0x67, 0x01, 0, 0, 1, 0x68, 0x02])
        let units = AnnexBParser.nalUnits(in: stream)
        expect(units.count == 2, "解析三字节和四字节 Annex-B 起始码")
        expect(units.first == Data([0x67, 0x01]), "保留第一个 NAL 负载")
        expect(units.last == Data([0x68, 0x02]), "保留最后一个 NAL 负载")

        testVideoSessionIsolation()
        testVideoSessionReplayOrdering()
        testVideoSessionBufferLimit()
        testVideoSessionCloseAndReopen()
        testOrientationWindowSizing()
        testAspectFitViewport()

        if failures > 0 {
            print("测试失败：\(failures) 项")
            exit(1)
        }
        print("全部单元测试通过")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            print("✓ \(message)")
        } else {
            failures += 1
            print("✗ \(message)")
        }
    }

    private static func testReceiverNameLimits() {
        let limitName = String(repeating: "a", count: 58)
        expect(
            (try? ReceiverConfiguration(baseName: limitName, installationTag: "A7K2"))?.advertisedName.utf8.count == 63,
            "Bonjour 名称允许完整的 63 字节边界"
        )
        expect(
            (try? ReceiverConfiguration(baseName: limitName + "a", installationTag: "A7K2")) == nil,
            "Bonjour 名称拒绝超过 63 字节"
        )
        expect(
            (try? ReceiverConfiguration(baseName: String(repeating: "镜", count: 20), installationTag: "A7K2")) == nil,
            "中文名称按 UTF-8 字节数验证"
        )
        expect(
            (try? ReceiverConfiguration(baseName: " \n\t ", installationTag: "A7K2")) == nil,
            "接收器名称不能只有空白"
        )
    }

    private static func testAnnexBParserEdges() {
        expect(AnnexBParser.nalUnits(in: Data()).isEmpty, "空 H.264 数据不会生成 NAL")
        let rawNAL = Data([0x65, 0x01, 0x02])
        expect(AnnexBParser.nalUnits(in: rawNAL) == [rawNAL], "无起始码的数据作为单个 NAL 保留")
        let adjacentStartCodes = Data([0, 0, 1, 0, 0, 0, 1, 0x65, 0x01, 0, 0, 1])
        expect(
            AnnexBParser.nalUnits(in: adjacentStartCodes) == [Data([0x65, 0x01])],
            "相邻或末尾的起始码不会产生空 NAL"
        )
    }

    private static func testSettingsRecovery() throws {
        let suiteName = "iMirror.UnitTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("O0I1", forKey: "installationTag")
        defaults.set(" \n ", forKey: "receiverName")

        let store = SettingsStore(defaults: defaults)
        let recovered = store.loadConfiguration()
        expect(recovered.baseName == ReceiverConfiguration.defaultBaseName, "损坏的接收器名称恢复为默认值")
        expect(recovered.installationTag != "O0I1", "损坏的本机标记会重新生成")
        expect(store.loadConfiguration() == recovered, "新生成的本机标记会持久保存")
        let saved = try store.saveBaseName("  Office  ")
        expect(saved.baseName == "Office" && saved.installationTag == recovered.installationTag, "修改名称保留稳定的本机标记")
        expect(store.loadConfiguration() == saved, "保存的名称会在下次加载时生效")
        expect(store.alwaysOnTop, "首次使用默认置顶")
        store.alwaysOnTop = false
        expect(!SettingsStore(defaults: defaults).alwaysOnTop, "取消置顶的设置会持久保存")
    }

    private static func testVideoSessionIsolation() {
        let router = VideoSessionRouter()
        let first = RecordingVideoSink()
        let second = RecordingVideoSink()

        router.route(sessionID: 11, accessUnit: Data([1]))
        router.route(sessionID: 22, accessUnit: Data([2]))
        router.attach(sessionID: 11, sink: first)
        router.attach(sessionID: 22, sink: second)
        router.route(sessionID: 11, accessUnit: Data([3]))

        expect(first.bytes == [1, 3], "两路投屏数据不会混入同一个解码器")
        expect(second.bytes == [2], "每个连接拥有独立的视频路由")

        router.detach(sessionID: 11)
        router.route(sessionID: 11, accessUnit: Data([4]))
        let replacement = RecordingVideoSink()
        router.attach(sessionID: 11, sink: replacement)
        expect(replacement.bytes.isEmpty, "断开后的迟到视频帧会被丢弃")
    }

    private static func testVideoSessionReplayOrdering() {
        let router = VideoSessionRouter()
        router.route(sessionID: 33, accessUnit: Data([1]))
        router.route(sessionID: 33, accessUnit: Data([2]))

        let sink = ReentrantVideoSink(router: router, sessionID: 33)
        router.attach(sessionID: 33, sink: sink)
        expect(sink.bytes == [1, 2, 3], "创建窗口期间到达的视频帧保持原始顺序")
    }

    private static func testVideoSessionBufferLimit() {
        let router = VideoSessionRouter(maximumPendingBytes: 3)
        router.route(sessionID: 44, accessUnit: Data([1, 1]))
        router.route(sessionID: 44, accessUnit: Data([2, 2]))
        let sink = RecordingVideoSink()
        router.attach(sessionID: 44, sink: sink)
        expect(sink.accessUnits == [Data([2, 2])], "等待窗口期间的视频缓冲有明确上限")
    }

    private static func testVideoSessionCloseAndReopen() {
        let router = VideoSessionRouter()
        let oldSink = RecordingVideoSink()
        router.attach(sessionID: 55, sink: oldSink)
        router.route(sessionID: 66, accessUnit: Data([1]))
        router.detachAll()
        router.route(sessionID: 55, accessUnit: Data([2]))
        router.route(sessionID: 66, accessUnit: Data([3]))

        let replacement = RecordingVideoSink()
        router.attach(sessionID: 66, sink: replacement)
        expect(oldSink.bytes.isEmpty && replacement.bytes.isEmpty, "关闭全部连接后丢弃旧连接的缓冲和迟到数据")
        router.route(sessionID: 66, accessUnit: Data([4]))
        expect(replacement.bytes == [4], "重新注册的连接可以接收新数据")
    }

    private static func testAspectFitViewport() {
        // Portrait iPhone on a maximized 16:10 window: pillarboxed, centered.
        let portrait = MirrorWindowSizing.aspectFitRect(
            content: CGSize(width: 1170, height: 2532),
            in: CGSize(width: 2880, height: 1800)
        )
        expect(portrait.height == 1800, "竖屏画面在最大化窗口中按高度铺满")
        expect(abs(portrait.width / portrait.height - 1170.0 / 2532.0) < 0.002, "最大化时保持视频宽高比，不拉伸")
        expect(abs(portrait.midX - 1440) <= 1, "竖屏画面在窗口中水平居中")

        // Landscape video on a taller window: letterboxed.
        let landscape = MirrorWindowSizing.aspectFitRect(
            content: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 1000, height: 1000)
        )
        expect(landscape.width == 1000 && landscape.height == 563, "横屏画面在高窗口中按宽度铺满")
        expect(landscape.minY == 218, "横屏画面在窗口中垂直居中")

        let exact = MirrorWindowSizing.aspectFitRect(
            content: CGSize(width: 1280, height: 720),
            in: CGSize(width: 640, height: 360)
        )
        expect(exact == CGRect(x: 0, y: 0, width: 640, height: 360), "比例一致时画面铺满整个窗口")
        expect(
            MirrorWindowSizing.aspectFitRect(content: .zero, in: CGSize(width: 100, height: 50))
                == CGRect(x: 0, y: 0, width: 100, height: 50),
            "尚无视频尺寸时使用整个窗口"
        )
    }

    private static func testOrientationWindowSizing() {
        let portrait = CGSize(width: 360, height: 780)
        let landscape = MirrorWindowSizing.sizePreservingArea(
            currentSize: portrait,
            aspectRatio: 16.0 / 9.0,
            minimumSize: CGSize(width: 220, height: 220),
            maximumSize: CGSize(width: 1_400, height: 900)
        )

        expect(landscape.width > 700 && landscape.height > 390, "竖屏切换横屏时窗口不会缩成狭小条带")
        expect(abs(landscape.width / landscape.height - 16.0 / 9.0) < 0.001, "方向切换后保持视频宽高比")
        expect(abs(landscape.width * landscape.height - portrait.width * portrait.height) < 1, "方向切换时保持窗口视觉面积")

        let constrained = MirrorWindowSizing.sizePreservingArea(
            currentSize: CGSize(width: 1_400, height: 900),
            aspectRatio: 16.0 / 9.0,
            minimumSize: CGSize(width: 220, height: 220),
            maximumSize: CGSize(width: 800, height: 600)
        )
        expect(constrained.width <= 800 && constrained.height <= 600, "方向切换后的窗口不会超出屏幕可见区域")
    }
}

private class RecordingVideoSink: VideoDataSink {
    private(set) var accessUnits: [Data] = []
    var bytes: [UInt8] { accessUnits.flatMap { $0 } }

    func enqueue(_ accessUnit: Data) {
        accessUnits.append(accessUnit)
    }
}

private final class ReentrantVideoSink: RecordingVideoSink {
    private let router: VideoSessionRouter
    private let sessionID: UInt64
    private var didInjectPacket = false

    init(router: VideoSessionRouter, sessionID: UInt64) {
        self.router = router
        self.sessionID = sessionID
    }

    override func enqueue(_ accessUnit: Data) {
        super.enqueue(accessUnit)
        guard !didInjectPacket else { return }
        didInjectPacket = true
        router.route(sessionID: sessionID, accessUnit: Data([3]))
    }
}

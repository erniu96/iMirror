import CoreVideo
import Foundation

@main
private struct VideoPipelineSmokeTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("用法：VideoPipelineSmokeTests <Annex-B H.264 文件>")
            exit(2)
        }

        let stream = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard !stream.isEmpty else {
            print("H.264 管线测试失败：测试文件为空")
            exit(1)
        }
        let requireHardwareAcceleration = ProcessInfo.processInfo.environment["IMIRROR_ALLOW_SOFTWARE_DECODER"] != "1"
        let pipelines = [
            VideoPipeline(requireHardwareAcceleration: requireHardwareAcceleration),
            VideoPipeline(requireHardwareAcceleration: requireHardwareAcceleration)
        ]
        var frameCounts = [0, 0]
        var firstFrameCounts = [0, 0]
        var firstSizes = [CGSize.zero, CGSize.zero]
        var decodeErrors = [String?](repeating: nil, count: pipelines.count)

        for (index, pipeline) in pipelines.enumerated() {
            pipeline.onFrame = { frame in
                frameCounts[index] += 1
                if frame.isFirstFrame {
                    firstFrameCounts[index] += 1
                    firstSizes[index] = frame.size
                }
            }
            pipeline.onError = { decodeErrors[index] = $0 }
            pipeline.enqueue(stream)
        }

        let deadline = Date().addingTimeInterval(5)
        while frameCounts.contains(0), decodeErrors.allSatisfy({ $0 == nil }), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        if let decodeError = decodeErrors.compactMap({ $0 }).first {
            print("H.264 管线测试失败：\(decodeError)")
            exit(1)
        }
        guard !frameCounts.contains(0), firstFrameCounts == [1, 1] else {
            print("H.264 管线测试失败：两路管线未能在 5 秒内分别解码出画面")
            exit(1)
        }
        guard firstSizes[0].width > 0, firstSizes[0].height > 0, firstSizes[0] == firstSizes[1] else {
            print("H.264 管线测试失败：首帧尺寸无效或两路解码结果不一致")
            exit(1)
        }

        let dimensions = firstSizes.map { "\(Int($0.width))×\(Int($0.height))" }.joined(separator: "、")
        print("✓ 两路 H.264 VideoToolbox 解码相互独立：\(frameCounts)，首帧 \(dimensions)")
    }
}

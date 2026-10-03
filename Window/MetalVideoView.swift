import CoreVideo
import Metal
import MetalKit
import simd

final class MetalVideoView: MTKView, MTKViewDelegate {
    private struct ColorConversion {
        var matrix: simd_float3x3
        var offset: SIMD3<Float>
    }

    private final class RenderFrame {
        let pixelBuffer: CVPixelBuffer
        let yReference: CVMetalTexture
        let uvReference: CVMetalTexture
        let colorConversion: ColorConversion

        init(
            pixelBuffer: CVPixelBuffer,
            yReference: CVMetalTexture,
            uvReference: CVMetalTexture,
            colorConversion: ColorConversion
        ) {
            self.pixelBuffer = pixelBuffer
            self.yReference = yReference
            self.uvReference = uvReference
            self.colorConversion = colorConversion
        }
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private var textureCache: CVMetalTextureCache?
    private var currentVideoFrame: RenderFrame?

    init(renderFrame frameRect: CGRect = .zero) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw RendererError.metalUnavailable
        }

        // 一个超出视口的三角形覆盖整个 drawable，彻底消除两个三角形
        // 在驱动异常时可能产生的对角分界。
        let vertices: [Float] = [
            -1, -1, 0, 0,
             3, -1, 2, 0,
            -1,  3, 0, 2
        ]
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw RendererError.bufferCreationFailed
        }

        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mirrorVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mirrorFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.commandQueue = commandQueue
        self.vertexBuffer = vertexBuffer
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        super.init(frame: frameRect, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = false
        autoResizeDrawable = true
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 60
        presentsWithTransaction = false
        wantsLayer = true
        delegate = self
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ pixelBuffer: CVPixelBuffer) {
        guard let textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else { return }

        var yReference: CVMetalTexture?
        var uvReference: CVMetalTexture?
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .r8Unorm, width, height, 0, &yReference
        )
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .rg8Unorm, width / 2, height / 2, 1, &uvReference
        )
        guard yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
              let yReference, let uvReference else { return }

        currentVideoFrame = RenderFrame(
            pixelBuffer: pixelBuffer,
            yReference: yReference,
            uvReference: uvReference,
            colorConversion: Self.colorConversion(for: pixelBuffer)
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let currentVideoFrame,
              let yTexture = CVMetalTextureGetTexture(currentVideoFrame.yReference),
              let uvTexture = CVMetalTextureGetTexture(currentVideoFrame.uvReference),
              let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)

        var colorConversion = currentVideoFrame.colorConversion
        encoder.setFragmentBytes(
            &colorConversion,
            length: MemoryLayout<ColorConversion>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [currentVideoFrame] _ in
            _ = currentVideoFrame.pixelBuffer
        }
        commandBuffer.commit()
    }

    private static func colorConversion(for pixelBuffer: CVPixelBuffer) -> ColorConversion {
        let attachment = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferYCbCrMatrixKey,
            nil
        )
        let isVideoRange = CVPixelBufferGetPixelFormatType(pixelBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        if let attachment,
           CFEqual(attachment, kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            return isVideoRange ? videoRange601 : fullRange601
        }
        if let attachment,
           CFEqual(attachment, kCVImageBufferYCbCrMatrix_ITU_R_2020) {
            return isVideoRange ? videoRange2020 : fullRange2020
        }
        return isVideoRange ? videoRange709 : fullRange709
    }

    private static let videoRange709 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1.164_383, 0, 1.792_741),
            SIMD3(1.164_383, -0.213_249, -0.532_909),
            SIMD3(1.164_383, 2.112_402, 0)
        ]),
        offset: SIMD3(-16.0 / 255.0, -0.5, -0.5)
    )

    private static let videoRange601 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1.164_383, 0, 1.596_027),
            SIMD3(1.164_383, -0.391_762, -0.812_968),
            SIMD3(1.164_383, 2.017_232, 0)
        ]),
        offset: SIMD3(-16.0 / 255.0, -0.5, -0.5)
    )

    private static let videoRange2020 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1.164_383, 0, 1.678_674),
            SIMD3(1.164_383, -0.187_326, -0.650_424),
            SIMD3(1.164_383, 2.141_772, 0)
        ]),
        offset: SIMD3(-16.0 / 255.0, -0.5, -0.5)
    )

    private static let fullRange709 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1, 0, 1.5748),
            SIMD3(1, -0.187_324, -0.468_124),
            SIMD3(1, 1.8556, 0)
        ]),
        offset: SIMD3(0, -0.5, -0.5)
    )

    private static let fullRange601 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1, 0, 1.402),
            SIMD3(1, -0.344_136, -0.714_136),
            SIMD3(1, 1.772, 0)
        ]),
        offset: SIMD3(0, -0.5, -0.5)
    )

    private static let fullRange2020 = ColorConversion(
        matrix: simd_float3x3(rows: [
            SIMD3(1, 0, 1.4746),
            SIMD3(1, -0.164_553, -0.571_353),
            SIMD3(1, 1.8814, 0)
        ]),
        offset: SIMD3(0, -0.5, -0.5)
    )

    enum RendererError: LocalizedError {
        case metalUnavailable
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: return "当前 Mac 不支持 Metal。"
            case .bufferCreationFailed: return "无法创建 Metal 顶点缓冲区。"
            }
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOutput {
        float4 position [[position]];
        float2 textureCoordinate;
    };

    struct ColorConversion {
        float3x3 matrix;
        float3 offset;
    };

    vertex VertexOutput mirrorVertex(constant float4 *vertices [[buffer(0)]], uint id [[vertex_id]]) {
        VertexOutput output;
        output.position = float4(vertices[id].xy, 0.0, 1.0);
        output.textureCoordinate = float2(vertices[id].z, 1.0 - vertices[id].w);
        return output;
    }

    fragment float4 mirrorFragment(
        VertexOutput input [[stage_in]],
        texture2d<float> yTexture [[texture(0)]],
        texture2d<float> uvTexture [[texture(1)]],
        constant ColorConversion &colorConversion [[buffer(0)]]) {
        constexpr sampler textureSampler(address::clamp_to_edge, filter::linear);
        float y = yTexture.sample(textureSampler, input.textureCoordinate).r;
        float2 uv = uvTexture.sample(textureSampler, input.textureCoordinate).rg;
        float3 ycbcr = float3(y, uv) + colorConversion.offset;
        float3 rgb = colorConversion.matrix * ycbcr;
        return float4(saturate(rgb), 1.0);
    }
    """
}

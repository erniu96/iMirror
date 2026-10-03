import CoreGraphics
import CoreVideo
import Foundation

final class VideoPipeline: VideoDataSink {
    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let size: CGSize
        let isFirstFrame: Bool
    }

    var onFrame: ((Frame) -> Void)?
    var onError: ((String) -> Void)?

    private let decoder: H264Decoder
    private let queue = DispatchQueue(label: "com.erniu.imirror.video-decode", qos: .userInteractive)
    private let deliveryLock = NSLock()
    private var hasDeliveredFrame = false
    private var pendingFrame: Frame?
    private var deliveryScheduled = false

    init(requireHardwareAcceleration: Bool = true) {
        decoder = H264Decoder(requireHardwareAcceleration: requireHardwareAcceleration)
        decoder.onDecodedFrame = { [weak self] pixelBuffer in
            self?.deliver(pixelBuffer)
        }
        decoder.onError = { [weak self] message in
            DispatchQueue.main.async { self?.onError?(message) }
        }
    }

    func enqueue(_ accessUnit: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            AnnexBParser.nalUnits(in: accessUnit).forEach(self.decoder.decode)
        }
    }

    func reset() {
        queue.async { [self] in
            self.decoder.reset()
            self.deliveryLock.lock()
            self.hasDeliveredFrame = false
            self.pendingFrame = nil
            self.deliveryLock.unlock()
        }
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer) {
        let frame = Frame(
            pixelBuffer: pixelBuffer,
            size: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            isFirstFrame: false
        )
        deliveryLock.lock()
        pendingFrame = frame
        guard !deliveryScheduled else {
            deliveryLock.unlock()
            return
        }
        deliveryScheduled = true
        deliveryLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.deliverLatestFrameOnMain()
        }
    }

    private func deliverLatestFrameOnMain() {
        deliveryLock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        deliveryScheduled = false
        let isFirstFrame = !hasDeliveredFrame
        if frame != nil {
            hasDeliveredFrame = true
        }
        deliveryLock.unlock()
        if let frame {
            onFrame?(
                Frame(
                    pixelBuffer: frame.pixelBuffer,
                    size: frame.size,
                    isFirstFrame: isFirstFrame
                )
            )
        }
    }
}

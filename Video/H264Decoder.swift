import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class H264Decoder {
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?

    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var parameterSetsChanged = false
    private let requireHardwareAcceleration: Bool

    init(requireHardwareAcceleration: Bool = true) {
        self.requireHardwareAcceleration = requireHardwareAcceleration
    }

    func decode(_ nalUnit: Data) {
        guard let header = nalUnit.first else { return }

        switch header & 0x1f {
        case 7:
            if sps != nalUnit {
                sps = nalUnit
                parameterSetsChanged = true
            }
        case 8:
            if pps != nalUnit {
                pps = nalUnit
                parameterSetsChanged = true
            }
        case 5:
            if parameterSetsChanged {
                invalidateSession()
                parameterSetsChanged = false
            }
            createSessionIfNeeded()
            decodeFrame(nalUnit)
        default:
            guard decompressionSession != nil else { return }
            decodeFrame(nalUnit)
        }
    }

    func reset() {
        if let session = decompressionSession {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
        }
        invalidateSession()
        sps = nil
        pps = nil
        parameterSetsChanged = false
    }

    private func createSessionIfNeeded() {
        guard decompressionSession == nil, let sps, let pps else { return }

        let parameterSetSizes = [sps.count, pps.count]
        let pointers: [UnsafePointer<UInt8>] = [sps, pps].map { data in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: pointer, count: data.count)
            return UnsafePointer(pointer)
        }
        defer { pointers.forEach { $0.deallocate() } }

        var description: CMVideoFormatDescription?
        let descriptionStatus = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: pointers.count,
            parameterSetPointers: pointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &description
        )
        guard descriptionStatus == noErr, let description else {
            onError?(String(localized: "Couldn’t create the H.264 format description (\(Int(descriptionStatus)))."))
            return
        }
        formatDescription = description

        let decoderSpecification: [CFString: Any] = [
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: requireHardwareAcceleration
        ]
        let imageAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let refcon, let imageBuffer else { return }
                let decoder = Unmanaged<H264Decoder>.fromOpaque(refcon).takeUnretainedValue()
                decoder.onDecodedFrame?(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: imageAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard sessionStatus == noErr, let session else {
            formatDescription = nil
            onError?(String(localized: "Couldn’t create the VideoToolbox decoder (\(Int(sessionStatus)))."))
            return
        }

        decompressionSession = session
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    }

    private func decodeFrame(_ nalUnit: Data) {
        guard let session = decompressionSession, let formatDescription else { return }

        let totalLength = nalUnit.count + MemoryLayout<UInt32>.size
        var blockBuffer: CMBlockBuffer?
        let allocationStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard allocationStatus == kCMBlockBufferNoErr, let blockBuffer else { return }

        var bigEndianLength = CFSwapInt32HostToBig(UInt32(nalUnit.count))
        let lengthStatus = withUnsafeBytes(of: &bigEndianLength) { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: bytes.count
            )
        }
        guard lengthStatus == kCMBlockBufferNoErr else { return }

        let payloadStatus = nalUnit.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: MemoryLayout<UInt32>.size,
                dataLength: bytes.count
            )
        }
        guard payloadStatus == kCMBlockBufferNoErr else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = totalLength
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { return }

        var infoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
        if decodeStatus != noErr {
            onError?(String(localized: "Couldn’t decode an H.264 frame (\(Int(decodeStatus)))."))
        }
    }

    private func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
    }

    deinit {
        invalidateSession()
    }
}

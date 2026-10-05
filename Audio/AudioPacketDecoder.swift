import AVFoundation
import AudioToolbox
import Foundation

/// Decodes one AirPlay audio packet at a time into deinterleaved Float32 PCM.
final class AudioPacketDecoder {
    enum DecoderError: LocalizedError {
        case unsupportedOutputFormat
        case converter(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unsupportedOutputFormat: return "无法创建音频输出格式"
            case .converter(let status): return "无法创建音频解码器（\(status)）"
            }
        }
    }

    let format: AirPlayAudioFormat
    let outputFormat: AVAudioFormat
    /// Status of the most recent AudioConverter call, for diagnostics.
    private(set) var lastStatus: OSStatus = noErr
    private var converter: AudioConverterRef?

    init(format: AirPlayAudioFormat) throws {
        self.format = format
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(AirPlayAudioFormat.channelCount)
        ) else {
            throw DecoderError.unsupportedOutputFormat
        }
        self.outputFormat = outputFormat
        guard format.codec != .pcm16BigEndian else { return }

        var input = format.streamDescription
        var output = outputFormat.streamDescription.pointee
        var converter: AudioConverterRef?
        var status = AudioConverterNew(&input, &output, &converter)
        guard status == noErr, let converter else { throw DecoderError.converter(status) }
        if let cookie = format.magicCookie {
            status = cookie.withUnsafeBytes {
                AudioConverterSetProperty(
                    converter,
                    kAudioConverterDecompressionMagicCookie,
                    UInt32($0.count),
                    $0.baseAddress!
                )
            }
            guard status == noErr else {
                AudioConverterDispose(converter)
                throw DecoderError.converter(status)
            }
        }
        self.converter = converter
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
    }

    /// Returns nil for empty or undecodable packets and while a codec is still priming.
    func decode(_ packet: Data) -> AVAudioPCMBuffer? {
        guard !packet.isEmpty else { return nil }
        if format.codec == .pcm16BigEndian { return convertPCM(packet) }
        guard let converter else { return nil }

        let capacity = AVAudioFrameCount(max(format.framesPerPacket, 4_096))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        // The buffer list reports frameLength bytes; expose the full capacity to the converter.
        buffer.frameLength = capacity

        var frames = UInt32(capacity)
        let status: OSStatus = packet.withUnsafeBytes { bytes in
            let input = UnsafeMutablePointer<PacketInput>.allocate(capacity: 1)
            defer { input.deallocate() }
            input.initialize(to: PacketInput(
                data: bytes.baseAddress!,
                size: UInt32(bytes.count),
                consumed: false,
                description: AudioStreamPacketDescription(
                    mStartOffset: 0,
                    mVariableFramesInPacket: 0,
                    mDataByteSize: UInt32(bytes.count)
                )
            ))
            return AudioConverterFillComplexBuffer(
                converter,
                supplySinglePacket,
                input,
                &frames,
                buffer.mutableAudioBufferList,
                nil
            )
        }
        lastStatus = status
        guard status == noErr || status == endOfPacketStatus, frames > 0 else { return nil }
        buffer.frameLength = frames
        return buffer
    }

    func reset() {
        if let converter { AudioConverterReset(converter) }
    }

    private func convertPCM(_ packet: Data) -> AVAudioPCMBuffer? {
        let channels = Int(AirPlayAudioFormat.channelCount)
        let frameCount = packet.count / (2 * channels)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let channelData = buffer.floatChannelData else { return nil }
        packet.withUnsafeBytes { bytes in
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let offset = (frame * channels + channel) * 2
                    let sample = Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]))
                    channelData[channel][frame] = Float(sample) / 32_768
                }
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }
}

private struct PacketInput {
    var data: UnsafeRawPointer
    var size: UInt32
    var consumed: Bool
    var description: AudioStreamPacketDescription
}

/// Returned by the input callback once its single packet has been handed over.
private let endOfPacketStatus: OSStatus = 0x6E_6D_64_21 // 'nmd!'

private let supplySinglePacket: AudioConverterComplexInputDataProc = { _, packetCount, bufferList, packetDescriptions, userData in
    let input = userData!.assumingMemoryBound(to: PacketInput.self)
    guard !input.pointee.consumed else {
        packetCount.pointee = 0
        return endOfPacketStatus
    }
    input.pointee.consumed = true
    packetCount.pointee = 1
    bufferList.pointee.mNumberBuffers = 1
    bufferList.pointee.mBuffers.mNumberChannels = AirPlayAudioFormat.channelCount
    bufferList.pointee.mBuffers.mDataByteSize = input.pointee.size
    bufferList.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: input.pointee.data)
    if let packetDescriptions {
        let offset = MemoryLayout<PacketInput>.offset(of: \PacketInput.description)!
        packetDescriptions.pointee = UnsafeMutableRawPointer(input)
            .advanced(by: offset)
            .assumingMemoryBound(to: AudioStreamPacketDescription.self)
    }
    return noErr
}

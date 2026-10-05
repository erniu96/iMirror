import AVFoundation
import AudioToolbox
import Foundation

/// Encodes a sine wave with Core Audio's own encoders, then decodes the packets
/// with AudioPacketDecoder, which only knows the AirPlay SETUP parameters.
/// This checks the hand-built magic cookies against real codec output.
@main
private struct AudioDecoderTests {
    private static var failures = 0

    static func main() {
        let eld = AirPlayAudioFormat(compressionType: 8, sampleRate: 44_100, framesPerPacket: 480)!
        expect(eld.audioSpecificConfig == Data([0xF8, 0xE8, 0x50, 0x00]), "AAC-ELD 44.1 kHz 立体声 480 帧的 AudioSpecificConfig")
        let lc = AirPlayAudioFormat(compressionType: 4, sampleRate: 44_100, framesPerPacket: 1_024)!
        expect(lc.audioSpecificConfig == Data([0x12, 0x10]), "AAC-LC 44.1 kHz 立体声的 AudioSpecificConfig")
        expect(AirPlayAudioFormat(compressionType: 8, sampleRate: 0, framesPerPacket: 0)?.framesPerPacket == 480, "缺省参数按编码类型补全")
        expect(AirPlayAudioFormat(compressionType: 3, sampleRate: 44_100, framesPerPacket: 0) == nil, "拒绝未知编码类型")

        for format in [
            eld,
            lc,
            AirPlayAudioFormat(compressionType: 2, sampleRate: 44_100, framesPerPacket: 352)!,
            AirPlayAudioFormat(compressionType: 1, sampleRate: 44_100, framesPerPacket: 352)!
        ] {
            roundTrip(format)
        }

        if failures > 0 {
            print("音频解码测试失败：\(failures) 项")
            exit(1)
        }
        print("✓ AirPlay 音频解码：AAC-ELD、AAC-LC、ALAC、PCM 均可还原")
    }

    private static func roundTrip(_ format: AirPlayAudioFormat) {
        let name = "\(format.codec)"
        let sampleRate = Double(format.sampleRate)
        let frameCount = Int(sampleRate) // one second
        var interleaved = [Int16](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            let sample = Int16(sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate) * 16_384)
            interleaved[frame * 2] = sample
            interleaved[frame * 2 + 1] = sample
        }

        let packets: [Data]
        if format.codec == .pcm16BigEndian {
            let bytesPerPacket = Int(format.framesPerPacket) * 4
            let bigEndian = interleaved.flatMap { [UInt8(UInt16(bitPattern: $0) >> 8), UInt8(UInt16(bitPattern: $0) & 0xFF)] }
            packets = stride(from: 0, to: bigEndian.count, by: bytesPerPacket).map {
                Data(bigEndian[$0..<min($0 + bytesPerPacket, bigEndian.count)])
            }
        } else {
            guard let encoded = encode(interleaved, as: format) else {
                expect(false, "\(name)：系统编码器无法生成测试数据")
                return
            }
            packets = encoded
        }

        let decoder: AudioPacketDecoder
        do {
            decoder = try AudioPacketDecoder(format: format)
        } catch {
            expect(false, "\(name)：创建解码器失败：\(error.localizedDescription)")
            return
        }

        var decodedFrames = 0
        var sumOfSquares = 0.0
        var measuredSamples = 0
        for packet in packets {
            guard let buffer = decoder.decode(packet), let channels = buffer.floatChannelData else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                // Skip codec priming at the start of the stream.
                if decodedFrames + frame > 4_096 {
                    let value = Double(channels[0][frame])
                    sumOfSquares += value * value
                    measuredSamples += 1
                }
            }
            decodedFrames += Int(buffer.frameLength)
        }
        let rms = measuredSamples > 0 ? sqrt(sumOfSquares / Double(measuredSamples)) : 0
        expect(decodedFrames > frameCount * 8 / 10, "\(name)：解码出 \(decodedFrames)/\(frameCount) 帧")
        // A 0.5-amplitude sine has an RMS of about 0.354.
        expect(rms > 0.25 && rms < 0.45, "\(name)：解码音量 RMS=\(String(format: "%.3f", rms))")
    }

    private struct EncoderInput {
        var samples: UnsafePointer<Int16>
        var frameCount: Int
        var position: Int
    }

    private static func encode(_ interleaved: [Int16], as format: AirPlayAudioFormat) -> [Data]? {
        var pcm = AudioStreamBasicDescription(
            mSampleRate: Double(format.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var compressed = format.streamDescription
        var converter: AudioConverterRef?
        var status = AudioConverterNew(&pcm, &compressed, &converter)
        guard status == noErr, let converter else {
            print("  AudioConverterNew(\(format.codec)) = \(status)")
            return nil
        }
        defer { AudioConverterDispose(converter) }

        var maximumPacketSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &propertySize, &maximumPacketSize)
        maximumPacketSize = max(maximumPacketSize, 8_192)

        return interleaved.withUnsafeBufferPointer { samples -> [Data]? in
            var input = EncoderInput(samples: samples.baseAddress!, frameCount: interleaved.count / 2, position: 0)
            var packets: [Data] = []
            let output = UnsafeMutableRawPointer.allocate(byteCount: Int(maximumPacketSize), alignment: 16)
            defer { output.deallocate() }
            while true {
                var bufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: maximumPacketSize, mData: output)
                )
                var packetCount: UInt32 = 1
                var description = AudioStreamPacketDescription()
                status = AudioConverterFillComplexBuffer(converter, { _, count, data, _, user in
                    let input = user!.assumingMemoryBound(to: EncoderInput.self)
                    let remaining = input.pointee.frameCount - input.pointee.position
                    guard remaining > 0 else {
                        count.pointee = 0
                        return noErr
                    }
                    let frames = min(Int(count.pointee), remaining, 4_096)
                    count.pointee = UInt32(frames)
                    data.pointee.mNumberBuffers = 1
                    data.pointee.mBuffers.mNumberChannels = 2
                    data.pointee.mBuffers.mDataByteSize = UInt32(frames * 4)
                    data.pointee.mBuffers.mData = UnsafeMutableRawPointer(
                        mutating: input.pointee.samples.advanced(by: input.pointee.position * 2)
                    )
                    input.pointee.position += frames
                    return noErr
                }, &input, &packetCount, &bufferList, &description)
                guard status == noErr else {
                    print("  AudioConverterFillComplexBuffer(\(format.codec)) = \(status)")
                    return nil
                }
                if packetCount == 0 { break }
                packets.append(Data(bytes: output, count: Int(bufferList.mBuffers.mDataByteSize)))
            }
            return packets
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("✓ \(message)")
        } else {
            failures += 1
            print("✗ \(message)")
        }
    }
}

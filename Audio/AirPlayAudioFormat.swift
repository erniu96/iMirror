import AudioToolbox
import Foundation

/// The audio stream an AirPlay sender negotiates in the type-96 SETUP request.
struct AirPlayAudioFormat: Equatable {
    enum Codec: Equatable {
        case pcm16BigEndian
        case appleLossless
        case aacLowComplexity
        case aacEnhancedLowDelay
    }

    static let channelCount: UInt32 = 2

    let codec: Codec
    let sampleRate: UInt32
    let framesPerPacket: UInt32

    /// `compressionType` is the SETUP `ct` field: 1 PCM, 2 ALAC, 4 AAC-LC, 8 AAC-ELD.
    init?(compressionType: UInt8, sampleRate: UInt32, framesPerPacket: UInt32) {
        switch compressionType {
        case 1: codec = .pcm16BigEndian
        case 2: codec = .appleLossless
        case 4: codec = .aacLowComplexity
        case 8: codec = .aacEnhancedLowDelay
        default: return nil
        }
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        if framesPerPacket > 0 {
            self.framesPerPacket = framesPerPacket
        } else {
            switch codec {
            case .pcm16BigEndian, .appleLossless: self.framesPerPacket = 352
            case .aacLowComplexity: self.framesPerPacket = 1_024
            case .aacEnhancedLowDelay: self.framesPerPacket = 480
            }
        }
    }

    var streamDescription: AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        description.mSampleRate = Float64(sampleRate)
        description.mChannelsPerFrame = Self.channelCount
        description.mFramesPerPacket = framesPerPacket
        switch codec {
        case .pcm16BigEndian:
            description.mFormatID = kAudioFormatLinearPCM
            description.mFormatFlags = kAudioFormatFlagIsSignedInteger
                | kAudioFormatFlagIsBigEndian
                | kAudioFormatFlagIsPacked
            description.mBitsPerChannel = 16
            description.mBytesPerFrame = 2 * Self.channelCount
            description.mFramesPerPacket = 1
            description.mBytesPerPacket = description.mBytesPerFrame
        case .appleLossless:
            description.mFormatID = kAudioFormatAppleLossless
            description.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData
        case .aacLowComplexity:
            description.mFormatID = kAudioFormatMPEG4AAC
        case .aacEnhancedLowDelay:
            description.mFormatID = kAudioFormatMPEG4AAC_ELD
        }
        return description
    }

    /// Decoder configuration for the compressed formats. AirPlay never sends one,
    /// so it is derived from the negotiated parameters exactly as AirPlay encoders use them.
    var magicCookie: Data? {
        switch codec {
        case .pcm16BigEndian:
            return nil
        case .appleLossless:
            return appleLosslessConfig
        case .aacLowComplexity, .aacEnhancedLowDelay:
            return Self.elementaryStreamDescriptor(wrapping: audioSpecificConfig)
        }
    }

    /// 24-byte ALACSpecificConfig with the parameters AirPlay senders use.
    private var appleLosslessConfig: Data {
        var data = Data()
        data.appendBigEndian(framesPerPacket)
        data.append(contentsOf: [0, 16, 40, 10, 14, UInt8(Self.channelCount)])
        data.appendBigEndian(UInt16(255))
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(sampleRate)
        return data
    }

    /// MPEG-4 AudioSpecificConfig (ISO/IEC 14496-3 1.6.2.1).
    var audioSpecificConfig: Data {
        var bits = BitWriter()
        switch codec {
        case .aacEnhancedLowDelay:
            bits.write(31, count: 5)
            bits.write(39 - 32, count: 6)
        default:
            bits.write(2, count: 5)
        }
        if let index = Self.samplingFrequencyIndex(for: sampleRate) {
            bits.write(index, count: 4)
        } else {
            bits.write(15, count: 4)
            bits.write(sampleRate, count: 24)
        }
        bits.write(Self.channelCount, count: 4)
        if codec == .aacEnhancedLowDelay {
            bits.write(framesPerPacket == 480 ? 1 : 0, count: 1) // frameLengthFlag
            bits.write(0, count: 3) // section, scalefactor and spectral data resilience
            bits.write(0, count: 1) // ldSbrPresentFlag
            bits.write(0, count: 4) // ELDEXT_TERM
            bits.write(0, count: 2) // epConfig
        } else {
            bits.write(framesPerPacket == 960 ? 1 : 0, count: 1) // frameLengthFlag
            bits.write(0, count: 1) // dependsOnCoreCoder
            bits.write(0, count: 1) // extensionFlag
        }
        return bits.data
    }

    private static func samplingFrequencyIndex(for sampleRate: UInt32) -> UInt32? {
        let rates: [UInt32] = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
        return rates.firstIndex(of: sampleRate).map(UInt32.init)
    }

    /// Wraps an AudioSpecificConfig in the ES_Descriptor that Core Audio expects as an AAC magic cookie.
    private static func elementaryStreamDescriptor(wrapping config: Data) -> Data {
        var decoderSpecificInfo = Data()
        appendDescriptor(tag: 0x05, payload: config, to: &decoderSpecificInfo)

        var decoderConfig = Data([0x40, 0x15, 0, 0, 0])
        decoderConfig.appendBigEndian(UInt32(0)) // maxBitrate
        decoderConfig.appendBigEndian(UInt32(0)) // avgBitrate
        decoderConfig.append(decoderSpecificInfo)

        var elementaryStream = Data([0, 0, 0]) // ES_ID and flags
        appendDescriptor(tag: 0x04, payload: decoderConfig, to: &elementaryStream)

        var cookie = Data()
        appendDescriptor(tag: 0x03, payload: elementaryStream, to: &cookie)
        return cookie
    }

    private static func appendDescriptor(tag: UInt8, payload: Data, to data: inout Data) {
        let length = UInt32(payload.count)
        data.append(tag)
        data.append(contentsOf: [
            UInt8(0x80 | ((length >> 21) & 0x7F)),
            UInt8(0x80 | ((length >> 14) & 0x7F)),
            UInt8(0x80 | ((length >> 7) & 0x7F)),
            UInt8(length & 0x7F)
        ])
        data.append(payload)
    }
}

private struct BitWriter {
    private(set) var data = Data()
    private var bitCount = 0

    mutating func write(_ value: UInt32, count: Int) {
        for shift in stride(from: count - 1, through: 0, by: -1) {
            if bitCount % 8 == 0 { data.append(0) }
            if (value >> UInt32(shift)) & 1 == 1 {
                data[data.count - 1] |= UInt8(0x80 >> (bitCount % 8))
            }
            bitCount += 1
        }
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

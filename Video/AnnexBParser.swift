import Foundation

enum AnnexBParser {
    static func nalUnits(in data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        let bytes = [UInt8](data)
        let starts = startCodes(in: bytes)

        guard !starts.isEmpty else {
            return [data]
        }

        var result: [Data] = []
        for index in starts.indices {
            let payloadStart = starts[index].payloadStart
            let payloadEnd = index + 1 < starts.count ? starts[index + 1].codeStart : bytes.count
            guard payloadEnd > payloadStart else { continue }
            result.append(Data(bytes[payloadStart..<payloadEnd]))
        }
        return result
    }

    private static func startCodes(in bytes: [UInt8]) -> [(codeStart: Int, payloadStart: Int)] {
        guard bytes.count >= 3 else { return [] }
        var result: [(Int, Int)] = []
        var index = 0

        while index + 2 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    result.append((index, index + 3))
                    index += 3
                    continue
                }
                if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                    result.append((index, index + 4))
                    index += 4
                    continue
                }
            }
            index += 1
        }
        return result
    }
}

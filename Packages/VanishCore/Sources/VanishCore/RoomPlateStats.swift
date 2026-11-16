import Foundation

public enum RoomPlateStats {
    /// Max share of person pixels allowed in an "empty room" snapshot.
    public static let maxPersonCoverage = 0.01

    /// Per-element median across equally sized samples (lower middle for even counts).
    /// Hot path for 1280×720×4 bytes × 15 frames: unsafe pointers + insertion sort on a tiny column.
    public static func median(_ samples: [[UInt8]]) -> [UInt8] {
        guard let first = samples.first else { return [] }
        let n = samples.count
        let count = first.count
        var out = [UInt8](repeating: 0, count: count)
        let mid = (n - 1) / 2
        // Pin all sample buffers.
        let pointers: [UnsafeMutablePointer<UInt8>] = samples.map { s in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            s.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: count) }
            return p
        }
        defer { pointers.forEach { $0.deallocate() } }
        let column = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
        defer { column.deallocate() }
        out.withUnsafeMutableBufferPointer { dst in
            for i in 0..<count {
                for s in 0..<n {
                    let v = pointers[s][i]
                    var j = s
                    while j > 0 && column[j - 1] > v {
                        column[j] = column[j - 1]
                        j -= 1
                    }
                    column[j] = v
                }
                dst[i] = column[mid]
            }
        }
        return out
    }

    public static func coverage(mask: [UInt8], threshold: UInt8) -> Double {
        guard !mask.isEmpty else { return 0 }
        let on = mask.reduce(0) { $0 + ($1 >= threshold ? 1 : 0) }
        return Double(on) / Double(mask.count)
    }

    public static func containsPerson(coverage: Double) -> Bool {
        coverage > maxPersonCoverage
    }
}

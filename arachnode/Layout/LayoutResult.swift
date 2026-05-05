import Foundation
import CoreGraphics

/// Output of the layout pipeline. `positions` are world-coord centers per
/// node ID; `regions` are the polygons each `CategoryKey` was allotted by
/// the partitioner. The renderer reads positions for every frame and reads
/// regions only when the "Show category regions" preference is on.
struct LayoutResult: Equatable {
    let positions: [UUID: CGPoint]
    let regions: [CategoryKey: Region]

    static let empty = LayoutResult(positions: [:], regions: [:])
}

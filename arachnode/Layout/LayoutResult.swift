import Foundation
import CoreGraphics

/// Output of the layout pipeline. `positions` are world-coord centers per
/// node ID; `radii` are display radii per node ID (computed by the
/// `LayoutController` from the active sizing mode and per-node value);
/// `regions` are the polygons each `CategoryKey` was allotted by the
/// partitioner. The renderer reads positions and radii every frame and
/// reads regions only when the "Show category regions" preference is on.
struct LayoutResult: Equatable {
    let positions: [UUID: CGPoint]
    let radii: [UUID: CGFloat]
    let regions: [CategoryKey: Region]

    static let empty = LayoutResult(positions: [:], radii: [:], regions: [:])
}

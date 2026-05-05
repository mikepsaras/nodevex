import Foundation
import CoreGraphics

/// Packs circles of given radii inside a `Region` polygon without overlap.
/// Returns world-coord centers per node ID.
///
/// If a region is over-saturated (the sum of circle areas exceeds the
/// region's area, or the geometry can't accommodate a particular circle
/// anywhere along the front), implementations may place that circle
/// overflowing the region. The renderer doesn't clip — overflow will be
/// visible to the user as a cue that their region is too small for its
/// node count. With node-count-weighted partitioning that should be rare.
protocol CirclePacker {
    func pack(
        nodes: [(id: UUID, radius: CGFloat)],
        in region: Region
    ) -> [UUID: CGPoint]
}

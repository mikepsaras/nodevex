import Foundation
import CoreGraphics

/// Partitions the layout `bounds` into one `Region` per `CategoryKey`
/// represented in the graph. The output map covers every key actually in
/// use — single-category, multi-category combinations, and uncategorized.
///
/// Implementations decide how seeds are positioned and how cells are
/// tessellated. The default `VoronoiPartitioner` uses a power-diagram
/// variant where cells are sized roughly proportionally to node count, so
/// a category with 200 nodes ends up with a noticeably larger cell than
/// one with 10.
protocol RegionPartitioner {
    func partition(graph: GraphSnapshot, bounds: CGRect) -> [CategoryKey: Region]
}

import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    let nodeRadius: CGFloat = 28

    func draw(in context: CGContext, bounds: CGRect, graph: GraphSnapshot, positions: [UUID: CGPoint]) {
        context.setFillColor(SemanticColors.AppKit.canvasBackground.cgColor)
        context.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            let canvasPos = CGPoint(x: center.x + pos.x, y: center.y + pos.y)
            drawNode(node, at: canvasPos, in: context)
        }
    }

    private func drawNode(_ node: Node, at point: CGPoint, in context: CGContext) {
        let rect = CGRect(
            x: point.x - nodeRadius,
            y: point.y - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )

        context.setFillColor(SemanticColors.AppKit.nodeFill.cgColor)
        context.fillEllipse(in: rect)

        context.setStrokeColor(SemanticColors.AppKit.nodeBorder.cgColor)
        context.setLineWidth(0.5)
        context.strokeEllipse(in: rect)

        let label = node.name as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: SemanticColors.AppKit.textPrimary
        ]
        let textSize = label.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: point.x - textSize.width / 2,
            y: point.y - textSize.height / 2
        )
        label.draw(at: textOrigin, withAttributes: attributes)
    }
}

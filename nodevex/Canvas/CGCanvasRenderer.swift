import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    let nodeRadius: CGFloat = 7
    let selectedNodeRadius: CGFloat = 8
    let nodeBorderWidth: CGFloat = 1.0
    let labelGap: CGFloat = 6
    let labelFontSize: CGFloat = 11
    let labelMaxWidth: CGFloat = 140

    func draw(
        in context: CGContext,
        bounds: CGRect,
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        selectedIDs: Set<UUID>
    ) {
        context.setFillColor(SemanticColors.AppKit.canvasBackground.cgColor)
        context.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            let canvasPos = CGPoint(x: center.x + pos.x, y: center.y + pos.y)
            drawNode(node, at: canvasPos, isSelected: selectedIDs.contains(node.id), in: context)
        }
    }

    private func drawNode(_ node: Node, at point: CGPoint, isSelected: Bool, in context: CGContext) {
        let radius = isSelected ? selectedNodeRadius : nodeRadius
        let circleRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // Filled circle.
        let fill = isSelected
            ? NSColor.controlAccentColor
            : NSColor.secondaryLabelColor
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: circleRect)

        // Subtle border for definition against the canvas background.
        context.setStrokeColor(SemanticColors.AppKit.nodeBorder.cgColor)
        context.setLineWidth(nodeBorderWidth)
        context.strokeEllipse(in: circleRect)

        drawLabel(node.name, below: point, radius: radius, isSelected: isSelected)
    }

    private func drawLabel(_ text: String, below point: CGPoint, radius: CGFloat, isSelected: Bool) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center

        let color = isSelected
            ? NSColor.labelColor
            : NSColor.secondaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: labelFontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.boundingRect(
            with: CGSize(width: labelMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).size
        let labelRect = CGRect(
            x: point.x - labelMaxWidth / 2,
            y: point.y + radius + labelGap,
            width: labelMaxWidth,
            height: textSize.height
        )
        attributed.draw(with: labelRect, options: [.usesLineFragmentOrigin], context: nil)
    }
}

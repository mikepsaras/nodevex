import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    let nodeWidth: CGFloat = 120
    let nodeHeight: CGFloat = 32
    let nodeCornerRadius: CGFloat = 16
    let nodeHorizontalPadding: CGFloat = 10
    let labelFontSize: CGFloat = 12

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
        let rect = CGRect(
            x: point.x - nodeWidth / 2,
            y: point.y - nodeHeight / 2,
            width: nodeWidth,
            height: nodeHeight
        )
        let pillPath = CGPath(
            roundedRect: rect,
            cornerWidth: nodeCornerRadius,
            cornerHeight: nodeCornerRadius,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 1),
            blur: 2,
            color: NSColor(white: 0, alpha: 0.08).cgColor
        )
        let fill = isSelected ? SemanticColors.AppKit.nodeFillSelected : SemanticColors.AppKit.nodeFill
        context.setFillColor(fill.cgColor)
        context.addPath(pillPath)
        context.fillPath()
        context.restoreGState()

        if isSelected {
            context.setStrokeColor(SemanticColors.AppKit.nodeBorderSelected.cgColor)
            context.setLineWidth(1.5)
        } else {
            context.setStrokeColor(SemanticColors.AppKit.nodeBorder.cgColor)
            context.setLineWidth(0.5)
        }
        context.addPath(pillPath)
        context.strokePath()

        drawLabel(node.name, in: rect)
    }

    private func drawLabel(_ text: String, in pillRect: CGRect) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: labelFontSize),
            .foregroundColor: SemanticColors.AppKit.textPrimary,
            .paragraphStyle: paragraphStyle
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let labelArea = pillRect.insetBy(dx: nodeHorizontalPadding, dy: 0)
        let textSize = attributed.boundingRect(
            with: CGSize(width: labelArea.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).size
        let drawRect = CGRect(
            x: labelArea.minX,
            y: pillRect.midY - textSize.height / 2,
            width: labelArea.width,
            height: textSize.height
        )
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)
    }
}

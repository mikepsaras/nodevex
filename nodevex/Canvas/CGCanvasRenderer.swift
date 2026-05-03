import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    let nodeRadius: CGFloat = 7
    let selectedNodeRadius: CGFloat = 8
    let nodeBorderWidth: CGFloat = 1.0
    let labelGap: CGFloat = 6
    let labelFontSize: CGFloat = 11
    let labelMaxWidth: CGFloat = 140

    let edgeGap: CGFloat = 3  // gap between line endpoint and node circle
    let arrowSize: CGFloat = 7
    let edgeLineWidth: CGFloat = 1.5
    // Strength is *not* encoded as line width per ADR-0006 — it's encoded as
    // animation speed. Until the animation pipeline lands, edges of any strength
    // render at the same thickness.

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

        // Edges first so nodes paint on top of any line ends near a circle.
        for edge in graph.edges {
            guard let sourcePos = positions[edge.sourceID],
                  let targetPos = positions[edge.targetID] else { continue }
            let canvasSource = CGPoint(x: center.x + sourcePos.x, y: center.y + sourcePos.y)
            let canvasTarget = CGPoint(x: center.x + targetPos.x, y: center.y + targetPos.y)
            drawEdge(edge, from: canvasSource, to: canvasTarget, in: context)
        }

        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            let canvasPos = CGPoint(x: center.x + pos.x, y: center.y + pos.y)
            drawNode(node, at: canvasPos, isSelected: selectedIDs.contains(node.id), in: context)
        }
    }

    private func drawEdge(_ edge: Edge, from sourcePos: CGPoint, to targetPos: CGPoint, in context: CGContext) {
        let dx = targetPos.x - sourcePos.x
        let dy = targetPos.y - sourcePos.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > nodeRadius * 2 + edgeGap * 2 + arrowSize else { return }
        let unitX = dx / distance
        let unitY = dy / distance

        let startInset = nodeRadius + edgeGap
        let endInset = nodeRadius + edgeGap
        let lineStart = CGPoint(
            x: sourcePos.x + unitX * startInset,
            y: sourcePos.y + unitY * startInset
        )
        let lineEnd = CGPoint(
            x: targetPos.x - unitX * endInset,
            y: targetPos.y - unitY * endInset
        )

        let color = edgeColor(for: edge.valence)

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(edgeLineWidth)
        context.setLineCap(.round)
        context.move(to: lineStart)
        context.addLine(to: lineEnd)
        context.strokePath()

        // Filled triangle arrowhead at the target end.
        let backCenter = CGPoint(
            x: lineEnd.x - unitX * arrowSize,
            y: lineEnd.y - unitY * arrowSize
        )
        let perpX = -unitY
        let perpY = unitX
        let halfBase = arrowSize * 0.5
        let v1 = CGPoint(
            x: backCenter.x + perpX * halfBase,
            y: backCenter.y + perpY * halfBase
        )
        let v2 = CGPoint(
            x: backCenter.x - perpX * halfBase,
            y: backCenter.y - perpY * halfBase
        )
        context.setFillColor(color.cgColor)
        context.move(to: lineEnd)
        context.addLine(to: v1)
        context.addLine(to: v2)
        context.closePath()
        context.fillPath()
    }

    private func edgeColor(for valence: EdgeValence) -> NSColor {
        switch valence {
        case .positive: SemanticColors.AppKit.edgePositive
        case .negative: SemanticColors.AppKit.edgeNegative
        case .neutral: SemanticColors.AppKit.edgeDefault
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

        let fill = isSelected
            ? NSColor.controlAccentColor
            : NSColor.secondaryLabelColor
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: circleRect)

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

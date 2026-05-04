import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    let nodeRadius: CGFloat = 7
    let selectedNodeRadius: CGFloat = 8
    let nodeBorderWidth: CGFloat = 1.0
    let labelGap: CGFloat = 6
    let labelFontSize: CGFloat = 11
    let labelMaxWidth: CGFloat = 140

    let edgeGap: CGFloat = 3
    let arrowSize: CGFloat = 9
    let edgeLineWidth: CGFloat = 1.5
    let arrowsPerAnimatedEdge = 3

    func draw(
        in context: CGContext,
        bounds: CGRect,
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        selectedIDs: Set<UUID>,
        edgeVisibility: EdgeVisibilityMode,
        animationPhase: CGFloat
    ) {
        context.setFillColor(SemanticColors.AppKit.canvasBackground.cgColor)
        context.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        if edgeVisibility != .hidden {
            for edge in graph.edges {
                guard let sourcePos = positions[edge.sourceID],
                      let targetPos = positions[edge.targetID] else { continue }
                let canvasSource = CGPoint(x: center.x + sourcePos.x, y: center.y + sourcePos.y)
                let canvasTarget = CGPoint(x: center.x + targetPos.x, y: center.y + targetPos.y)
                drawEdge(
                    edge,
                    from: canvasSource,
                    to: canvasTarget,
                    visibility: edgeVisibility,
                    animationPhase: animationPhase,
                    in: context
                )
            }
        }

        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            let canvasPos = CGPoint(x: center.x + pos.x, y: center.y + pos.y)
            drawNode(node, at: canvasPos, isSelected: selectedIDs.contains(node.id), in: context)
        }
    }

    private func drawEdge(
        _ edge: Edge,
        from sourcePos: CGPoint,
        to targetPos: CGPoint,
        visibility: EdgeVisibilityMode,
        animationPhase: CGFloat,
        in context: CGContext
    ) {
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

        // Line ends at arrow base in static mode (so the triangle is "added on"
        // with no overlap). In animated mode, line goes the full length and
        // flowing trapezoids are sprinkled along it.
        let lineDrawingEnd: CGPoint
        switch visibility {
        case .hidden:
            return
        case .staticVisible:
            lineDrawingEnd = CGPoint(
                x: lineEnd.x - unitX * arrowSize,
                y: lineEnd.y - unitY * arrowSize
            )
        case .animated:
            lineDrawingEnd = lineEnd
        }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(edgeLineWidth)
        context.setLineCap(.butt)
        context.move(to: lineStart)
        context.addLine(to: lineDrawingEnd)
        context.strokePath()

        switch visibility {
        case .hidden:
            return
        case .staticVisible:
            drawArrowhead(
                at: lineEnd,
                direction: (unitX, unitY),
                size: arrowSize,
                color: color,
                in: context
            )
        case .animated:
            let speed = 0.2 + CGFloat(edge.strength) * 0.8
            let spacing = 1.0 / CGFloat(arrowsPerAnimatedEdge)
            let fadeRange: CGFloat = 0.3
            for i in 0..<arrowsPerAnimatedEdge {
                let baseOffset = spacing * CGFloat(i)
                let progress = (baseOffset + animationPhase * speed).truncatingRemainder(dividingBy: 1.0)
                let arrowPos = CGPoint(
                    x: lineStart.x + (lineEnd.x - lineStart.x) * progress,
                    y: lineStart.y + (lineEnd.y - lineStart.y) * progress
                )
                let opacity: CGFloat
                if progress < fadeRange {
                    opacity = progress / fadeRange
                } else if progress > 1 - fadeRange {
                    opacity = (1 - progress) / fadeRange
                } else {
                    opacity = 1.0
                }
                let smoothed = opacity * opacity * (3 - 2 * opacity)
                let fadedColor = color.withAlphaComponent(smoothed)
                drawArrowhead(
                    at: arrowPos,
                    direction: (unitX, unitY),
                    size: arrowSize,
                    color: fadedColor,
                    in: context
                )
            }
        }
    }

    private func drawArrowhead(
        at tip: CGPoint,
        direction: (CGFloat, CGFloat),
        size: CGFloat,
        color: NSColor,
        in context: CGContext
    ) {
        let (unitX, unitY) = direction
        let backCenter = CGPoint(
            x: tip.x - unitX * size,
            y: tip.y - unitY * size
        )
        let perpX = -unitY
        let perpY = unitX
        let halfBase = size * 0.5
        let v1 = CGPoint(
            x: backCenter.x + perpX * halfBase,
            y: backCenter.y + perpY * halfBase
        )
        let v2 = CGPoint(
            x: backCenter.x - perpX * halfBase,
            y: backCenter.y - perpY * halfBase
        )
        context.setFillColor(color.cgColor)
        context.move(to: tip)
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

        let fill = nodeFillColor(for: node, isSelected: isSelected)
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: circleRect)

        context.setStrokeColor(SemanticColors.AppKit.nodeBorder.cgColor)
        context.setLineWidth(nodeBorderWidth)
        context.strokeEllipse(in: circleRect)

        if node.isPinned {
            drawPinGlyph(at: point, nodeRadius: radius, in: context)
        }

        drawLabel(node.name, below: point, radius: radius, isSelected: isSelected)
    }

    /// A barely-there pin marker at the upper-right of the node circle: a small
    /// filled head plus a short stub tail. Manually drawn rather than rendering
    /// SF Symbol `pin.fill` because tinting symbols inside a flipped CGContext
    /// is fiddly and the visual goal is "just enough to know it's pinned".
    private func drawPinGlyph(at nodeCenter: CGPoint, nodeRadius: CGFloat, in context: CGContext) {
        let offsetX = nodeRadius * 0.75
        let offsetY = nodeRadius * 0.95
        let cx = nodeCenter.x + offsetX
        let cy = nodeCenter.y - offsetY

        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.7)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)

        let headRadius: CGFloat = 1.6
        context.fillEllipse(in: CGRect(
            x: cx - headRadius,
            y: cy - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))

        context.setLineWidth(1.0)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: cx, y: cy + headRadius - 0.3))
        context.addLine(to: CGPoint(x: cx, y: cy + headRadius + 2.0))
        context.strokePath()
    }

    private func nodeFillColor(for node: Node, isSelected: Bool) -> NSColor {
        if isSelected {
            return .controlAccentColor
        }
        if let firstCategory = node.categories.first {
            return firstCategory.nsDisplayColor
        }
        return .secondaryLabelColor
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

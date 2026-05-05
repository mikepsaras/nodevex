import AppKit
import CoreGraphics

final class CGCanvasRenderer: CanvasRenderer {
    /// +1pt over the node's base radius. Additive (rather than ratio) so the
    /// selection cue reads consistently across fixed and value-scaled sizes.
    let selectedRadiusBump: CGFloat = 1
    let nodeBorderWidth: CGFloat = 1.0
    let labelGap: CGFloat = 6
    let labelFontSize: CGFloat = 11
    let labelMaxWidth: CGFloat = 140

    let edgeGap: CGFloat = 3
    let arrowSize: CGFloat = 9
    let edgeLineWidth: CGFloat = 1.5
    let arrowsPerAnimatedEdge = 3

    /// Per-(name, selection) label-image cache. Core Text layout +
    /// `NSAttributedString.draw(...)` is the dominant cost when redrawing the
    /// canvas at 60 fps with many nodes — this caches a pre-rasterized
    /// `NSImage` per unique label so subsequent frames just blit a bitmap.
    /// Entries persist for the lifetime of the renderer; renames produce a
    /// new key (the old entry becomes orphaned but is bounded by the number
    /// of names ever used in this session).
    private struct LabelCacheKey: Hashable {
        let name: String
        let isSelected: Bool
    }
    private var labelCache: [LabelCacheKey: NSImage] = [:]

    func draw(
        in context: CGContext,
        bounds: CGRect,
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        regions: [CategoryKey: Region],
        radii: [UUID: CGFloat],
        selectedIDs: Set<UUID>,
        highlightedNodeID: UUID?,
        revealedNodeID: UUID?,
        revealOpacity: CGFloat,
        edgeVisibility: EdgeVisibilityMode,
        animationPhase: CGFloat,
        zoom: CGFloat,
        appearanceMode: AppearanceMode,
        showRegions: Bool
    ) {
        context.setFillColor(SemanticColors.AppKit.canvasBackground(for: appearanceMode).cgColor)
        context.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Optional category-region tints, drawn first so everything else
        // (edges, nodes, labels) layers on top. Off by default; toggled in
        // Settings → Layout → "Show category regions".
        if showRegions {
            for (key, region) in regions {
                drawRegionTint(region, key: key, graph: graph, in: context, atCenter: center)
            }
        }

        // Edge rendering: when global mode is hidden, only edges connected to
        // a hover/modal-revealed node draw, and they animate at `revealOpacity`.
        // When global mode is non-hidden (the experimental edge-visibility
        // toggle), render every edge per that mode — hover does nothing
        // additive there.
        for edge in graph.edges {
            let isRevealConnected = revealedNodeID != nil &&
                (edge.sourceID == revealedNodeID || edge.targetID == revealedNodeID)

            var effectiveVisibility: EdgeVisibilityMode
            let opacityScale: CGFloat
            if edgeVisibility == .hidden {
                guard isRevealConnected, revealOpacity > 0 else { continue }
                effectiveVisibility = .animated
                opacityScale = revealOpacity
            } else {
                effectiveVisibility = edgeVisibility
                opacityScale = 1.0
            }

            // LOD: animated arrowheads turn into sub-pixel noise far out.
            // Below 0.4× zoom, fall back to static rendering.
            if effectiveVisibility == .animated && zoom < 0.4 {
                effectiveVisibility = .staticVisible
            }

            guard let sourcePos = positions[edge.sourceID],
                  let targetPos = positions[edge.targetID] else { continue }
            let canvasSource = CGPoint(x: center.x + sourcePos.x, y: center.y + sourcePos.y)
            let canvasTarget = CGPoint(x: center.x + targetPos.x, y: center.y + targetPos.y)
            let sourceRadius = radii[edge.sourceID] ?? NodeSizingMode.defaultRadius
            let targetRadius = radii[edge.targetID] ?? NodeSizingMode.defaultRadius
            drawEdge(
                edge,
                from: canvasSource,
                to: canvasTarget,
                sourceRadius: sourceRadius,
                targetRadius: targetRadius,
                visibility: effectiveVisibility,
                opacityScale: opacityScale,
                animationPhase: animationPhase,
                in: context
            )
        }

        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            let canvasPos = CGPoint(x: center.x + pos.x, y: center.y + pos.y)
            let baseRadius = radii[node.id] ?? NodeSizingMode.defaultRadius
            drawNode(
                node,
                at: canvasPos,
                baseRadius: baseRadius,
                isSelected: selectedIDs.contains(node.id),
                isHighlighted: highlightedNodeID == node.id,
                showLabel: zoom >= 0.5,
                in: context
            )
        }
    }

    private func drawEdge(
        _ edge: Edge,
        from sourcePos: CGPoint,
        to targetPos: CGPoint,
        sourceRadius: CGFloat,
        targetRadius: CGFloat,
        visibility: EdgeVisibilityMode,
        opacityScale: CGFloat,
        animationPhase: CGFloat,
        in context: CGContext
    ) {
        if edge.sourceID == edge.targetID {
            let color = edgeColor(for: edge.valence).withAlphaComponent(opacityScale)
            drawSelfLoop(at: sourcePos, nodeRadius: sourceRadius, color: color, in: context)
            return
        }

        let dx = targetPos.x - sourcePos.x
        let dy = targetPos.y - sourcePos.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > sourceRadius + targetRadius + edgeGap * 2 + arrowSize else { return }
        let unitX = dx / distance
        let unitY = dy / distance

        let startInset = sourceRadius + edgeGap
        let endInset = targetRadius + edgeGap
        let lineStart = CGPoint(
            x: sourcePos.x + unitX * startInset,
            y: sourcePos.y + unitY * startInset
        )
        let lineEnd = CGPoint(
            x: targetPos.x - unitX * endInset,
            y: targetPos.y - unitY * endInset
        )

        let color = edgeColor(for: edge.valence).withAlphaComponent(opacityScale)

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
                let fadedColor = color.withAlphaComponent(smoothed * opacityScale)
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

    /// Self-loop rendering: a small stroked circle sitting on top of the
    /// node. Visibility mode is ignored — animated arrowheads on a tiny
    /// closed loop don't read well, so we keep it static regardless.
    private func drawSelfLoop(at point: CGPoint, nodeRadius: CGFloat, color: NSColor, in context: CGContext) {
        let loopRadius: CGFloat = 8
        // isFlipped: true ⇒ smaller y is visually higher.
        let loopCenter = CGPoint(x: point.x, y: point.y - nodeRadius - loopRadius)
        let rect = CGRect(
            x: loopCenter.x - loopRadius,
            y: loopCenter.y - loopRadius,
            width: 2 * loopRadius,
            height: 2 * loopRadius
        )
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(edgeLineWidth)
        context.strokeEllipse(in: rect)
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

    /// Fill a Voronoi cell polygon with a faint tint of its category color.
    /// Combination cells (multi-category nodes) blend the constituent
    /// category colors via simple sRGB averaging; uncategorized cells use
    /// `secondaryLabelColor`. Alpha is intentionally low so the tint reads
    /// as atmospheric backdrop rather than a competing visual layer.
    private func drawRegionTint(
        _ region: Region,
        key: CategoryKey,
        graph: GraphSnapshot,
        in context: CGContext,
        atCenter center: CGPoint
    ) {
        let polygon = region.polygon
        guard polygon.count >= 3 else { return }
        let color = regionColor(for: key, graph: graph).withAlphaComponent(0.08)
        context.setFillColor(color.cgColor)
        context.beginPath()
        for (i, vertex) in polygon.enumerated() {
            let canvasVertex = CGPoint(
                x: center.x + vertex.x,
                y: center.y + vertex.y
            )
            if i == 0 {
                context.move(to: canvasVertex)
            } else {
                context.addLine(to: canvasVertex)
            }
        }
        context.closePath()
        context.fillPath()
    }

    /// Resolve a `CategoryKey` to a tint color. Single-category cells use
    /// the category's display color; combinations average their constituents
    /// in sRGB; uncategorized falls back to a neutral gray.
    private func regionColor(for key: CategoryKey, graph: GraphSnapshot) -> NSColor {
        switch key {
        case .uncategorized:
            return .secondaryLabelColor
        case .single(let id):
            return graph.categories.first(where: { $0.id == id })?.nsDisplayColor
                ?? .secondaryLabelColor
        case .combination(let ids):
            var rSum: CGFloat = 0
            var gSum: CGFloat = 0
            var bSum: CGFloat = 0
            var count = 0
            for id in ids {
                guard let cat = graph.categories.first(where: { $0.id == id }) else { continue }
                let nsColor = cat.nsDisplayColor.usingColorSpace(.sRGB) ?? cat.nsDisplayColor
                rSum += nsColor.redComponent
                gSum += nsColor.greenComponent
                bSum += nsColor.blueComponent
                count += 1
            }
            guard count > 0 else { return .secondaryLabelColor }
            let n = CGFloat(count)
            return NSColor(
                srgbRed: rSum / n,
                green: gSum / n,
                blue: bSum / n,
                alpha: 1
            )
        }
    }

    private func drawNode(
        _ node: Node,
        at point: CGPoint,
        baseRadius: CGFloat,
        isSelected: Bool,
        isHighlighted: Bool,
        showLabel: Bool,
        in context: CGContext
    ) {
        let radius = isSelected ? baseRadius + selectedRadiusBump : baseRadius
        let circleRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let fill = nodeFillColor(for: node, isSelected: isSelected, isHighlighted: isHighlighted)
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: circleRect)

        context.setStrokeColor(SemanticColors.AppKit.nodeBorder.cgColor)
        context.setLineWidth(nodeBorderWidth)
        context.strokeEllipse(in: circleRect)

        guard showLabel else { return }
        // Hover: shift the label down by 2pt as a quiet responsiveness cue.
        let labelExtraGap: CGFloat = isHighlighted ? 2 : 0
        drawLabel(
            node.name,
            below: point,
            radius: radius,
            isSelected: isSelected,
            extraGap: labelExtraGap
        )
    }

    private func nodeFillColor(for node: Node, isSelected: Bool, isHighlighted: Bool) -> NSColor {
        if isSelected {
            return .controlAccentColor
        }
        let base: NSColor
        if let firstCategory = node.categories.first {
            base = firstCategory.nsDisplayColor
        } else {
            base = .secondaryLabelColor
        }
        // Hover lifts the fill toward white for a "lit" feeling.
        return isHighlighted ? (base.blended(withFraction: 0.35, of: .white) ?? base) : base
    }

    private func drawLabel(
        _ text: String,
        below point: CGPoint,
        radius: CGFloat,
        isSelected: Bool,
        extraGap: CGFloat
    ) {
        let key = LabelCacheKey(name: text, isSelected: isSelected)
        let image: NSImage
        if let cached = labelCache[key] {
            image = cached
        } else if let new = renderLabelImage(name: text, isSelected: isSelected) {
            labelCache[key] = new
            image = new
        } else {
            return
        }

        let size = image.size
        let labelRect = CGRect(
            x: point.x - size.width / 2,
            y: point.y + radius + labelGap + extraGap,
            width: size.width,
            height: size.height
        )
        // `respectFlipped: true` so the bitmap renders right-side-up in the
        // CanvasNSView's flipped coordinate system without extra transforms.
        image.draw(
            in: labelRect,
            from: CGRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }

    private func renderLabelImage(name: String, isSelected: Bool) -> NSImage? {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center

        let color = isSelected
            ? NSColor.labelColor
            : NSColor.secondaryLabelColor
        let attributed = NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: labelFontSize),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )

        let textSize = attributed.boundingRect(
            with: CGSize(width: labelMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).size
        let size = CGSize(
            width: ceil(textSize.width),
            height: ceil(textSize.height)
        )
        guard size.width > 0, size.height > 0 else { return nil }

        let image = NSImage(size: size)
        image.lockFocus()
        attributed.draw(
            with: CGRect(origin: .zero, size: size),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        image.unlockFocus()
        return image
    }
}

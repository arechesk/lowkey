import AppKit

/// Line icons drawn from a 16×16 grid (y grows downward), matching the design prototype.
enum Glyph {
    case close
    /// A small round "q": closes a site for good.
    case terminate
    case back
    case forward
    /// An arrow to a bar (⇤): back to the configured start URL. Simple enough to read at 9 px.
    case start
    case lock

    func draw(in rect: NSRect, color: NSColor, background: NSColor, lineWidth: CGFloat = 1.6) {
        let scale = min(rect.width, rect.height) / 16
        let origin = NSPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        let path = NSBezierPath()
        path.lineWidth = lineWidth * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        func line(_ points: (CGFloat, CGFloat)...) {
            path.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { path.line(to: p(point.0, point.1)) }
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
            let c = NSBezierPath(ovalIn: NSRect(x: origin.x + (cx - r) * scale, y: origin.y + (cy - r) * scale,
                                                width: 2 * r * scale, height: 2 * r * scale))
            c.lineWidth = path.lineWidth
            return c
        }

        color.setStroke()
        switch self {
        case .close:
            line((4, 4), (12, 12))
            line((12, 4), (4, 12))
        case .terminate:
            circle(7, 7, 4.5).stroke()
            line((10.2, 10.2), (13.5, 13.5))
        case .back:
            line((10, 3), (5, 8), (10, 13))
        case .forward:
            line((6, 3), (11, 8), (6, 13))
        case .start:
            line((3, 3), (3, 13))
            line((13.5, 8), (6, 8))
            line((9.5, 4.5), (6, 8), (9.5, 11.5))
        case .lock:
            let body = NSBezierPath(roundedRect: NSRect(x: origin.x + 4 * scale, y: origin.y + 7 * scale,
                                                        width: 8 * scale, height: 7 * scale),
                                    xRadius: 1.5 * scale, yRadius: 1.5 * scale)
            body.lineWidth = path.lineWidth
            body.stroke()
            path.move(to: p(5.5, 7))
            path.line(to: p(5.5, 4.5))
            path.appendArc(withCenter: p(8, 4.5), radius: 2.5 * scale, startAngle: 180, endAngle: 0, clockwise: false)
            path.line(to: p(10.5, 7))
        }
        path.stroke()
    }
}

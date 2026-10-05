import AppKit

/// Monochrome template version of the app icon for the menu bar: an iPhone in
/// front of a Mac display, both showing the same smiling face.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Display, with the area behind the phone knocked out.
            NSGraphicsContext.saveGraphicsState()
            let visible = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 22, height: 18))
            visible.append(NSBezierPath(roundedRect: NSRect(x: 0, y: 4, width: 9.5, height: 14), xRadius: 2.6, yRadius: 2.6))
            visible.windingRule = .evenOdd
            visible.addClip()
            let display = NSBezierPath(roundedRect: NSRect(x: 6.25, y: 1.75, width: 15, height: 10.5), xRadius: 2.2, yRadius: 2.2)
            display.lineWidth = 1.5
            display.stroke()
            let neck = NSBezierPath()
            neck.move(to: NSPoint(x: 13.75, y: 12.5))
            neck.line(to: NSPoint(x: 13.75, y: 14.75))
            neck.lineWidth = 1.5
            neck.stroke()
            NSGraphicsContext.restoreGraphicsState()

            NSBezierPath(roundedRect: NSRect(x: 11, y: 14.5, width: 5.5, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            drawFace(eyes: [NSPoint(x: 13.6, y: 6), NSPoint(x: 17.2, y: 6)], eyeRadius: 0.95,
                     smileFrom: NSPoint(x: 13.5, y: 8.4), control: NSPoint(x: 15.4, y: 10.4),
                     to: NSPoint(x: 17.3, y: 8.4), lineWidth: 1.1)

            let phone = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 5.25, width: 7, height: 11.5), xRadius: 1.9, yRadius: 1.9)
            phone.lineWidth = 1.5
            phone.stroke()
            drawFace(eyes: [NSPoint(x: 3.7, y: 10.3), NSPoint(x: 5.8, y: 10.3)], eyeRadius: 0.7,
                     smileFrom: NSPoint(x: 3.6, y: 12.2), control: NSPoint(x: 4.75, y: 13.4),
                     to: NSPoint(x: 5.9, y: 12.2), lineWidth: 0.9)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "iMirror"
        return image
    }()

    private static func drawFace(
        eyes: [NSPoint],
        eyeRadius: CGFloat,
        smileFrom start: NSPoint,
        control: NSPoint,
        to end: NSPoint,
        lineWidth: CGFloat
    ) {
        for eye in eyes {
            NSBezierPath(ovalIn: NSRect(
                x: eye.x - eyeRadius,
                y: eye.y - eyeRadius,
                width: eyeRadius * 2,
                height: eyeRadius * 2
            )).fill()
        }
        // Quadratic curve expressed as the equivalent cubic.
        let smile = NSBezierPath()
        smile.move(to: start)
        smile.curve(
            to: end,
            controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3, y: start.y + (control.y - start.y) * 2 / 3),
            controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3, y: end.y + (control.y - end.y) * 2 / 3)
        )
        smile.lineWidth = lineWidth
        smile.lineCapStyle = .round
        smile.stroke()
    }
}

import CoreGraphics

enum MirrorWindowSizing {
    static func sizePreservingArea(
        currentSize: CGSize,
        aspectRatio: CGFloat,
        minimumSize: CGSize,
        maximumSize: CGSize
    ) -> CGSize {
        guard currentSize.width > 0,
              currentSize.height > 0,
              aspectRatio > 0,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return currentSize
        }

        let area = currentSize.width * currentSize.height
        var width = sqrt(area * aspectRatio)
        var height = width / aspectRatio

        let minimumScale = max(
            1,
            minimumSize.width / width,
            minimumSize.height / height
        )
        width *= minimumScale
        height *= minimumScale

        let maximumScale = min(
            1,
            maximumSize.width / width,
            maximumSize.height / height
        )
        return CGSize(width: width * maximumScale, height: height * maximumScale)
    }

    /// The largest rectangle with the content's aspect ratio that fits inside
    /// `bounds`, centered and snapped to whole pixels. Used as the Metal
    /// viewport so the picture is letterboxed instead of stretched when the
    /// window is maximized, tiled or full screen.
    static func aspectFitRect(content: CGSize, in bounds: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let width = min(bounds.width, (content.width * scale).rounded())
        let height = min(bounds.height, (content.height * scale).rounded())
        return CGRect(
            x: ((bounds.width - width) / 2).rounded(.down),
            y: ((bounds.height - height) / 2).rounded(.down),
            width: width,
            height: height
        )
    }
}

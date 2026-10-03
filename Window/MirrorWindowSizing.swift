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
}

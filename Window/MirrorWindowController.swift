import AppKit

@MainActor
final class MirrorWindowController: NSWindowController {
    private let pipeline: VideoPipeline
    private let surface: MirrorContainerView
    private let onClose: () -> Void
    private var currentAspectRatio: CGFloat = 9.0 / 16.0
    private var cascadeOffset = NSSize.zero

    var isAlwaysOnTop: Bool {
        get { window?.level == .floating }
        set {
            window?.level = newValue ? .floating : .normal
            surface.setPinned(newValue)
        }
    }

    init(
        pipeline: VideoPipeline,
        alwaysOnTop: Bool,
        title: String,
        onClose: @escaping () -> Void
    ) throws {
        self.pipeline = pipeline
        self.surface = MirrorContainerView(videoView: try MetalVideoView(renderFrame: .zero))
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 640),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = surface
        window.title = title
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = NSSize(width: 220, height: 220)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        window.animationBehavior = .documentWindow

        super.init(window: window)
        isAlwaysOnTop = alwaysOnTop
        wireActions()
        wirePipeline()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSession(cascadeIndex: Int) {
        let offset = CGFloat(min(cascadeIndex, 6)) * 28
        cascadeOffset = NSSize(width: offset, height: -offset)
        showWindow(nil)
        window?.center()
        applyCascadeOffset()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func endSession() {
        window?.orderOut(nil)
        pipeline.reset()
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    private func wireActions() {
        surface.onClose = { [weak self] in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.onClose()
        }
        surface.onTogglePin = { [weak self] in self?.toggleAlwaysOnTop() }
        surface.onToggleFullScreen = { [weak self] in self?.toggleFullScreen() }
    }

    private func wirePipeline() {
        pipeline.onFrame = { [weak self] frame in
            guard let self else { return }
            self.surface.present(frame.pixelBuffer)
            self.applyVideoSize(frame.size, firstFrame: frame.isFirstFrame)
        }
    }

    private func applyVideoSize(_ videoSize: CGSize, firstFrame: Bool) {
        guard videoSize.width > 0, videoSize.height > 0, let window else { return }
        let aspectRatio = videoSize.width / videoSize.height
        window.contentAspectRatio = videoSize

        if firstFrame {
            currentAspectRatio = aspectRatio
            fitInitialWindow(videoSize: videoSize)
            return
        }

        guard abs(aspectRatio - currentAspectRatio) > 0.01 else { return }
        currentAspectRatio = aspectRatio
        guard !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main else { return }

        let visibleSize = screen.visibleFrame.insetBy(dx: 32, dy: 32).size
        let targetContentSize = MirrorWindowSizing.sizePreservingArea(
            currentSize: window.contentLayoutRect.size,
            aspectRatio: aspectRatio,
            minimumSize: window.minSize,
            maximumSize: visibleSize
        )
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        targetFrame.origin = NSPoint(
            x: center.x - targetFrame.width / 2,
            y: center.y - targetFrame.height / 2
        )
        window.setFrame(targetFrame, display: true, animate: true)
        keepWindowInsideVisibleScreen()
    }

    private func fitInitialWindow(videoSize: CGSize) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 32, dy: 32).size
        let scale = min(1, available.width / videoSize.width, available.height / videoSize.height)
        let target = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
        window.setContentSize(target)
        window.center()
        applyCascadeOffset()
        keepWindowInsideVisibleScreen()
    }

    private func applyCascadeOffset() {
        guard let window else { return }
        var origin = window.frame.origin
        origin.x += cascadeOffset.width
        origin.y += cascadeOffset.height
        window.setFrameOrigin(origin)
    }

    private func keepWindowInsideVisibleScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        var frame = window.frame
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        window.setFrameOrigin(frame.origin)
    }
}

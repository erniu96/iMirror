import AppKit
import CoreVideo

final class MirrorContainerView: NSView {
    var onClose: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?

    private let videoView: MetalVideoView
    private let controls = HoverControlsView()
    private var trackingAreaReference: NSTrackingArea?

    init(videoView: MetalVideoView) {
        self.videoView = videoView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        videoView.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)
        addSubview(controls)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        ])

        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onTogglePin = { [weak self] in self?.onTogglePin?() }
        controls.onToggleFullScreen = { [weak self] in self?.onToggleFullScreen?() }
        controls.setVisible(false, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ pixelBuffer: CVPixelBuffer) {
        videoView.present(pixelBuffer)
    }

    func setPinned(_ pinned: Bool) {
        controls.setPinned(pinned)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        controls.setVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        controls.setVisible(false, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class HoverControlsView: NSVisualEffectView {
    var onClose: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?

    private let pinButton: NSButton

    init() {
        let closeButton = Self.makeButton(symbol: "xmark", tooltip: "停止此设备投屏")
        pinButton = Self.makeButton(symbol: "pin.fill", tooltip: "取消置顶")
        let fullScreenButton = Self.makeButton(
            symbol: "arrow.up.left.and.arrow.down.right",
            tooltip: "进入或退出全屏"
        )

        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        pinButton.target = self
        pinButton.action = #selector(pinPressed)
        fullScreenButton.target = self
        fullScreenButton.action = #selector(fullScreenPressed)

        let stack = NSStackView(views: [closeButton, pinButton, fullScreenButton])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPinned(_ pinned: Bool) {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.toolTip = pinned ? "取消置顶" : "保持置顶"
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        if visible { isHidden = false }
        let changes = { self.animator().alphaValue = visible ? 1 : 0 }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                changes()
            } completionHandler: { [weak self] in
                if !visible { self?.isHidden = true }
            }
        } else {
            alphaValue = visible ? 1 : 0
            isHidden = !visible
        }
    }

    @objc private func closePressed() { onClose?() }
    @objc private func pinPressed() { onTogglePin?() }
    @objc private func fullScreenPressed() { onToggleFullScreen?() }

    private static func makeButton(symbol: String, tooltip: String) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!,
            target: nil,
            action: nil
        )
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 27).isActive = true
        button.heightAnchor.constraint(equalToConstant: 27).isActive = true
        return button
    }
}

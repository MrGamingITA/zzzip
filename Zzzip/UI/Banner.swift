import AppKit

/// Non-modal notice at the top of a window ("Extracted to …  [Show in Finder]"). Hides itself after 6 s.
final class BannerView: NSView {
    private var actions: [() -> Void] = []

    init(message: String, symbol: String = "checkmark.circle.fill", tint: NSColor = .systemGreen, buttons: [(String, () -> Void)]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = tint
        let label = NSTextField(labelWithString: message)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [icon, label, NSView()]
        for (i, (title, action)) in buttons.enumerated() {
            actions.append(action)
            let b = NSButton(title: title, target: self, action: #selector(tapped(_:)))
            b.tag = i; b.bezelStyle = .push; b.controlSize = .small
            views.append(b)
        }
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close"))!, target: self, action: #selector(dismiss))
        close.isBordered = false
        views.append(close)
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.dismiss() }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped(_ b: NSButton) { actions[b.tag](); dismiss() }
    @objc func dismiss() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; self.animator().alphaValue = 0 }) { self.removeFromSuperview() }
    }
}

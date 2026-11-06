import AppKit

/// A sheet with a progress bar and a Cancel button. Shown only if the operation lasts more than 0.5 s.
final class ProgressSheet: NSWindowController {
    let bar = NSProgressIndicator()
    let label = NSTextField(labelWithString: "")
    let token = CancelToken()

    init(title: String) {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110), styleMask: [.titled, .docModalWindow], backing: .buffered, defer: false)
        super.init(window: w)
        label.stringValue = title
        label.lineBreakMode = .byTruncatingMiddle
        bar.isIndeterminate = true; bar.minValue = 0; bar.maxValue = 1; bar.style = .bar
        bar.startAnimation(nil)
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, bar, cancel])
        stack.orientation = .vertical; stack.alignment = .trailing; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        label.widthAnchor.constraint(equalToConstant: 340).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 340).isActive = true
        w.contentView = stack
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ v: Double) {
        if bar.isIndeterminate { bar.isIndeterminate = false; bar.stopAnimation(nil) }
        bar.doubleValue = v
    }

    @objc private func cancelPressed() { token.cancel(); label.stringValue = String(localized: "Cancelling…") }
}

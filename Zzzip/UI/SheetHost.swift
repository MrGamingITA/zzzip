import AppKit

/// Counts overlapping operations; the window is busy until the last one ends.
final class BusyCounter {
    private(set) var count = 0
    var isBusy: Bool { count > 0 }
    func begin() { count += 1 }
    func end() { count = max(0, count - 1) }
}

enum SheetHost {
    /// The window a new sheet must attach to: the deepest sheet already shown (e.g. the progress sheet), else the window.
    /// A second sheet on the same window is queued by AppKit and never appears while the first is up.
    static func host(for window: NSWindow) -> NSWindow {
        var w = window
        while let s = w.attachedSheet { w = s }
        return w
    }
}

extension SheetHost {
    /// Detaches any sheet already on `window` (the progress sheet) so a question can take its place, and returns the window.
    static func clear(_ window: NSWindow) -> NSWindow {
        while let s = window.attachedSheet { window.endSheet(s); s.orderOut(nil) }
        return window
    }
}
